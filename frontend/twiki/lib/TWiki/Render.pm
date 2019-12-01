# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2001-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

package TWiki::Render;

=pod

---+ package TWiki::Render

This module provides most of the actual HTML rendering code in TWiki.

=cut

use strict;
use Assert;
use Error qw(:try);

require TWiki::Time;

# Used to generate unique placeholders for when we lift blocks out of the
# text during rendering.
use vars qw( $placeholderMarker );
$placeholderMarker = 0;

# Used to generate unique anchors
my %anchornames = ();

# defaults for trunctation of summary text
my $TMLTRUNC = 162;
my $PLAINTRUNC = 70;
my $MINTRUNC = 16;
# max number of lines in a summary (best to keep it even)
my $SUMMARYLINES = 6;

# limiting lookbehind and lookahead for wikiwords and emphasis
# use like \b
#SMELL: they really limit the number of places emphasis can happen.
my $STARTWW = qr/^|(?<=[\s\(])/m;
my $ENDWW = qr/$|(?=[\s,.;:!?)])/m;

# marker used to tage the start of a table
my $TABLEMARKER = "\0\1\2TABLE\2\1\0";
# Marker used to indicate table rows that are valid header/footer rows
my $TRMARK = "is\1all\1th";

BEGIN {
    # Do a dynamic 'use locale' for this module
    if( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

=pod

---++ ClassMethod new ($session)

Creates a new renderer

=cut

sub new {
    my ( $class, $session ) = @_;
    my $this = bless( { session => $session }, $class );

    return $this;
}

=begin twiki

---++ ObjectMethod finish()
Break circular references.

=cut

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;
    undef $this->{NEWLINKFORMAT};
    undef $this->{LINKTOOLTIPINFO};
    undef $this->{SHOWTOPICTITLELINK};
    undef $this->{LIST};
    undef $this->{metaCache};
    undef $this->{formDefCache};
    undef $this->{session};
}

sub _newLinkFormat {
    my $this = shift;
    unless( $this->{NEWLINKFORMAT} ) {
        $this->{NEWLINKFORMAT} =
             $this->{session}->{prefs}->getPreferencesValue('NEWLINKFORMAT') ||
             '<span class="twikiNewLink"><a href="%SCRIPTURLPATH{edit}%/$web/$topic?topicparent=%WEB%.%TOPIC%" '
           . 'rel="nofollow" title="%MAKETEXT{"Create this topic"}%">'
           . '$text</a></span>';
    }
    return $this->{NEWLINKFORMAT};
}

=pod

---++ ObjectMethod renderParent($web, $topic, $meta, $params) -> $text

Render parent meta-data

=cut

sub renderParent {
    my( $this, $web, $topic, $meta, $ah ) = @_;
    my $dontRecurse = $ah->{dontrecurse} || 0;
    my $noWebHome =   $ah->{nowebhome} || 0;
    my $prefix =      $ah->{prefix} || '';
    my $suffix =      $ah->{suffix} || '';
    my $usesep =      $ah->{separator} || ' &gt; ';
    my $format =      $ah->{format} || '[[$web.$topic][$topic]]';

    return '' unless $web && $topic;

    my %visited;
    $visited{$web.'.'.$topic} = 1;

    my $pWeb = $web;
    my $pTopic;
    my $text = '';
    my $parentMeta = $meta->get( 'TOPICPARENT' );
    my $parent;
    my $store = $this->{session}->{store};

    $parent = $parentMeta->{name} if $parentMeta;

    my @stack;

    while( $parent ) {
        ( $pWeb, $pTopic ) = $this->{session}->normalizeWebTopicName( $pWeb, $parent );
        $parent = $pWeb.'.'.$pTopic;
        last if( $noWebHome &&
                 ( $pTopic eq $TWiki::cfg{HomeTopicName} ) ||
                 $visited{$parent} );
        $visited{$parent} = 1;
        $text = $format;
        $text =~ s/\$web/$pWeb/g;
        $text =~ s/\$topic/$pTopic/g;
        unshift( @stack, $text );
        last if $dontRecurse;
        $parent = $store->getTopicParent( $pWeb, $pTopic );
    }
    $text = join( $usesep, @stack );

    if( $text) {
        $text = $prefix.$text if ( $prefix );
        $text .= $suffix if ( $suffix );
    }

    return $text;
}

=pod

---++ ObjectMethod renderMoved($web, $topic, $meta, $params) -> $text

Render moved meta-data

=cut

sub renderMoved {
    my( $this, $web, $topic, $meta, $params ) = @_;
    my $text = '';
    my $moved = $meta->get( 'TOPICMOVED' );
    $web =~ s#\.#/#go;

    if( $moved ) {
        my( $fromWeb, $fromTopic ) = $this->{session}->normalizeWebTopicName( $web, $moved->{from} );
        my( $toWeb, $toTopic )     = $this->{session}->normalizeWebTopicName( $web, $moved->{to} );
        my $by = $moved->{by};
        my $u = $by;
        my $users = $this->{session}->{users};
        $by = $users->webDotWikiName($u) if $u;
        my $date = TWiki::Time::formatTime( $moved->{date}, '', 'gmtime' );

        # Only allow put back if current web and topic match stored information
        my $putBack = '';
        if( $web eq $toWeb && $topic eq $toTopic ) {
            $putBack = ' - '
            . '<form style="display:inline" method="post" action="'
                . $this->{session}->getScriptUrl( 0, 'rename', $web, $topic )
            . '">'
            . '<input type="hidden" name="newweb" value="' . $fromWeb . '"/>'
            . '<input type="hidden" name="newtopic" value="' . $fromTopic . '"/>'
            . '<input type="hidden" name="confirm" value="on"/>'
            . '<input type="hidden" name="nonwikiword" value="checked"/>'
            . '<input type="submit" name="submit" value="'
                . $this->{session}->i18n->maketext('put it back')
            . '" class="twikiButton"/>'
            . '</form>';
        }
        $text = CGI::i(
          $this->{session}->i18n->maketext("[_1] moved from [_2] on [_3] by [_4]",
                                             "<nop>$toWeb.<nop>$toTopic",
                                             "<nop>$fromWeb.<nop>$fromTopic",
                                             $date,
                                             $by)) . $putBack;
    }
    return $text;
}

# Add a list item, of the given type and indent depth. The list item may
# cause the opening or closing of lists currently being handled.
sub _addListItem {
    my( $this, $result, $type, $element, $indent ) = @_;

    $indent =~ s/   /\t/g;
    my $depth = length( $indent );

    my $size = scalar( @{$this->{LIST}} );

    # The whitespaces either side of the tags are required for the
    # emphasis REs to work.
    if( $size < $depth ) {
        my $firstTime = 1;
        while( $size < $depth ) {
            push( @{$this->{LIST}}, { type=>$type, element=>$element } );
            push @$result, ' <'.$element.">\n" unless( $firstTime );
            push @$result, ' <'.$type.">\n";
            $firstTime = 0;
            $size++;
        }
    } else {
        while( $size > $depth ) {
            my $tags = pop( @{$this->{LIST}} );
            push @$result, "\n</".$tags->{element}.'></'.$tags->{type}.'> ';
            $size--;
        }
        if( $size ) {
            push @$result, "\n</".$this->{LIST}->[$size-1]->{element}.'> ';
        } else {
            push @$result, "\n";
        }
    }

    if ( $size ) {
        my $oldt = $this->{LIST}->[$size-1];
        if( $oldt->{type} ne $type ) {
            push @$result, ' </'.$oldt->{type}.'><'.$type.">\n";
            pop( @{$this->{LIST}} );
            push( @{$this->{LIST}}, { type=>$type, element=>$element } );
        }
    }
}

# Given that we have just seen the end of a table, work out the thead,
# tbody and tfoot sections
sub _addTHEADandTFOOT {
    my( $lines ) = @_;
    # scan back to the head of the table
    my $i = scalar( @$lines ) - 1;
    my @thRows;
    my $inFoot = 1;
    my $footLines = 0;
    my $headLines = 0;
    while( $i >= 0 && $lines->[$i] ne $TABLEMARKER ) {
        if( $lines->[$i] =~ /^\s*$/ ) {
            # Remove blank lines in tables; they generate spurious <p>'s
            splice( @$lines, $i, 1 );
        }
        elsif( $lines->[$i] =~ s/$TRMARK=(["'])(.*?)\1//i) {
            if( $2 ) {
                if( $inFoot ) {
                    $footLines++;
                } else {
                    $headLines++;
                }
            } else {
                $inFoot = 0;
                $headLines = 0;
            }
        }
        $i--;
    }
    $lines->[$i] = CGI::start_table(
        { class=>'twikiTable',
          border => 1, cellspacing => 0, cellpadding => 0 });
    if( $footLines && !$headLines) {
        $headLines = $footLines;
        $footLines = 0;
    }
    if( $footLines ) {
        push( @$lines, '</tfoot>');
        my $firstFoot = scalar( @$lines ) - $footLines;
        splice( @$lines, $firstFoot, 0, '</tbody><tfoot>');
    } else {
        push( @$lines, '</tbody>');
    }
    if( $headLines ) {
        splice( @$lines, $i + 1 + $headLines, 0, '</thead><tbody>');
        splice( @$lines, $i + 1, 0, '<thead>');
    } else {
        splice( @$lines, $i + 1, 0, '<tbody>');
    }
}

sub _emitTR {
    my ( $this, $theRow ) = @_;

    $theRow =~ s/\t/   /g;  # change tabs to space
    $theRow =~ s/\s*$//;    # remove trailing spaces
    $theRow =~ s/(\|\|+)/'colspan'.$TWiki::TranslationToken.length($1).'|'/ge;  # calc COLSPAN
    my $cells = '';
    my $containsTableHeader;
    my $isAllTH = 1;
    foreach( split( /\|/, $theRow ) ) {
        my @attr;

        # Avoid matching single columns
        if ( s/colspan$TWiki::TranslationToken([0-9]+)//o ) {
            push( @attr, colspan => $1 );
        }
        s/^\s+$/ &nbsp; /;
        my( $l1, $l2 ) = ( 0, 0 );
        if( /^(\s*).*?(\s*)$/ ) {
            $l1 = length( $1 );
            $l2 = length( $2 );
        }
        if( $l1 >= 2 ) {
            if( $l2 <= 1 ) {
                push( @attr, align => 'right' );
            } else {
                push( @attr, align => 'center' );
            }
        }
        if( /^\s*\*(.*)\*\s*$/ ) {
            $cells .= CGI::th( { @attr }, CGI::strong( " $1 " ))."\n";
        } else {
            $cells .= CGI::td( { @attr }, " $_ " )."\n";
            $isAllTH = 0;
        }
    }
    return CGI::Tr({ $TRMARK => $isAllTH }, $cells );
}

sub _fixedFontText {
    my( $theText, $theDoBold ) = @_;
    # preserve white space, so replace it by '&nbsp; ' patterns
    $theText =~ s/\t/   /g;
    $theText =~ s|((?:[\s]{2})+)([^\s])|'&nbsp; ' x (length($1) / 2) . $2|eg;
    $theText = CGI->b( $theText ) if $theDoBold;
    return CGI->code( $theText );
}

# Build an HTML &lt;Hn> element with suitable anchor for linking from %<nop>TOC%
sub _makeAnchorHeading {
    my( $this, $text, $theLevel, $topic, $web ) = @_;
    $text =~ s/^\s*(.*?)\s*$/$1/;

    # - Build '<nop><h1><a name='atext'></a> heading </h1>' markup
    # - Initial '<nop>' is needed to prevent subsequent matches.
    # - filter out $TWiki::regex{headerPatternNoTOC} ( '!!' and '%NOTOC%' )
    my $anchorName = $this->makeUniqueAnchorName( $web, $topic, $text, 0 );
    #  if the generated uniqe anchor name is 'compatible', it won't change:
    my $compatAnchorName = $this->makeAnchorName( $anchorName, 1 );

    # filter '!!', '%NOTOC%'
    $text =~ s/$TWiki::regex{headerPatternNoTOC}//o;
    my $html = '<nop><h'.$theLevel.'>';
    $html .= CGI::a( { name => $anchorName }, '' );
    if( $compatAnchorName ne $anchorName ) {
        $compatAnchorName = $this->makeUniqueAnchorName( $web, $topic, $anchorName, 1 );
        $html .= CGI::a( { name => $compatAnchorName }, '');
    }
    $html .= ' '.$text.' </h'.$theLevel.'>';

    return $html;
}

=pod

---++ StaticMethod chompUtf8Fragment($str) -> $str

String truncation may happen in the middle of a UTF-8 byte sequence.
This function gets rid of the truncated fragment.

=cut

sub chompUtf8Fragment {
    my $str = shift;
    $str =~ /^((?:
        [\x00-\x7e] |
        [\xc2-\xdf][\x80-\xbf] |
        [\xe0-\xef][\x80-\xbf]{2} |
        [\xf0-\xf7][\x80-\xbf]{3}
    )+)/x;
    $str = $1;
    return defined($str) ? $str : '_';
}

=pod

---++ ObjectMethod makeAnchorName($anchorName, $compatibilityMode) -> $anchorName

   * =$anchorName= - the unprocessed anchor name
   * =$compatibilityMode= - SMELL: compatibility with *what*?? Who knows. :-(

Build a valid HTML anchor name

=cut

sub makeAnchorName {
    my( $this, $anchorName, $compatibilityMode ) = @_;

    if( !$compatibilityMode &&
          $anchorName =~ /^$TWiki::regex{anchorRegex}$/ ) {
        # accept, already valid -- just remove leading #
        return substr($anchorName, 1);
    }

    # strip out potential links so they don't get rendered.
    # remove double bracket link
    $anchorName =~ s/\[(?:\[.*?\])?\[(.*?)\]\s*\]/$1/g;
    # add an _ before bare WikiWords
    $anchorName =~ s/($TWiki::regex{wikiWordRegex})/_$1/go;

    if( $compatibilityMode ) {
        # remove leading/trailing underscores first, allowing them to be
        # reintroduced
        $anchorName =~ s/^[\s#_]*//;
        $anchorName =~ s/[\s_]*$//;
    }
    $anchorName =~ s/<\/?[a-zA-Z][^>]*>//gi;  # remove HTML tags
    $anchorName =~ s/&#?[a-zA-Z0-9]+;//g; # remove HTML entities
    $anchorName =~ s/&//g;                # remove &
    # filter TOC excludes if not at beginning
    $anchorName =~ s/^(.+?)\s*$TWiki::regex{headerPatternNoTOC}.*/$1/o;
    # filter '!!', '%NOTOC%'
    $anchorName =~ s/$TWiki::regex{headerPatternNoTOC}//o;

    # For most common alphabetic-only character encodings (i.e. iso-8859-*),
    # remove non-alpha characters
    if( !defined($TWiki::cfg{Site}{CharSet}) ||
          $TWiki::cfg{Site}{CharSet} =~ /^iso-?8859-?/i ) {
        $anchorName =~ s/[^$TWiki::regex{mixedAlphaNum}]+/_/g;
    }
    elsif ( $TWiki::cfg{Site}{CharSet} =~ /^utf.*8$|euc/i ) {
        $anchorName =~ s/[\x00-\x2f\x3a-\x40\x5b-\x60\x7b-\x7f]+/_/g;
    }
    $anchorName =~ s/__+/_/g;           # remove excessive '_' chars
    if ( !$compatibilityMode ) {
        $anchorName =~ s/^[\s#_]+//;  # no leading space nor '#', '_'
    }
    $anchorName =~ s/^(.{32})(.*)$/$1/; # limit to 32 chars
    if ( defined($TWiki::cfg{Site}{CharSet}) &&
         $TWiki::cfg{Site}{CharSet} =~ /^utf.*8/i
    ) {
        $anchorName = chompUtf8Fragment($anchorName);
    }
    if ( !$compatibilityMode ) {
        $anchorName =~ s/[\s_]+$//;    # no trailing space, nor '_'
    }

    # No need to encode 8-bit characters in anchor due to UTF-8 URL support

    return $anchorName;
}


# dispose of the set of known unique anchornames in order to inhibit the
# 'relabeling' of anchor names if the same topic is processed more than once,
# cf. explanation in TWiki::handleCommonTags()
sub _eraseAnchorNameMemory {
    %anchornames = ();
}


=pod

---++ ObjectMethod makeUniqueAnchorName($web, $topic, $anchorName, $compatibility) -> $anchorName

   * =$anchorName= - the unprocessed anchor name
   * =$compatibilityMode= - SMELL: compatibility with *what*?? Who knows. :-(

Build a valid HTML anchor name (unique w.r.t. the list stored in %anchornames)

=cut

sub makeUniqueAnchorName {
    my( $this, $web, $topic, $text, $compatibilityMode ) = @_;
    $web = '' if (!defined($web));
    $topic = '' if (!defined($topic));

    my $anchorName = $this->makeAnchorName( $text, $compatibilityMode );

    # ensure that the generated anchor name is unique
    my $cnt = 1;
    my $prefix = $web . '.' . $topic . '#';
    my $suffix = '';
    while (exists $anchornames{$prefix . $anchorName . $suffix}) {
        # $anchorName.$suffix must _always_ be 'compatible', or things would get complicated
        $suffix = '_AN' . $cnt++;
        # limit resulting name to 32 chars
        $anchorName = substr($anchorName, 0, 32 - length($suffix));
        # a UTF-8 character sequence might be truncated in the middle
        if ( defined($TWiki::cfg{Site}{CharSet}) &&
             $TWiki::cfg{Site}{CharSet} =~ /^utf.*8/i
        ) {
            $anchorName = chompUtf8Fragment($anchorName);
        }
        # this is only needed because '__' would not be 'compatible'
        $anchorName =~ s/_+$//g;
    }
    $anchorName .= $suffix;
    $anchornames{$prefix . $anchorName} = 1;

    return $anchorName;
}

# Returns =title='...'= tooltip info in case LINKTOOLTIPINFO perferences variable is set.
# Warning: Slower performance if enabled.
sub _linkToolTipInfo {
    my( $this, $theWeb, $theTopic ) = @_;
    unless( defined( $this->{LINKTOOLTIPINFO} )) {
        $this->{LINKTOOLTIPINFO} =
          $this->{session}->{prefs}->getPreferencesValue('LINKTOOLTIPINFO') || '';
        $this->{LINKTOOLTIPINFO} = '$username - $date - r$rev: $summary'
          if( 'on' eq lc($this->{LINKTOOLTIPINFO}) );
    }
    return '' unless( $this->{LINKTOOLTIPINFO} );
    return '' if( $this->{LINKTOOLTIPINFO} =~ /^off$/i );
    return '' unless( $this->{session}->inContext( 'view' ));

    # FIXME: This is slow, it can be improved by caching topic rev info and summary
    my $store = $this->{session}->{store};
    my $users = $this->{session}->{users};
    # SMELL: we ought not to have to fake this. Topic object model, please!!
    require TWiki::Meta;
    my $meta = new TWiki::Meta( $this->{session}, $theWeb, $theTopic );
    my( $date, $user, $rev ) = $meta->getRevisionInfo();
    my $text = $this->{LINKTOOLTIPINFO};
    $text =~ s/\$web/<nop>$theWeb/g;
    $text =~ s/\$topic/<nop>$theTopic/g;
    $text =~ s/\$rev/1.$rev/g;
    $text =~ s/\$date/TWiki::Time::formatTime( $date )/ge;
    $text =~ s/\$username/$users->getLoginName($user)||'unknown'/ge;    # 'jsmith'
    $text =~ s/\$wikiname/$users->getWikiName($user)||'UnknownUser'/ge;     # 'JohnSmith'
    $text =~ s/\$wikiusername/$users->webDotWikiName($user)||$TWiki::cfg{UsersWebName}.'UnknownUser'/ge;
                                                                            # 'Main.JohnSmith'
    if( $text =~ /\$summary/ ) {
        my $summary = $store->readTopicRaw( undef, $theWeb, $theTopic, undef );
        $summary = $this->makeTopicSummary( $summary, $theTopic, $theWeb );
        $summary =~ s/[\"\']//g;       # remove quotes (not allowed in title attribute)
        $text =~ s/\$summary/$summary/g;
    }
    return $text;
}

# Returns topic meta object, either from cache or from file
sub _getTopicMeta {
    my( $this, $theWeb, $theTopic, $theRev ) = @_;
    $theRev ||= '';
    my $meta = $this->{metaCache}{"$theWeb.$theTopic;$theRev"};
    return $meta if ( $meta );
    try {
        my $store = $this->{session}->{store};
        my $dummyText;
        ( $meta, $dummyText ) = $store->readTopic(
              $this->{session}->{user}, $theWeb, $theTopic, $theRev );
        $this->{metaCache}{"$theWeb.$theTopic;$theRev"} = $meta;
    } catch TWiki::AccessControlException with {
        # Ignore access exceptions; just don't read the data.
        my $e = shift;
        $this->{session}->writeWarning( "Attempt to read meta data failed: ".$e->stringify() );
    };
    return $meta;
}

# Returns topic title if force is on or if SHOWTOPICTITLELINK
# preferences setting is set.
# Warning: Slower performance if SHOWTOPICTITLELINK enabled.
sub _getTopicTitle {
    my( $this, $web, $topic, $link, $force ) = @_;
    unless( defined( $this->{SHOWTOPICTITLELINK} )) {
        $this->{SHOWTOPICTITLELINK} =
          TWiki::isTrue( $this->{session}->{prefs}->getPreferencesValue('SHOWTOPICTITLELINK') );
    }
    return $link unless( $this->{SHOWTOPICTITLELINK} || $force );
    return $link unless( $this->{session}->inContext( 'view' ));

    my $meta = $this->_getTopicMeta( $web, $topic );

    return $meta->topicTitle() if( $meta );
    return $link;
}

=pod

---++ ObjectMethod internalLink ( $theWeb, $theTopic, $theLinkText, $theAnchor, $doLink, $doKeepWeb, $hasExplicitLinkLabel, $theParams ) -> $html

Generate a link.

Note: Topic names may be spaced out. Spaced out names are converted to <nop>WikWords,
for example, "spaced topic name" points to "SpacedTopicName".
   * =$theWeb= - the web containing the topic
   * =$theTopic= - the topic to be link
   * =$theLinkText= - text to use for the link
   * =$theAnchor= - the link anchor, if any
   * =$doLinkToMissingPages= - boolean: false means suppress link for non-existing pages
   * =$doKeepWeb= - boolean: true to keep web prefix (for non existing Web.TOPIC)
   * =$hasExplicitLinkLabel= - boolean: true in case of [[TopicName][explicit link label]]
   * =$theParams= - the URL parameters specified by ?name1=value1;name2=valu2;... excluding the leading ?.
     This is added as per Item7505. This parameter's natural position is before
     =$theAnchor=. But to minimize code changes, it's introduced as the laster
     one

Called by _handleWikiWord and _handleSquareBracketedLink and by Func::internalLink

Calls _renderWikiWord, which in turn will use Plurals.pm to match fold plurals to equivalency with their singular form

SMELL: why is this available to Func?

=cut

sub internalLink {
    my( $this, $theWeb, $theTopic, $theLinkText, $theAnchor, $doLinkToMissingPages, $doKeepWeb, $hasExplicitLinkLabel, $theParams ) = @_;
    # SMELL - shouldn't it be callable by TWiki::Func as well?

    #PN: Webname/Subweb/ -> Webname/Subweb
    $theWeb =~ s/\/\Z//o;

    if($theLinkText eq $theWeb) {
        $theLinkText =~ s/\//\./go;
    }

    #WebHome links to tother webs render as the WebName
    if (($theLinkText eq $TWiki::cfg{HomeTopicName}) &&
        ($theWeb ne $this->{session}->{webName})) {
            $theLinkText = $theWeb;
    }

    # Get rid of leading/trailing spaces in topic name
    $theTopic =~ s/^\s*//o;
    $theTopic =~ s/\s*$//o;

    # Allow spacing out, etc.
    # Plugin authors use $hasExplicitLinkLabel to determine if the link label
    # should be rendered differently even if the topic author has used a
    # specific link label.
    $theLinkText = $this->{session}->{plugins}->dispatch(
        'renderWikiWordHandler', $theLinkText, $hasExplicitLinkLabel,
        $theWeb, $theTopic ) || $theLinkText;

    # Turn spaced-out names into WikiWords - upper case first letter of
    # whole link, and first of each word. TODO: Try to turn this off,
    # avoiding spaces being stripped elsewhere
    $theTopic =~ s/^(.)/\U$1/;
    $theTopic =~ s/\s([$TWiki::regex{mixedAlphaNum}])/\U$1/go;

    # Add <nop> before WikiWord inside link text to prevent double links
    $theLinkText =~ s/(?<=[\s\(])([$TWiki::regex{upperAlpha}])/<nop>$1/go;

    return _renderWikiWord($this, $theWeb, $theTopic, $theLinkText, $theAnchor, $doLinkToMissingPages, $doKeepWeb, $theParams);
}

# TODO: this should be overridable by plugins.
sub _renderWikiWord {
    my ($this, $theWeb, $theTopic, $theLinkText, $theAnchor, $doLinkToMissingPages, $doKeepWeb, $theParams) = @_;
    my $store = $this->{session}->{store};
    my $topicExists = $store->topicExists( $theWeb, $theTopic );
    if ( !$topicExists && $store->webExists( $theWeb.'/'.$theTopic ) ) {
        $theWeb .= '/'.$theTopic;
        $theTopic = $TWiki::cfg{HomeTopicName};
        $topicExists = $store->topicExists( $theWeb, $theTopic );
    }

    my $singular = '';
    unless( $topicExists ) {
        # topic not found - try to singularise
        require TWiki::Plurals;
        $singular = TWiki::Plurals::singularForm($theWeb, $theTopic);
        if( $singular ) {
            $topicExists = $store->topicExists( $theWeb, $singular );
            $theTopic = $singular if( $topicExists );
        }
    }

    if( $topicExists ) {
        return _renderExistingWikiWord( $this, $theWeb, $theTopic, $theLinkText, $theAnchor, $theParams );
    }
    if( $doLinkToMissingPages ) {
        # CDot: disabled until SuggestSingularNotPlural is resolved
        # if ($singular && $singular ne $theTopic) {
        #     #unshift( @topics, $singular);
        # }
        return _renderNonExistingWikiWord($this, $theWeb, $theTopic, $theLinkText );
    }
    if( $doKeepWeb ) {
        return $theWeb.'.'.$theLinkText;
    }

    return $theLinkText;
}

sub _renderExistingWikiWord {
    my ($this, $web, $topic, $text, $anchor, $params) = @_;

    my $currentWebHome = '';
    $currentWebHome = 'twikiCurrentWebHomeLink ' if (($web eq $this->{session}->{webName}) &&
                                      ($topic eq $TWiki::cfg{HomeTopicName} ));

    my $currentTopic = '';
    $currentTopic = 'twikiCurrentTopicLink ' if (($web eq $this->{session}->{webName}) &&
                                       ($topic eq $this->{session}->{topicName}));

    my @attrs;
    my $href = $this->{session}->getScriptUrl( 0, 'view', $web, $topic );
    if ( $params ) {
        $href .= '?' . $params;
    }
    if( $anchor ) {
        $anchor = $this->makeAnchorName( $anchor );
        push( @attrs, class => $currentTopic.$currentWebHome.'twikiAnchorLink', href => $href.'#'.$anchor );
    } else {
        push( @attrs, class => $currentTopic.$currentWebHome.'twikiLink', href => $href );
    }
    my $tooltip = _linkToolTipInfo( $this, $web, $topic );
    push( @attrs, title => $tooltip ) if( $tooltip );

    my $link = CGI::a( { @attrs }, $text );
    # When we pass the tooltip text to CGI::a it may contain
    # <nop>s, and CGI::a will convert the < to &lt;. This is a
    # basic problem with <nop>.
    $link =~ s/&lt;nop&gt;/<nop>/g;
    return $link;
}

sub _renderNonExistingWikiWord {
    my ($this, $web, $topic, $text) = @_;

    my $ans = $this->_newLinkFormat;
    $ans =~ s/\$web/$web/g;
    $ans =~ s/\$topic/$topic/g;
    $ans =~ s/\$text/$text/g;
    $ans =~ s/\$summary/$this->TML2PlainText( $text, $web, $topic, 'entityencode')/ge;

    $ans = $this->{session}->handleCommonTags( $ans, $this->{session}{webName}, $this->{session}{topicName} );
    return $ans;
}

# _handleWikiWord is called by the TWiki Render routine when it sees a
# wiki word that needs linking.
# Handle the various link constructions. e.g.:
# WikiWord
# Web.WikiWord
# Web.WikiWord#anchor
#
# This routine adds missing parameters before passing off to internallink
sub _handleWikiWord {
    my ( $this, $theWeb, $web, $topic, $anchor ) = @_;

    my $linkIfAbsent = 1;
    my $keepWeb = 0;
    my $text;

    $web = $theWeb unless (defined($web));
    if( defined( $anchor )) {
        ASSERT(($anchor =~ m/\#.*/)) if DEBUG; # must include a hash.
    } else {
        $anchor = '' ;
    }

    if ( defined( $anchor ) ) {
        # 'Web.TopicName#anchor' or 'Web.ABBREV#anchor' link
        $text = $topic.$anchor;
    } else {
        $anchor = '';

        # 'Web.TopicName' or 'Web.ABBREV' link:
        if ( $topic eq $TWiki::cfg{HomeTopicName} &&
             $web ne $this->{session}->{webName} ) {
            $text = $web;
        } else {
            $text = $topic;
        }
    }

    # =$doKeepWeb= boolean: true to keep web prefix (for non existing Web.TOPIC)
    # (Necessary to leave "web part" of ABR.ABR.ABR intact if topic not found)
    $keepWeb = ( $topic =~ /^$TWiki::regex{abbrevRegex}$/o && $web ne $this->{session}->{webName} );

    # false means suppress link for non-existing pages
    $linkIfAbsent = ( $topic !~ /^$TWiki::regex{abbrevRegex}$/o );

    # SMELL - it seems $linkIfAbsent, $keepWeb are always inverses of each
    # other
    # TODO: check the spec of doKeepWeb vs $doLinkToMissingPages

    return $this->internalLink( $web, $topic, $text, $anchor, $linkIfAbsent, $keepWeb, undef );
}

sub _getNameFromLink {
    my $link = shift;
    my $name = $link;
    $name =~ s/$TWiki::regex{anchorRegex}$//;
    $name =~ s/\?.*$//;
    $name =~ s:/+$::;
    my @path = split(m:/+:, $name);
    $name = $path[-1];
    $name = $link if ( $name eq '' ); #the last resort
    return $name;
}

# Handle SquareBracketed links mentioned on page $theWeb.$theTopic
# format: [[$link]]
# format: [[$link][$text]]
sub _handleSquareBracketedLink {
    my( $this, $web, $topic, $link, $text ) = @_;

    # Strip leading/trailing spaces
    $link =~ s/^\s+//;
    $link =~ s/\s+$//;

    my $hasExplicitLinkLabel = $text ? 1 : undef;

    # Explicit external [[$link][$text]]-style can be handled directly
    if( $link =~ m!^($TWiki::regex{linkProtocolPattern}\:|/)! ) {
        if (defined $text) {
            # [[][]] style - protect text:
            # for [[...][$name]]
            $text =~ s/\$name\b/_getNameFromLink($link)/ge;
            # Prevent automatic WikiWord or CAPWORD linking in explicit links
            $text =~ s/(?<=[\s\(])($TWiki::regex{wikiWordRegex}|[$TWiki::regex{upperAlpha}])/<nop>$1/go;
        }
        else {
            # [[]] style - take care for legacy:
            # Prepare special case of '[[URL#anchor display text]]' link
            if ( $link =~ /^(\S+)\s+(.*)$/ ) {
                # '[[URL#anchor display text]]' link:
                $link = $1;
                $text = $2;
                $text =~ s/(?<=[\s\(])($TWiki::regex{wikiWordRegex}|[$TWiki::regex{upperAlpha}])/<nop>$1/go;
            }
        }
        return _externalLink( $this, $link, $text );
    }

    # Extract '#anchor'
    my $origLink = $link;
    my $anchor = '';
    if( $link =~ s/($TWiki::regex{anchorRegex}$)// ) {
        $anchor = $1;
    }

    my $forceTopicTitle = 0;
    if( $link =~ s/^\+// ) {
        # [[+WikiWord]] link
        $forceTopicTitle = 1;
    }

    # Item7505: Extract '?parameter'
    my $params;
    if ( $link =~ s/\?(.*)$// ) {
        $params = $1;
    }

    $link = $this->buildWikiWord( $link );
    $topic = $link if( $link );

    # Topic defaults to the current topic
    ($web, $topic) = $this->{session}->normalizeWebTopicName( $web, $topic );

    if( $text ) {
        $text =~ s/\$name\b/$topic/g;
        $text =~ s/\$topictitle/$this->_getTopicTitle( $web, $topic, $origLink, 1 )/geo;
    } else {
        $text = $this->_getTopicTitle( $web, $topic, $origLink, $forceTopicTitle );
    }

    return $this->internalLink( $web, $topic, $text, $anchor, 1, undef, $hasExplicitLinkLabel, $params );
}

# Converts arbitrary text to a WikiWord
sub buildWikiWord {
    my( $this, $link ) = @_;

    # filter out &any; entities (legacy)
    $link =~ s/\&[a-z]+\;//gi;
    # filter out &#123; entities (legacy)
    $link =~ s/\&\#[0-9]+\;//g;
    # Filter junk
    $link =~ s/$TWiki::cfg{NameFilter}+/ /g;
    # Capitalise first word
    $link =~ s/^(.)/\U$1/;
    # Collapse spaces and capitalise following letter
    $link =~ s/\s([$TWiki::regex{mixedAlphaNum}])/\U$1/go;
    # Get rid of remaining spaces, i.e. spaces in front of -'s and ('s
    $link =~ s/\s//go;

    return $link;
}

sub _readTopicTable {
    my( $this, $webTopic, $defaultWeb ) = @_;

    if( $webTopic =~ /%/ ) {
        $webTopic = TWiki::Func::expandCommonVariables( $webTopic, $defaultWeb );
    }

    my( $web, $topic ) = TWiki::Func::normalizeWebTopicName( $defaultWeb, $webTopic );
    my $wikiName = TWiki::Func::getWikiName();
    my( $meta, $text ) = TWiki::Func::readTopic( $web, $topic );
    my @result;

    if( TWiki::Func::checkAccessPermission( 'VIEW', $wikiName, $text, $topic, $web, $meta ) ) {
        if( defined $text && $text ne '' ) {
            while( $text =~ /^\s*\|(.*?)\|(?:.*\|)?\s*$/mg ) {
                ( my $name = $1 ) =~ s/^\s+|\s+$//g;
                next if $name =~ /^\*.*\*$/; # exclude "| *Text* |"
                push @result, $name;
            }
        } else {
            TWiki::Func::writeWarning( "$webTopic cannot be read" );
        }
    } else {
        TWiki::Func::writeWarning( "$webTopic is not accessible for user $wikiName" );
    }

    return @result;
}

sub _isInternalLinkDomain {
    my( $this, $url ) = @_;

    # TWiki internal link if URL starts with TWiki domain or "/"
    my $urlHostRegex = quotemeta( $this->{session}{urlHost} );
    return 1 if $url =~ /^($urlHostRegex|\/)/;

    # Item7191: Check $TWiki::cfg{Links}{InternalLinkDomains}
    if( $url =~ m!^$TWiki::regex{linkProtocolPattern}://([^/]+)! ) {
        my $domain = $2; # $1 is the protocol part
        $domain =~ s/:.*//; # Remove any port number

        unless( defined $this->{_internalDomainRegex} ) {
            my @targets = (
                { defaultWeb => $TWiki::cfg{SystemWebName},
                    value => $TWiki::cfg{Links}{InternalLinkDomains} },
                { defaultWeb => $this->{session}{SESSION_TAGS}{BASEWEB},
                    value => $this->{session}{prefs}->getPreferencesValue( 'INTERNALLINKDOMAINS' ) },
            );
            my @patterns;
            for my $target ( @targets ) {
                next if !$target->{value};

                my $defaultWeb = $target->{defaultWeb};
                for my $entry ( split( /\s*,\s*/, $target->{value} ) ) {
                    $entry =~ s/^\s+|\s+$//g;
                    next if $entry eq '';

                    my @entries;
                    if( $entry =~ /^topic:(.*)/ ) {
                        @entries = $this->_readTopicTable( $1, $defaultWeb );
                    } else {
                        @entries = ( $entry );
                    }
                    # Case 1: $domain is '.': intranet "one-word" domain
                    # Case 2: $domain starts with '.': subdomains under $domain
                    # Case 3: otherwise: $domain (no subdomains)
                    push @patterns, map {
                        my $domain = $_;
                        $domain eq '.' ? '^[^\.]+$' :
                            ( $domain =~ /^\./ ? '' : '^' ).quotemeta( $domain ).'$'
                    } @entries;
                }
            }

            if( @patterns ) {
                $this->{_internalDomainRegex} = '('.join( '|', @patterns ).')';
            } else {
                $this->{_internalDomainRegex} = '';
            }
        }

        if( $this->{_internalDomainRegex} ) {
            return 1 if $domain =~ /$this->{_internalDomainRegex}/;
        }
    }

    return 0;
}

# Handle an external link typed directly into text. If it's an image
# (as indicated by the file type), and no text is specified, then use
# an img tag, otherwise generate a link.
sub _externalLink {
    my( $this, $url, $text ) = @_;

    if( $url =~ /^[^?]*\.(gif|jpg|jpeg|png)$/i && !$text) {
        my $filename = $url;
        $filename =~ s@.*/([^/]*)@$1@go;
        return CGI::img( { src => $url, alt => $filename } );
    }
    my $prefs = $this->{session}{prefs};
    my $externalLinksInNewWindow = $TWiki::cfg{Links}{ExternalLinksInNewWindow};
    if( defined( my $prefValue = $prefs->getPreferencesValue( 'EXTERNALLINKSINNEWWINDOW' ) ) ) {
        $externalLinksInNewWindow = TWiki::isTrue( $prefValue ) if $prefValue ne '';
    }
    my $externalLinksIcon = $TWiki::cfg{Links}{ExternalLinksIcon};
    if( defined( my $prefValue = $prefs->getPreferencesValue( 'EXTERNALLINKSICON' ) ) ) {
        $externalLinksIcon = TWiki::isTrue( $prefValue ) if $prefValue ne '';
    }
    my $opt = '';
    my $icn = '';
    if( $url =~ /^mailto:/i ) {
        my $twiki = $this->{session};
        if( $TWiki::cfg{AntiSpam}{EmailGuestPadding} && !$twiki->inContext( 'authenticated' ) ) {
            $url =~  s/(\@[\w\_\-\+]+)(\.)/$1$TWiki::cfg{AntiSpam}{EmailGuestPadding}$2/;
            if ($text) {
                $text =~ s/(\@[\w\_\-\+]+)(\.)/$1$TWiki::cfg{AntiSpam}{EmailGuestPadding}$2/;
            }
        } elsif( $TWiki::cfg{AntiSpam}{EmailPadding} ) {
            $url =~  s/(\@[\w\_\-\+]+)(\.)/$1$TWiki::cfg{AntiSpam}{EmailPadding}$2/;
            if ($text) {
                $text =~ s/(\@[\w\_\-\+]+)(\.)/$1$TWiki::cfg{AntiSpam}{EmailPadding}$2/;
            }
        }
        if( $TWiki::cfg{AntiSpam}{HideUserDetails} ) {
            # Much harder obfuscation scheme. For link text we only encode '@'
            # See also Item2928 and Item3430 before touching this
            $url =~ s/(\W)/'&#'.ord($1).';'/ge;
            if ($text) {
                $text =~ s/\@/'&#'.ord('@').';'/ge;
            }
        }

    } elsif( $this->_isInternalLinkDomain( $url ) ) {
        # TWiki internal link if URL is under an internal domain
        $opt = ' target="_top"';

    } else {
        # External link
        if( $externalLinksInNewWindow ) {
            $opt = ' target="_blank"';
        } else {
            $opt = ' target="_top"';
        }
        if( $externalLinksIcon ) {
            unless( $this->{externalIcon} ) {
                $this->{externalIcon} = CGI::img( { src =>
                  "$TWiki::cfg{PubUrlPath}/$TWiki::cfg{SystemWebName}"
                  . "/TWikiDocGraphics/external-link.gif", 
                  alt => '', width => 13, height => 12, border => 0 } );
            }
            $icn = $this->{externalIcon};
        }
    }
    $text ||= $url;

    $url =~ s/ /%20/g;  #Item5787: if a url has spaces, escape them so the url has less chance of being broken by later parsing.
    # SMELL: Can't use CGI::a here, because it encodes ampersands in
    # the link, and those have already been encoded once in the
    # rendering loop (they are identified as "stand-alone"). One
    # encoding works; two is too many. None would be better for everyone!
    return "<a href=\"$url\"$opt>$text$icn</a>";
}

# Generate a "mailTo" link
sub _mailLink {
    my( $this, $text ) = @_;

    my $url = $text;
    $url = 'mailto:'.$url unless $url =~ /^mailto:/i;
    return _externalLink( $this, $url, $text );
}

# Generate a "@twitter" link
sub _twitterLink {
    my( $this, $text ) = @_;

    my $url = $TWiki::cfg{Links}{TwitterUrlPattern};
    return( '@' . $text ) unless( $url );
    $url =~ s/\%ID\%/$text/go;
    return _externalLink( $this, $url, '@' . $text );
}

=pod

---++ ObjectMethod renderFORM ( %params, $topic, $web ) -> $tml

Returns TML of a TWiki Form, based on %FORM{}% variable.

=cut

sub renderFORM {
    my ( $this, $params, $topic, $web ) = @_;

    my @fieldList = split( /, */, $params->{formfields} || 'all' );
    my $vWeb      = $params->{web} || $web;
    my $vTopic    = $params->{topic}||  $params->{_DEFAULT} || $topic;
    my $default   = $params->{default} || '';
    my $rev       = $params->{rev};
    if( $rev ) {
        $rev = $this->{session}{store}->cleanUpRevID($rev);
    }
    my $format    = $params->{format} || '| $title: | $value |';
    my $newLine   = $params->{newline};
    if( defined $newLine ) {
        $newLine =~ s/\$br\b/<br \/>/go;
        $newLine =~ s/\$n\b/\n/go;
    } elsif( $format =~ /^ *\|/ ) {
        # TML table, so use br tag for newlines by default
        $newLine = '<br />';
    } else {
        $newLine = "\n";
    }
    my $separator = $params->{separator} || "\n";
    my $header    = $params->{header} || '1';
    $header = '|  *[[$formweb.$formtopic][$formtopic]]*  ||' if( $header =~ /^(on|1)$/ );
    my $showHidden = $params->{showhidden};
    my $encodeType = $params->{encode} || '';

    my $session   = $this->{session};

    ( $vWeb, $vTopic ) = $session->normalizeWebTopicName( $web, $vTopic );
    my $meta = $this->_getTopicMeta( $vWeb, $vTopic, $rev );
    return $default unless( $meta && $meta->get( 'FORM' ) ); # no form on topic

    my $formWeb = $vWeb;
    my $formTopic = $meta->get( 'FORM' )->{name};
    ( $formWeb, $formTopic ) = $session->normalizeWebTopicName( $formWeb, $formTopic );
    my $formDef = $this->{formDefCache}{"$formWeb.$formTopic"};
    if( !$formDef && $session->{store}->topicExists( $formWeb, $formTopic ) ) {
        require TWiki::Form;
        $formDef = new TWiki::Form( $session, $formWeb, $formTopic );
        $this->{formDefCache}{"$formWeb.$formTopic"} = $formDef;
    }

    my @lines = ();
    unless( $header eq 'none' ) {
        $header =~ s/\$formweb/$formWeb/go;
        $header =~ s/\$formtopic/$formTopic/go;
        @lines = ( $header );
    }

    my @fields = $meta->find( 'FIELD' );
    my %seen;
    my $attrs = { showhidden => 1, encode => $encodeType, newline => $newLine };
    if( $formDef ) {
        # get all attributes from form definition, except for value
        @fieldList =
            map {
              if( /^all$/ ) {
                map { $_->{name} } @{$formDef->{fields}}
              } else {
                $_
              }
            } @fieldList; 
            # fieldList may contain duplicates that need to be filtered out

        foreach my $name ( @fieldList ) {
            my $field = $formDef->getField( $name );
            if( $field && !$seen{$field} && ( $field->{attributes} !~ /H/ || $showHidden ) ) {
                $seen{$field} = 1;
                my $title = $field->{title} || $name;
                my $attributes = $field->{attributes} || '';
                my $text = $format;
                my @a = map { $_->{value} } grep { $_->{name} eq $name } @fields;
                my $value = '';
                $value = $a[0] if( scalar @a );
                my $length = length $value;
                $text =~ s/\$length/$length/go;
                $text =~ s/\$size/$field->{size}/go;
                $text =~ s/\$formweb/$formWeb/go;
                $text =~ s/\$formtopic/$formTopic/go;
                if( $text =~ s/(\$value)\(\s*([^\)]*)\)/$1/go ) {
                    $attrs->{break} = $2;
                } else {
                    undef $attrs->{break};
                }
                $text = $field->renderForDisplay( $text, $value, $attrs );
                push( @lines, $text );
            }
        }

    } else {
        # topic has a form but form definition is unavailable.
        # do the best to render form without form definition topic.
        @fieldList =
            map {
              if( /^all$/ ) {
                map { $_->{name} } @fields
              } else {
                $_
              }
            } @fieldList;
            # fieldList may contain duplicates that need to be filtered out

        foreach my $name ( @fieldList ) {
            my $field = $meta->get( 'FIELD', $name );
            if( $field && !$seen{$field} && ( $field->{attributes} !~ /H/ || $showHidden ) ) {
                $seen{$field} = 1;
                my $title = $field->{title} || $name;
                my $attributes = $field->{attributes} || '';
                my $text = $format;
                if( $text =~ s/(\$value)\(\s*([^\)]*)\)/$1/go ) {
                    $attrs->{break} = $2;
                } else {
                    undef $attrs->{break};
                }
                my $value = TWiki::Render::protectFormFieldValue( $field->{value}, $attrs );
                my $length = length $value;
                $text =~ s/\$length/$length/go;
                $text =~ s/\$size/1/go; # fake it
                $text =~ s/\$attributes/$attributes/go;
                $text =~ s/\$type/unknown/go;
                $text =~ s/\$formweb/$formWeb/go;
                $text =~ s/\$formtopic/$formTopic/go;
                $text =~ s/\$tooltip//go;
                $text =~ s/\$title/$title/go;
                $text =~ s/\$name/$name/go;
                $text =~ s/\$value/$value/go;
                push( @lines, $text );
            }
        }
    }
    return $default unless( scalar keys %seen ); # no wanted fields found

    $separator =~ s/\$br\b/<br \/>/go;
    $separator =~ s/\$n\b/\n/go;
    return join( $separator, @lines );
}

=pod

---++ ObjectMethod renderFORMFIELD ( %params, $topic, $web ) -> $html

Returns the fully rendered expansion of a %FORMFIELD{}% tag.

=cut

sub renderFORMFIELD {
    my ( $this, $params, $topic, $web ) = @_;

    my $formField = $params->{_DEFAULT};
    my $formTopic = $params->{topic};
    my $altText   = $params->{alttext};
    my $default   = $params->{default};
    my $rev       = $params->{rev};
    if ( $rev ) {
        $rev = $this->{session}{store}->cleanUpRevID($rev);
    }
    my $format    = $params->{format} || '$value';
    my $encode    = $params->{encode} || '';
    my $newLine   = $params->{newline};

    my $formWeb;
    if ( $formTopic ) {
        if ($topic =~ /^([^.]+)\.([^.]+)/o) {
            ( $formWeb, $topic ) = ( $1, $2 );
        } else {
            # SMELL: Undocumented feature, 'web' parameter
            $formWeb = $params->{web};
        }
        $formWeb = $web unless $formWeb;
    } else {
        $formWeb = $web;
        $formTopic = $topic;
    }

    my $meta = $this->_getTopicMeta( $formWeb, $formTopic, $rev );
    my $text = '';
    my $found = 0;
    my $title = '';
    if ( $meta ) {
        my @fields = $meta->find( 'FIELD' );
        foreach my $field ( @fields ) {
            my $name = $field->{name};
            $title = $field->{title} || $name;
            if( $title eq $formField || $name eq $formField ) {
                $found = 1;
                my $value = $field->{value};
                my $length = length $value;
                if( $length || $format ne '$value' ) {
                    $text = $format;
                    $text =~ s/\$length/$length/go;
                    $text =~ s/\$attributes/$field->{attributes}/go;
                    $text =~ s/\$formtopic/$meta->get( 'FORM' )->{name}/geo;
                    $text =~ s/\$title/$title/go; # Item6267: Keep $title in value
                    $text =~ s/\$name/$name/go;
                    $text =~ s/\$value\(\s*([^\)]*)\s*\)/breakName( $value, $1 )/ges;
                    $text =~ s/\$value/$value/go;
                } elsif ( defined $default ) {
                    $text = $default;
                }
                last; #one hit suffices
            }
        }
    }

    unless ( $found ) {
        $text = $altText || '';
    }

    if( defined $newLine ) {
        $newLine =~ s/\$br\b/\0-br-\0/go;
        $newLine =~ s/\$n\b/\0-n-\0/go;
        $text =~ s/\r?\n/$newLine/go;
    }
    if( $encode ) {
        $text = $this->{session}->ENCODE( { _DEFAULT => $text, type => $encode } );
    }
    if( defined $newLine ) {
        $text =~ s/\0-br-\0/<br \/>/go;
        $text =~ s/\0-n-\0/\n/go;
    }

    return $text;
}

=pod

---++ ObjectMethod renderEDITFORM ( %params, $topic, $web ) -> $tml

Returns TML of a TWiki Form, based on %EDITFORM{}% variable.

=cut

sub renderEDITFORM {
    my ( $this, $params, $topic, $web ) = @_;

    my $vWeb         = $params->{web} || $web;
    my $vTopic       = $params->{topic}||  $params->{_DEFAULT} || $topic;
    my $formTemplate = $params->{formtemplate} || '';
    my @elementList  = split( /, */, $params->{elements}
                     || 'formstart, header, formfields, submit, hiddenfields, formend' );
    my $header       = $params->{header} || '1';
    $header          = '|  *[[$formweb.$formtopic][$formtopic]]*  ||' if( $header =~ /^(on|1)$/ );
    my @fieldList    = split( /, */, $params->{formfields} || 'all' );
    my $format       = $params->{format} || '| $title: $extra | $inputfield |';
    my @hiddenList   = split( /, */, $params->{hiddenfields} || '' );
    my $submit       = $params->{submit} || '| | $submit |';
    my $onsubmit     = $params->{onsubmit} || '';
    my $action       = $params->{action} || 'save';
    my $method       = $params->{method} || 'get';
    $method          = 'post' if( $action eq 'save' );
    my $separator    = $params->{separator} || "\n";
    my $default      = $params->{default} || '';

    my $session   = $this->{session};

    # get topic meta data
    ( $vWeb, $vTopic ) = $session->normalizeWebTopicName( $web, $vTopic );
    my $meta = $this->_getTopicMeta( $vWeb, $vTopic );
    my $metaFormName = $meta && $meta->get( 'FORM' ) && $meta->get( 'FORM' )->{name};

    # get form definition
    my $formWeb = $web;
    my $formTopic = $formTemplate || $metaFormName;
    return $default unless( $formTopic ); # no form on topic and no form template
    ( $formWeb, $formTopic ) = $session->normalizeWebTopicName( $formWeb, $formTopic );
    my $formDef = $this->{formDefCache}{"$formWeb.$formTopic"};
    if( !$formDef && $session->{store}->topicExists( $formWeb, $formTopic ) ) {
        require TWiki::Form;
        $formDef = new TWiki::Form( $session, $formWeb, $formTopic );
        $this->{formDefCache}{"$formWeb.$formTopic"} = $formDef;
    }
    return $default unless( $formDef ); # no form definition found

    # loop through element list to compose the form
    my @lines = ();
    foreach my $element ( @elementList ) {
        if( $element eq 'formstart' ) {
            if( $action =~ /^[a-z_-]+$/i ) {
                $action = $session->getScriptUrl( 0, $action, $vWeb, $vTopic );
            } # else use full action URL verbatim

            my $html = "<form action=\"$action\" method=\"$method\"";
            $html .= ' onsubmit="' . $params->{onsubmit} . '"' if( $params->{onsubmit} );
            $html .= ' onreset="'  . $params->{onreset}  . '"' if( $params->{onreset} );
            $html .= '>';
            push( @lines, $html );

        } elsif( $element eq 'header' ) {
            $header =~ s/\$formweb/$formWeb/go;
            $header =~ s/\$formtopic/$formTopic/go;
            push( @lines, $header );

        } elsif( $element eq 'formfields' ) {
            # get all attributes from form definition, except for value
            @fieldList =
                map {
                  if( /^all$/ ) {
                    map { $_->{name} } @{$formDef->{fields}}
                  } else {
                    $_
                  }
                } @fieldList; 
                # fieldList may contain duplicates that need to be filtered out

            my %seen;
            my @fields = $meta->find( 'FIELD' );
            my $attrs = { showhidden => 1 };
            foreach my $name ( @fieldList ) {
                my $field = $formDef->getField( $name );
                if( $field && !$seen{$field} ) {
                    $seen{$field} = 1;
                    my $title = $field->{title} || $name;
                    next if( grep{ /^($title|$name)$/ } @hiddenList );
                    my $attributes = $field->{attributes} || '';
                    my $text = $format;
                    my @a = map { $_->{value} } grep { $_->{name} eq $name } @fields;
                    my $value = '';
                    $value = $a[0] if( scalar @a );
                    my $length = length $value;
                    my ( $extra, $inputField ) = $field->renderForEdit( $vWeb, $vTopic, $value );
                    # In value="", escape space, angle brackets, "%" and "|"
                    $inputField =~ s/(value=")([^"]*)/$1 . defuseTML($2)/geo;
                    if( $field->isMandatory() ) {
                        $extra .= CGI::span( { class => 'twikiAlert' }, ' *' );
                    }
                    $text =~ s/\$inputfield/$inputField/go;
                    $text =~ s/\$title/$title/go;
                    $text =~ s/\$name/$name/go;
                    $text =~ s/\$length/$length/go;
                    $text =~ s/\$size/$field->{size}/go;
                    $text =~ s/\$value/$field->{value}/go;
                    $text =~ s/\$tooltip/$field->{tooltip}/go;
                    $text =~ s/\$attributes/$attributes/go;
                    $text =~ s/\$extra/$extra/go;
                    $text =~ s/\$formweb/$formWeb/go;
                    $text =~ s/\$formtopic/$formTopic/go;
                    push( @lines, $text );
                }
            }

        } elsif( $element eq 'hiddenfields' ) {
            my $hiddenFormat = '<input type="hidden" name="$name" value="$value" />';
            foreach my $name ( @hiddenList ) {
                my $value = $params->{$name};
                if( defined $value ) {
                    my $text = $hiddenFormat;
                    $text =~ s/\$name/$name/go;
                    $text =~ s/\$value/$value/go;
                    push( @lines, $text );
                }
            }

        } elsif( $element eq 'submit' ) {
            $submit =~ s/\$submit\(([^\)]*)\)/_submitField( $1 )/geo;
            $submit =~ s/\$submit/_submitField( 'Save' )/geo;
            push( @lines, $submit );

        } elsif( $element eq 'formend' ) {
            push( @lines, '</form>' );
        }
    }

    $separator =~ s/\$br\b/<br \/>/go;
    $separator =~ s/\$n\b/\n/go;
    my $text = join( $separator, @lines );
    return $text;
}

sub _submitField {
    my( $label ) = @_;
    $label ||= 'Save';
    my $text = '<input type="submit" name="action_save" value="$label" class="twikiSubmit" />';
    $text =~ s/\$label/$label/g;
    return $text;
}

=pod

---++ ObjectMethod renderEDITFORMFIELD ( %params, $topic, $web ) -> $html

Returns the fully rendered expansion of a %EDITFORMFIELD{}% tag.

=cut

sub renderEDITFORMFIELD {
    my ( $this, $params, $topic, $web ) = @_;

    my $formField = $params->{_DEFAULT};
    my $formTopic = $params->{form};
    my $format    = $params->{format} || '$inputfield';
    my $type      = $params->{type}   || '';
    my $value     = $params->{value}  || '';
    my $vTopic    = $params->{topic}  || '';

    my $session   = $this->{session};
    my $formWeb;
    unless( $formField ) {
        return errorMsg( 'Required form field name is missing' );
    }

    if( $type =~ /^start$/i ) {
        # special case: HTML start tag
        my $action = $params->{action} || 'view';
        my $method = 'get';
        if( $params->{method} ) {
            $method = $params->{method};
        } elsif( $action =~ /^save$/i ) {
            $method = 'post';
        }
        if( $action =~ /^[a-z_-]+$/i ) {
            my $vWeb;
            $vTopic ||= $topic;
            ( $vWeb, $vTopic ) = $session->normalizeWebTopicName( $web, $vTopic );
            $action = $session->getScriptUrl( 0, $action, $vWeb, $vTopic );
        } # else use full action URL verbatim
        my $html = "<form action=\"$action\" method=\"$method\"";
        $html .= ' onsubmit="' . $params->{onsubmit} . '"' if( $params->{onsubmit} );
        $html .= ' onreset="'  . $params->{onreset}  . '"' if( $params->{onreset} );
        $html .= '>';
        return $html;

    } elsif( $type =~ /^end$/i ) {
        # special case: HTML start tag
        my $html = '</form>';
        return $html;

    } elsif( $type =~ /^textarea$/ ) {
        # special case, construct <textara></textarea> tags
        my $html = "<textarea name=\"$formField\"";
        my $needsClass = 1;
        my $class = 'twikiTextarea';
        foreach my $key ( keys %$params ) {
            next if( $key =~ /^(_DEFAULT|_RAW|name|size|type|text|value)$/i );
            $needsClass = 0 if( $key =~ /^class$/i );
            $html .= " $key=\"" . $params->{$key} . '"';
        }
        my $size = $params->{size} || '';
        if( $size =~ /^([0-9]+)x([0-9]+)$/ ) {
            $html .= " cols=\"$1\" rows=\"$2\"";
        } elsif( $size =~ /^([0-9]+)$/ ) {
            $html .= " cols=\"$1\" rows=\"6\"";
        }
        if( $needsClass ) {
            $html .= ' class="twikiTextarea"';
        }
        $html .= '>' . $value . '</textarea>';
        return $html;

    } elsif( $type ) {
        # special case, construct an <input type="" /> tag
        my $html = "<input name=\"$formField\" type=\"$type\"";
        my $classes = {
            submit   => 'twikiSubmit',
            button   => 'twikiButton',
            text     => 'twikiInputField twikiEditFormTextField',
            checkbox => 'twikiCheckbox',
            radio    => 'twikiRadioButton',
          };
        my $needsClass = 1;
        foreach my $key ( keys %$params ) {
            next if( $key =~ /^(_DEFAULT|_RAW|name|type|text)$/i );
            $needsClass = 0 if( $key =~ /^class$/i );
            $html .= " $key=\"" . $params->{$key} . '"';
        }
        if( $needsClass && $classes->{$type} ) {
            $html .= ' class="' . $classes->{$type} . '"';
        }
        $html .= ' />';
        if( $type =~ /^(radio|checkbox)$/i ) {
            if( $params->{text} ) {
                $html .= ' ' . $params->{text};
            } elsif( $params->{value} ) {
                $html .= ' ' . $params->{value};
            }
            $html = "<label> $html </label>";
        }
        return $html;
    }
    unless( $formTopic || $vTopic || $type ) {
        return errorMsg( 'Required form, topic or type parameter is missing' );
    }
    if( $vTopic ) {
        # get form name and value from specified topic
        my $vWeb;
        ( $vWeb, $vTopic ) = $session->normalizeWebTopicName( $web, $vTopic );
        my $meta = $this->_getTopicMeta( $vWeb, $vTopic );
        if ( $meta ) {
            if( $meta->get( 'FORM' ) ) {
                $formTopic ||= ( $meta->get( 'FORM' )->{name} || '' );
            } else {
                return errorMsg( "Topic !$vWeb.$vTopic does not have a form" );
            }
            if( $value eq '' ) {
                # get value from specified topic
                my @fields = $meta->find( 'FIELD' );
                foreach my $field ( @fields ) {
                    my $title = $field->{title} || '';
                    if( $title eq $formField || $field->{name} eq $formField ) {
                        $value = $field->{value};
                        last; #one hit suffices
                    }
                }
            }
        }
    }

    ( $formWeb, $formTopic ) = $session->normalizeWebTopicName( $web, $formTopic );
    unless( $session->{store}->topicExists( $formWeb, $formTopic ) ) {
        return errorMsg( "Topic !$formWeb.$formTopic does not exist" );
    }

    my $formDef = $this->{formDefCache}{"$formWeb.$formTopic"};
    unless( $formDef ) {
        require TWiki::Form;
        $formDef = new TWiki::Form( $session, $formWeb, $formTopic );
        $this->{formDefCache}{"$formWeb.$formTopic"} = $formDef;
    }
    unless( $formDef ) {
        return errorMsg( "Topic $formWeb.$formTopic does not have a form definition" );
    }

    foreach my $fieldDef ( @{$formDef->{fields}} ) {
        if( $fieldDef->{title} eq $formField || $fieldDef->{name} eq $formField ) {
            if ( $TWiki::cfg{Site}{CharSet} =~ m/^utf-?8$/i ) {
                require Encode;
                $value = Encode::decode_utf8($value);
            }
            my ( $extra, $text ) = $fieldDef->renderForEdit( $web, $topic, $value );
            if ( $TWiki::cfg{Site}{CharSet} =~ m/^utf-?8$/i ) {
                $extra = Encode::encode_utf8($extra);
                $text = Encode::encode_utf8($text);
            }
            # In value="", escape space, angle brackets, "%" and "|"
            $text =~ s/(value=")([^"]*)/$1 . defuseTML($2)/geo;
            if( $fieldDef->isMandatory() ) {
                $extra .= CGI::span( { class => 'twikiAlert' }, ' *' );
            }
            my $html = $format;
            $html =~ s/\$inputfield/$text/go;
            $html =~ s/\$extra/$extra/go;
            $html =~ s/\$name/$fieldDef->{name}/go;
            $html =~ s/\$title/$fieldDef->{title}/go;
            $html =~ s/\$size/$fieldDef->{size}/go;
            $html =~ s/\$value/$fieldDef->{value}/go;
            $html =~ s/\$tooltip/$fieldDef->{tooltip}/go;
            $html =~ s/\$attributes/$fieldDef->{attributes}/go;
            return $html;
        }
    }
    return errorMsg( "Topic $formWeb.$formTopic does not have a form field named !"
          . $formField );
}

sub defuseTML {
    my( $text ) = @_;
    $text =~ s/\s/&#32;/g;  # defuse TML by escaping space
    $text =~ s/\%/&#37;/g;  # defuse %VARIABLES%
    $text =~ s/\[/&#91;/g;  # defuse [[]] links
    $text =~ s/\|/&#124;/g; # defuse "|" to allow EDITFIELD in TWiki tables
    return $text;
}

sub errorMsg {
    my( $msg ) = @_;
    return CGI::span( { class => 'twikiAlert' }, "EDITFORMFIELD Error: $msg" );
}

=pod

---++ ObjectMethod getRenderedVersion ( $text, $theWeb, $theTopic ) -> $html

The main rendering function.

=cut

sub getRenderedVersion {
    my( $this, $text, $theWeb, $theTopic ) = @_;

    return '' unless $text;  # nothing to do

    $theTopic ||= $this->{session}->{topicName};
    $theWeb ||= $this->{session}->{webName};
    my $session = $this->{session};
    my $plugins = $session->{plugins};
    my $prefs = $session->{prefs};

    @{$this->{LIST}} = ();

    %anchornames = ();

    # Initial cleanup
    $text =~ s/\r//g;
    # whitespace before <! tag (if it is the first thing) is illegal
    $text =~ s/^\s+(<![a-z])/$1/i;

    # clutch to enforce correct rendering at end of doc
    $text =~ s/\n?$/\n<nop>\n/s;

    # Maps of placeholders to tag parameters and text
    my $removed = {};

    # verbatim before literal - see Item3431
    $text = $this->takeOutBlocks( $text, 'verbatim', $removed );
    $text = $this->takeOutBlocks( $text, 'literal', $removed );

    $text = $this->_takeOutProtected( $text, qr/<\?([^?]*)\?>/s,               'comment',  $removed );
    $text = $this->_takeOutProtected( $text, qr/<!DOCTYPE([^<>]*)>?/mi,        'comment',  $removed );
    $text = $this->_takeOutProtected( $text, qr/<head.*?<\/head>/si,           'head',     $removed );
    $text = $this->_takeOutProtected( $text, qr/<textarea\b.*?<\/textarea>/si, 'textarea', $removed );
    $text = $this->_takeOutProtected( $text, qr/<script\b.*?<\/script>/si,     'script',   $removed );

    # DEPRECATED startRenderingHandler before PRE removed
    # SMELL: could parse more efficiently if this wasn't
    # here.
    $plugins->dispatch( 'startRenderingHandler', $text, $theWeb, $theTopic );

    $text = $this->takeOutBlocks( $text, 'pre', $removed );

    # Join lines ending in '\' (don't need \r?, it was removed already)
    $text =~ s/\\\n//gs;

    $plugins->dispatch( 'preRenderingHandler', $text, $removed );

    if( $plugins->haveHandlerFor( 'insidePREHandler' )) {
        foreach my $region ( sort keys %$removed ) {
            next unless ( $region =~ /^pre\d+$/i );
            my @lines = split( /\r?\n/, $removed->{$region}{text} );
            my $rt = '';
            while ( scalar( @lines )) {
                my $line = shift( @lines );
                $plugins->dispatch( 'insidePREHandler', $line );
                if ( $line =~ /\n/ ) {
                    unshift( @lines, split( /\r?\n/, $line ));
                    next;
                }
                $rt .= $line."\n";
            }
            $removed->{$region}{text} = $rt;
        }
    }

    if( $plugins->haveHandlerFor( 'outsidePREHandler' )) {
        # DEPRECATED - this is the one call preventing
        # effective optimisation of the TWiki ML processing loop,
        # as it exposes the concept of a 'line loop' to plugins,
        # but HTML is not a line-oriented language (though TML is).
        # But without it, a lot of processing could be moved
        # outside the line loop.
        my @lines = split( /\r?\n/, $text );
        my $rt = '';
        while ( scalar( @lines ) ) {
            my $line = shift( @lines );
            $plugins->dispatch( 'outsidePREHandler', $line );
            if ( $line =~ /\n/ ) {
                unshift( @lines, split( /\r?\n/, $line ));
                next;
            }
            $rt .= $line . "\n";
        }

        $text = $rt;
    }

    # Escape rendering: Change ' !AnyWord' to ' <nop>AnyWord',
    # for final ' AnyWord' output
    $text =~ s/$STARTWW\!(?=[\w\*\=\@])/<nop>/gm;

    # Blockquoted email (indented with '> ')
    # Could be used to provide different colors for different numbers of '>'
    $text =~ s/^>(.*?)$/'&gt;'.CGI::cite( $1 ).CGI::br()/gem;

    # Locate isolated < and > and translate to entities
    # Protect isolated <!-- and -->
    $text =~ s/<!--/{$TWiki::TranslationToken!--/g;
    $text =~ s/-->/--}$TWiki::TranslationToken/g;
    # SMELL: this next fragment does not handle the case where HTML tags
    # are embedded in the values provided to other tags. The only way to
    # do this correctly is to parse the HTML (bleagh!). So we just assume
    # they have been escaped.
    $text =~ s/<(\/?\w+(:\w+)?)>/{$TWiki::TranslationToken$1}$TWiki::TranslationToken/g;
    $text =~ s/<(\w+(:\w+)?(\s+.*?|\/)?)>/{$TWiki::TranslationToken$1}$TWiki::TranslationToken/g;
    # XML processing instruction only valid at start of text
    $text =~ s/^<(\?\w.*?\?)>/{$TWiki::TranslationToken$1}$TWiki::TranslationToken/g;

    # entitify lone < and >, praying that we haven't screwed up :-(
    # Item1985: CDATA sections are not lone < and >
    $text =~ s/<(?!\!\[CDATA\[)/&lt\;/g;
    $text =~ s/(?<!\]\])>/&gt\;/g;
    $text =~ s/{$TWiki::TranslationToken/</go;
    $text =~ s/}$TWiki::TranslationToken/>/go;

    # standard URI
    $text =~ s/(^|[-*\s(|])($TWiki::regex{linkProtocolPattern}:([^\s<>"]+[^\s*.,!?;:)<|]))/$1._externalLink( $this,$2)/geo;

    # other entities
    $text =~ s/&(\w+);/$TWiki::TranslationToken$1;/g;      # "&abc;"
    $text =~ s/&(#x?[0-9a-f]+);/$TWiki::TranslationToken$1;/gi;  # "&#123;"
    $text =~ s/&/&amp;/g;                         # escape standalone "&"
    $text =~ s/$TWiki::TranslationToken(#x?[0-9a-f]+;)/&$1/goi;
    $text =~ s/$TWiki::TranslationToken(\w+;)/&$1/go;

    # '#WikiName' anchors (moved in front in order to retain original names if possible)
    # SMELL: in case this type of anchor (presumably user-defined) gets renamed, it should be noted somewhere
    $text =~ s/^(\#)($TWiki::regex{wikiWordRegex})/CGI::a({name=>$this->makeUniqueAnchorName($theWeb,$theTopic,$2)},'')/geom;

    # Headings
    # '<h6>...</h6>' HTML rule
    $text =~ s/$TWiki::regex{headerPatternHt}/_makeAnchorHeading($this,$2,$1,$theTopic,$theWeb)/geo;
    # '----+++++++' rule
    $text =~ s/$TWiki::regex{headerPatternDa}/_makeAnchorHeading($this,$2,(length($1)),$theTopic,$theWeb)/geo;

    # Horizontal rule
    my $hr = CGI::hr();
    $text =~ s/^---+/$hr/gm;

    # Now we really _do_ need a line loop, to process TML
    # line-oriented stuff.
    my $isList = 0;  # 1 when within a list, -1 when list cleanup is required, 0 when outside of list
    my $tableRow = 0;
    my @result;
    my $isFirst = 1;
    my $olStyle = { 'A' => 'upper-alpha', 'a' => 'lower-alpha', 'I' => 'upper-roman', 'i' => 'lower-roman' };
    my $emptyP = $TWiki::cfg{OpenClosePTags} ? '<p></p>' : '<p />';
    my $tablePluginEnabled = $session->inContext( 'TablePluginEnabled' );
    foreach my $line ( split( /\r?\n/, $text )) {
        # Table: | cell | cell |
        # allow trailing white space after the last |
        if( !$tablePluginEnabled && $line =~ m/^(\s*)\|.*\|\s*$/ ) {
            unless( $tableRow ) {
                # mark the head of the table
                push( @result, $TABLEMARKER );
            }
            $line =~ s/^(\s*)\|(.*)/$1._emitTR( $this, $2 )/e;
            $tableRow++;
        } elsif( $tableRow ) {
            _addTHEADandTFOOT( \@result );
            push( @result, '</table>' );
            $tableRow = 0;
        }

        # Lists and paragraphs
        if ( $line =~ m/^\s*$/ ) {
            unless( $tableRow || $isFirst ) {
                $line = $emptyP;
            }
            $isList = -1 if( $isList );
        }
        elsif ( $line =~ m/^\S/ ) {
            $isList = -1 if( $isList );
        }
        elsif ( $line =~ m/^(\t|   )+\S/ ) {
            if ( $line =~ s/^((\t|   )+)\$\s(([^:]+|:[^\s]+)+?):\s/<dt> $3 <\/dt><dd> / ) {
                # Definition list
                _addListItem( $this, \@result, 'dl', 'dd', $1 );
                $isList = 1;
            }
            elsif ( $line =~ s/^((\t|   )+)(\S+?):\s/<dt> $3<\/dt><dd> /o ) {
                # Definition list
                _addListItem( $this, \@result, 'dl', 'dd', $1 );
                $isList = 1;
            }
            elsif ( $line =~ s/^((\t|   )+)\* icon:([^ ]+) /'<li class="twikiIconBullet" style="background: url(' . $session->formatIcon( $3, '$urlpath', 'blank' ) . ') no-repeat 0 .2em;"> '/eo ) {
                # Unordered list with bullet icon
                _addListItem( $this, \@result, 'ul', 'li', $1 );
                $isList = 1;
            }
            elsif ( $line =~ s/^((\t|   )+)\* /<li> /o ) {
                # Unordered list
                _addListItem( $this, \@result, 'ul', 'li', $1 );
                $isList = 1;
            }
            elsif ( $line =~ m/^((\t|   )+)([1AaIi]\.|\d+\.?) ?/ ) {
                # Numbered list
                my $ot = $3;
                $ot =~ s/^(.).*/$1/;
                if( $olStyle->{$ot} ) {
                    $ot = ' style="list-style-type: '.$olStyle->{$ot}.';"';
                } else {
                    $ot = '';
                }
                $line =~ s/^((\t|   )+)([1AaIi]\.|\d+\.?) ?/<li$ot> /;
                _addListItem( $this, \@result, 'ol', 'li', $1 );
                $isList = 1;
            }
            elsif( $isList && $line =~ /^(\t|   )+\s*\S/ ) {
                # indented line extending prior list item
                push( @result, $line );
                next;
            }
            else {
                $isList = -1 if( $isList );
            }
        } elsif( $isList && $line =~ /^(\t|   )+\s*\S/ ) {
            # indented line extending prior list item; case where indent
            # starts with is at least 3 spaces or a tab, but may not be a
            # multiple of 3.
            push( @result, $line );
            next;
        }

        # Finish the list
        if( $isList < 0 ) {
            _addListItem( $this, \@result, '', '', '' );
            $isList = 0;
        } elsif( !$isFirst && !$isList ) {
            push( @result, "\n" );
        }
        $isFirst = 0;

        push( @result, $line );
    }

    if( $tableRow ) {
        _addTHEADandTFOOT( \@result );
        push( @result, '</table>' );
    }
    _addListItem( $this, \@result, '', '', '' );

    $text = join( '', @result );

    # <nop>WikiWords
    $text =~ s/${STARTWW}==(\S+?|\S[^\n]*?\S)==$ENDWW/_fixedFontText($1,1)/gem;
    $text =~ s/${STARTWW}__(\S+?|\S[^\n]*?\S)__$ENDWW/<strong><em>$1<\/em><\/strong>/gm;
    $text =~ s/${STARTWW}\*(\S+?|\S[^\n]*?\S)\*$ENDWW/<strong>$1<\/strong>/gm;
    $text =~ s/${STARTWW}\_(\S+?|\S[^\n]*?\S)\_$ENDWW/<em>$1<\/em>/gm;
    $text =~ s/${STARTWW}\=(\S+?|\S[^\n]*?\S)\=$ENDWW/_fixedFontText($1,0)/gem;

    # Fix for Item6165: Moved mailto rendering to below [[][]] rendering (broken link if link text has e-mail address)

    # Handle [[][] and [[]] links
    # Escape rendering: Change ' ![[...' to ' [<nop>[...', for final unrendered ' [[...' output
    $text =~ s/(^|\s)\!\[\[/$1\[<nop>\[/gm;
    # Spaced-out Wiki words with alternative link text
    # i.e. [[$1][$3]]
    $text =~ s/\[\[([^\]\[\n]+)\](\[([^\]\n]+)\])?\]/_handleSquareBracketedLink( $this,$theWeb,$theTopic,$1,$3)/ge;

    # Mailto e-mail addresses must always be 7-bit, even within I18N sites
    # Normal mailto:foo@example.com ('mailto:' part optional)
    $text =~ s/$STARTWW((mailto\:)?$TWiki::regex{emailAddrRegex})$ENDWW/_mailLink( $this, $1 )/gem;

    # Twitter ID, e.g. @twiki
    $text =~ s/$STARTWW\@([a-zA-Z0-9_]+)/_twitterLink( $this, $1 )/gem;

    unless( TWiki::isTrue( $prefs->getPreferencesValue('NOAUTOLINK')) ) {
        # Handle WikiWords
        $text = $this->takeOutBlocks( $text, 'noautolink', $removed );
        $text =~ s/$STARTWW(?:($TWiki::regex{webNameRegex})\.)?($TWiki::regex{wikiWordRegex}|$TWiki::regex{abbrevRegex})($TWiki::regex{anchorRegex})?/_handleWikiWord( $this,$theWeb,$1,$2,$3)/geom;
        $this->putBackBlocks( \$text, $removed, 'noautolink' );
    }

    $this->putBackBlocks( \$text, $removed, 'pre' );

    # DEPRECATED plugins hook after PRE re-inserted
    $plugins->dispatch( 'endRenderingHandler', $text );

    $this->_putBackProtected( \$text,       'script',   $removed, \&_filterScript );
    $this->_putBackProtected( \$text,       'textarea', $removed );
    $this->_putBackProtected( \$text,       'head',     $removed );
    $this->_putBackProtected( \$text,       'comment',  $removed );
    $this->putBackBlocks( \$text, $removed, 'literal', '', \&_filterLiteral );

    # replace verbatim with pre in the final output
    $this->putBackBlocks( \$text, $removed, 'verbatim', 'pre', \&verbatimCallBack );
    $text =~ s|\n?<nop>\n$||o; # clean up clutch

    $this->{session}->{users}->{loginManager}->endRenderingHandler( $text );

    $plugins->dispatch( 'postRenderingHandler', $text );

    return $text;
}

=pod

---++ StaticMethod verbatimCallBack

Callback for use with putBackBlocks that replaces &lt; and >
by their HTML entities &amp;lt; and &amp;gt;

=cut

sub verbatimCallBack {
    my $val = shift;

    # SMELL: A shame to do this, but been in TWiki.org have converted
    # 3 spaces to tabs since day 1
    $val =~ s/\t/   /g;

    return TWiki::entityEncode( $val );
}

# Only put script and literal sections back if they are allowed by options
sub _filterLiteral {
    my $val = shift;
    return $val if( $TWiki::cfg{AllowInlineScript} );
    return CGI::comment('<literal> is not allowed on this site');
}

sub _filterScript {
    my $val = shift;
    return $val if( $TWiki::cfg{AllowInlineScript} );
    return CGI::comment('<script> is not allowed on this site');
}

=pod

---++ ObjectMethod TML2PlainText( $text, $web, $topic, $opts ) -> $plainText

Clean up TWiki text for display as plain text without pushing it
through the full rendering pipeline. Intended for generation of
topic and change summaries. Adds nop tags to prevent TWiki
subsequent rendering; nops get removed at the very end.

Defuses TML.

$opts:
   * showvar - shows !%VAR% names if not expanded
   * expandvar - expands !%VARS%
   * nohead - strips ---+ headings at the top of the text
   * showmeta - does not filter meta-data
   * entityencode - entity encode the resulting plain text (for title parameter)

=cut

sub TML2PlainText {
    my( $this, $text, $web, $topic, $opts ) = @_;
    $opts ||= '';
    my $nopToken = "\0nop\0";

    $text =~ s/\r//g;  # SMELL, what about OS10?

    if( $opts =~ /showmeta/ ) {
        $text =~ s/%META:/%<nop>META:/g;
    } else {
        $text =~ s/%META:[A-Z].*?}%//g;
    }

    if( $opts =~ /expandvar/ ) {
        $text =~ s/(\%)(SEARCH)\{/$1<nop>$2/g; # prevent recursion
        $text = $this->{session}->handleCommonTags( $text, $web, $topic );
    } else {
        $text =~ s/%WEB%/$web/g;
        $text =~ s/%TOPIC%/$topic/g;
        my $wtn = $this->{session}->{prefs}->getPreferencesValue( 'WIKITOOLNAME' ) || '';
        $text =~ s/%WIKITOOLNAME%/$wtn/g;
        if( $opts =~ /showvar/ ) {
            $text =~ s/%($TWiki::regex{tagNameRegex}\{)/$1/g; # defuse %VARIABLE{ ...
            $text =~ s/(})%/$1/g;    #        ... }%
        } else {
            # Remove %MAKETEXT{"..."}% but preserve text:
            $text =~ s/%MAKETEXT\{ *"?([^"}]*).*?}%/$1/go; # FIXME: Properly resolve params
            # Remove nested %VAR1{ ... %VAR2{...}% ...}% by
            # first adding nesting level to parenthesis,
            # e.g. "%A{%B{...}%}% ... %C{%D{...}%}%"
            # gets "A-esc-1{B-esc-2{...-esc-2}-esc-1} ... C-esc-1{D-esc-2{...-esc-2}-esc-1}"
            my $escToken = "\0-esc-\0";
            my $level = 0;
            $text =~ s/%$TWiki::regex{tagNameRegex}(\{)|(\})%/_addNestingLevel($1, $2, \$level, $escToken)/geo;
            # then removing whole nested block non-greedily, one by one
            $text =~ s/($escToken[0-9]+)\{.*?\1\}//gos;
            # clean up unbalanced stuff:
            $text =~ s/$escToken[0-9]+[\{\}]//go;
            # Remove all simple %VARIABLES% that don't have parameters:
            $text =~ s/%$TWiki::regex{tagNameRegex}%//go;
            # Replace escape of %<nop>VARIABLE{}% with a space:
            $text =~ s/%<nop>($TWiki::regex{tagNameRegex})/% $1/go;
        }
    }

    # Remove #AnchorNames at the beginning of lines:
    $text =~ s/^#$TWiki::regex{wikiWordRegex}//gom;

    # Format e-mail to add spam padding (HTML tags removed later)
    $text =~ s/$STARTWW((mailto\:)?[a-zA-Z0-9-_.+]+@[a-zA-Z0-9-_.]+\.[a-zA-Z0-9-_]+)$ENDWW/_mailLink( $this, $1 )/gem;
    $text =~ s/<!--.*?-->//gs;          # remove all HTML comments
    $text =~ s|<nop[ /]*>|$nopToken|g;  # escape <nop>
    $text =~ s/<[^>]*>//g;              # remove all HTML tags
    $text =~ s/\&[a-z]+;/ /g;           # remove entities
    if( $opts =~ /nohead/ ) {
        # skip headings on top
        while( $text =~ s/^\s*\-\-\-+\+[^\n\r]*// ) {}; # remove heading
    }
    # keep only link text of [[prot://uri.tld/ link text]] or [[][]]
    $text =~ s/\[\[$TWiki::regex{linkProtocolPattern}\:([^\s<>"]+[^\s*.,!?;:)<|])\s+(.*?)\]\]/$3/g;
    $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$2/g;
    # remove "Web." prefix from "Web.TopicName" link
    $text =~ s/$STARTWW(($TWiki::regex{webNameRegex})\.($TWiki::regex{wikiWordRegex}|$TWiki::regex{abbrevRegex}))/$3/g;
    $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;  # remove Wiki formatting chars
    $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;  # remove heading formatting and hbar
    $text =~ s/[\+\-]+/ /g;             # remove special chars
    $text =~ s/[\"\']/`/g;              # change quotes to not interfere if used in html tag attributes
    $text =~ s/^\s+//;                  # remove leading whitespace
    $text =~ s/\s+$//;                  # remove trailing whitespace
    $text =~ s/!(\w+)/$1/gs;            # remove all ! nop exclamation marks before words
    $text =~ s/[\r\n]+/\n/s;
    $text =~ s/[ \t]+/ /s;              # consolidate multiple spaces into one
    $text =~ s/$nopToken/<nop>/g;       # restore <nop>

    if( $opts =~ /entityencode/ ) {
        $text =~ s/<nop>//g;            # remove <nop> tags
        $text = TWiki::entityEncode( $text, ' (),' );
    }
    return $text;
}

# =========================
sub _addNestingLevel
{
  my( $theOpen, $theClose, $theLevelRef, $escToken ) = @_;

  my $result = "";
  if( $theOpen ) {
    $$theLevelRef++;
    $result = "$escToken$$theLevelRef$theOpen";
  } else {
    $result = "$escToken$$theLevelRef$theClose";
    $$theLevelRef-- if( $$theLevelRef > 0 );
  }
  return $result;
}

=pod

---++ ObjectMethod protectPlainText($text) -> $tml

Protect plain text from expansions that would normally be done
duing rendering, such as wikiwords. Topic summaries, for example,
have to be protected this way.

=cut

sub protectPlainText {
    my( $this, $text ) = @_;

    # prevent text from getting rendered in inline search and link tool
    # tip text by escaping links (external, internal, Interwiki)
#    $text =~ s/(?<=[\s\(])((($TWiki::regex{webNameRegex})\.)?($TWiki::regex{wikiWordRegex}|$TWiki::regex{abbrevRegex}))/<nop>$1/g;
#    $text =~ s/(^|(<=\W))((($TWiki::regex{webNameRegex})\.)?($TWiki::regex{wikiWordRegex}|$TWiki::regex{abbrevRegex}))/<nop>$1/g;
    $text =~ s/((($TWiki::regex{webNameRegex})\.)?($TWiki::regex{wikiWordRegex}|$TWiki::regex{abbrevRegex}))/<nop>$1/g;

#    $text =~ s/(?<=[\s\(])($TWiki::regex{linkProtocolPattern}\:)/<nop>$1/go;
#    $text =~ s/(^|(<=\W))($TWiki::regex{linkProtocolPattern}\:)/<nop>$1/go;
    $text =~ s/($TWiki::regex{linkProtocolPattern}\:)/<nop>$1/go;
    $text =~ s/([@%])/<nop>$1<nop>/g;    # email address, variable

    # Encode special chars into XML &#nnn; entities for use in RSS feeds
    # - no encoding for HTML pages, to avoid breaking international
    # characters. Only works for ISO-8859-1 sites, since the Unicode
    # encoding (&#nnn;) is identical for first 256 characters.
    # I18N TODO: Convert to Unicode from any site character set.
    if( $this->{session}->inContext( 'rss' ) &&
          defined( $TWiki::cfg{Site}{CharSet} ) &&
            $TWiki::cfg{Site}{CharSet} =~ /^iso-?8859-?1$/i ) {
        $text =~ s/([\x7f-\xff])/"\&\#" . unpack( 'C', $1 ) .';'/ge;
    }

    return $text;
}

=pod

---++ ObjectMethod makeTopicSummary (  $theText, $theTopic, $theWeb, $theFlags ) -> $tml

Makes a plain text summary of the given topic by simply trimming a bit
off the top. Truncates to $TMTRUNC chars or, if a number is specified in $theFlags,
to that length.

=cut

sub makeTopicSummary {
    my( $this, $theText, $theTopic, $theWeb, $theFlags ) = @_;
    $theFlags ||= '';

    my $htext = $this->TML2PlainText( $theText, $theWeb, $theTopic, $theFlags);
    $htext =~ s/\n+/ /g;

    # FIXME I18N: Avoid splitting within multi-byte characters (e.g. EUC-JP
    # encoding) by encoding bytes as Perl UTF-8 characters in Perl 5.8+.
    # This avoids splitting within a Unicode codepoint (or a UTF-16
    # surrogate pair, which is encoded as a single Perl UTF-8 character),
    # but we ideally need to avoid splitting closely related Unicode codepoints.
    # Specifically, this means Unicode combining character sequences (e.g.
    # letters and accents) - might be better to split on word boundary if
    # possible.

    # limit to n chars
    my $nchar = $theFlags;
    unless( $nchar =~ s/^.*?([0-9]+).*$/$1/ ) {
        $nchar = $TMLTRUNC;
    }
    $nchar = $MINTRUNC if( $nchar < $MINTRUNC );
    if ( length( $htext ) > $nchar ) {
        # truncate but keep full words (up to max 20 extra chars)
        $htext =~ s/^(.{$nchar}[$TWiki::regex{mixedAlphaNum}]{0,20}).*$/$1/s;
        $htext =~ s/&?#?[0-9]*$//; # remove damaged trailing entity encodes
        $htext =~ s/ *$//;         # remove trailing spaces
        $htext = chompUtf8Fragment( $htext ) . '...';
    }

    # We do not want the summary to contain any $variable that formatted
    # searches can interpret to anything (Item3489).
    # Especially new lines (Item2496)
    # To not waste performance we simply replace $ by $<nop>
    $htext =~ s/\$/\$<nop>/g;
    # Escape Interwiki links and other side effects introduced by
    # plugins later in the rendering pipeline (Item4748)
    $htext =~ s/\:/<nop>\:/g;
    $htext =~ s/\s+/ /g;

    return $this->protectPlainText( $htext );
}

# _takeOutProtected( \$text, $re, $id, \%map ) -> $text
#
#   * =$text= - Text to process
#   * =$re= - Regular expression that matches tag expressions to remove
#   * =\%map= - Reference to a hash to contain the removed blocks
#
# Return value: $text with blocks removed. Unlike takeOuBlocks, this
# *preserves* the tags.
#
# used to extract from $text comment type tags like &lt;!DOCTYPE blah>
#
# WARNING: if you want to take out &lt;!-- comments --> you _will_ need
# to re-write all the takeOuts to use a different placeholder
sub _takeOutProtected {
    my( $this, $intext, $re, $id, $map ) = @_;

    $intext =~ s/($re)/_replaceBlock($1, $id, $map)/ge;

    return $intext;
}

sub _replaceBlock {
    my( $scoop, $id, $map ) = @_;
    my $placeholder = $placeholderMarker;
    $placeholderMarker++;
    $map->{$id.$placeholder}{text} = $scoop;

    return '<!--'.$TWiki::TranslationToken.$id.$placeholder
        .  $TWiki::TranslationToken.'-->';
}

# _putBackProtected( \$text, $id, \%map, $callback ) -> $text
# Return value: $text with blocks added back
#   * =\$text= - reference to text to process
#   * =$id= - type of taken-out block e.g. 'verbatim'
#   * =\%map= - map placeholders to blocks removed by takeOutBlocks
#   * =$callback= - Reference to function to call on each block being inserted (optional)
#
#Reverses the actions of takeOutProtected.
sub _putBackProtected {
    my( $this, $text, $id, $map, $callback ) = @_;
    ASSERT(ref($map) eq 'HASH') if DEBUG;

    foreach my $placeholder ( keys %$map ) {
        next unless $placeholder =~ /^$id\d+$/;
        my $val = $map->{$placeholder}{text};
        $val = &$callback( $val ) if( defined( $callback ));
        $$text =~ s/<!--$TWiki::TranslationToken$placeholder$TWiki::TranslationToken-->/$val/;
        delete( $map->{$placeholder} );
    }
}

=pod

---++ ObjectMethod takeOutBlocks( \$text, $tag, \%map ) -> $text

   * =$text= - Text to process
   * =$tag= - XHTML-style tag.
   * =\%map= - Reference to a hash to contain the removed blocks

Return value: $text with blocks removed

Searches through $text and extracts blocks delimited by a tag, appending each
onto the end of the @buffer and replacing with a token
string which is not affected by TWiki rendering.  The text after these
substitutions is returned.

Parameters to the open tag are recorded.

This is _different_ to takeOutProtected, because it requires tags
to be on their own line. it also supports a callback for post-
processing the data before re-insertion.

=cut

sub takeOutBlocks {
    my( $this, $intext, $tag, $map ) = @_;

    return $intext unless( $intext =~ m/<$tag\b/i );

    my $out = '';
    my $depth = 0;
    my $scoop;
    my $tagParams;

    foreach my $token ( split/(<\/?$tag[^>]*>)/i, $intext ) {
        if ($token =~ /<$tag\b([^>]*)?>/i) {
            $depth++;
            if ($depth eq 1) {
                $tagParams = $1;
                next;
            }
        } elsif ($token =~ /<\/$tag>/i) {
            if ($depth > 0) {
                $depth--;
                if ($depth eq 0) {
                    my $placeholder = $tag.$placeholderMarker;
                    $placeholderMarker++;
                    $map->{$placeholder}{text} = $scoop;
                    $map->{$placeholder}{params} = $tagParams;
                    $out .= '<!--'.$TWiki::TranslationToken.$placeholder.$TWiki::TranslationToken.'-->';
                    $scoop = '';
                    next;
                }
            }
        }
        if ($depth > 0) {
            $scoop .= $token;
        } else {
            $out .= $token;
        }
    }

    # unmatched tags
    if (defined($scoop) && ($scoop ne '')) {
        my $placeholder = $tag.$placeholderMarker;
        $placeholderMarker++;
        $map->{$placeholder}{text} = $scoop;
        $map->{$placeholder}{params} = $tagParams;
        $out .= '<!--'.$TWiki::TranslationToken.$placeholder.$TWiki::TranslationToken.'-->';
    }

    return $out;
}

=pod

---++ ObjectMethod putBackBlocks( \$text, \%map, $tag, $newtag, $callBack ) -> $text

Return value: $text with blocks added back
   * =\$text= - reference to text to process
   * =\%map= - map placeholders to blocks removed by takeOutBlocks
   * =$tag= - Tag name processed by takeOutBlocks
   * =$newtag= - Tag name to use in output, in place of $tag. If undefined, uses $tag.
   * =$callback= - Reference to function to call on each block being inserted (optional)

Reverses the actions of takeOutBlocks.

Each replaced block is processed by the callback (if there is one) before
re-insertion.

Parameters to the outermost cut block are replaced into the open tag,
even if that tag is changed. This allows things like
&lt;verbatim class=''>
to be mapped to
&lt;pre class=''>

Cool, eh what? Jolly good show.

And if you set $newtag to '', we replace the taken out block with the valuse itself
   * which i'm using to stop the rendering process, but then at the end put in the html directly
   (for <literal> tag.

=cut

sub putBackBlocks {
    my( $this, $text, $map, $tag, $newtag, $callback ) = @_;

    $newtag = $tag if (!defined($newtag));

    foreach my $placeholder ( keys %$map ) {
        if( $placeholder =~ /^$tag\d+$/ ) {
            my $params = $map->{$placeholder}{params} || '';
            my $val = $map->{$placeholder}{text};
            $val = &$callback( $val ) if ( defined( $callback ));
            if ($newtag eq '') {
                $$text =~ s(<!--$TWiki::TranslationToken$placeholder$TWiki::TranslationToken-->)($val);
            } else {
                $$text =~ s(<!--$TWiki::TranslationToken$placeholder$TWiki::TranslationToken-->)
                  (<$newtag$params>$val</$newtag>);
            }
            delete( $map->{$placeholder} );
        }
    }
}

=pod

---++ ObjectMethod renderRevisionInfo($web, $topic, $meta, $rev, $format) -> $string

Obtain and render revision info for a topic.
   * =$web= - the web of the topic
   * =$topic= - the topic
   * =$meta= if specified, get rev info from here. If not specified, or meta contains rev info for a different version than the one requested, will reload the topic
   * =$rev= - the rev number, defaults to latest rev
   * =$format= - the render format, defaults to =$rev - $time - $wikiusername=
=$format= can contain the following keys for expansion:
   | =$web= | the web name |
   | =$topic= | the topic name |
   | =$rev= | the rev number |
   | =$comment= | the comment |
   | =$username= | the login of the saving user |
   | =$wikiname= | the wikiname of the saving user |
   | =$wikiusername= | the web.wikiname of the saving user |
   | =$date= | the date of the rev (no time) |
   | =$time= | the time of the rev |
   | =$min=, =$sec=, etc. | Same date format qualifiers as GMTIME |

=cut

sub renderRevisionInfo {
    my( $this, $web, $topic, $meta, $rrev, $format ) = @_;
    my $store = $this->{session}->{store};

    if( $rrev ) {
        $rrev = $store->cleanUpRevID( $rrev );
    }

    # normalise
    ( $web, $topic ) = $this->{session}->normalizeWebTopicName( $web, $topic );

    my( $date, $user, $rev, $comment );
    if( $meta ) {
        ( $date, $user, $rev, $comment ) = $meta->getRevisionInfo( $rrev );
    } else {
        my $text;
        if( $store->topicExists( $web, $topic )) {
            ( $meta, $text ) = $store->readTopic( undef, $web, $topic, $rrev );
            ( $date, $user, $rev, $comment ) = $meta->getRevisionInfo( $rrev );
        } else {
            # non-existant topic
            $date = 0;
            $user = undef;
            $rev = 0;
            $comment = '';
        }
    }

    my $wun = '';
    my $wn = '';
    my $un = '';
    if( $user ) {
        # $meta->getRevisionInfo() gets $user in cUID even for a topic
        # saved in pre-cUID days as long as the $user is valid.
        # However $user may be invalid.
        my $users = $this->{session}->{users};
        if ( defined($users->getLoginName($user)) ) {
            # only if $user is a valid cUID
            $wun = $users->webDotWikiName($user);
            $wn = $users->getWikiName($user);
            $un = $users->getLoginName($user);
        }
        # If $user is invalid, then use whatever is saved in the meta.
        # But obscure it if the RenderLoggedInButUnknownUsers is enabled.
        $user = 'unknown' if $TWiki::cfg{RenderLoggedInButUnknownUsers};
        $wun ||= $TWiki::cfg{UsersWebName} . '.' . $user;
        $wn ||= $user;
        $un ||= $user;
    }

    my $value = $format || 'r$rev - $date - $time - $wikiusername';
    $value =~ s/\$web/$web/gi;
    $value =~ s/\$topic/$topic/gi;
    $value =~ s/\$rev/$rev/gi;
    $value =~ s/\$time/TWiki::Time::formatTime( $date, '$hour:$min:$sec')/gei;
    $value =~ s/\$date/TWiki::Time::formatTime( $date, $TWiki::cfg{DefaultDateFormat} )/gei;
    $value =~ s/(\$(rcs|http|email|iso))/TWiki::Time::formatTime($date, $1 )/gei;
    if( $value =~ /\$(sec|min|hou|day|wday|dow|week|mo|ye|epoch|tz)/ ) {
        $value = TWiki::Time::formatTime( $date, $value );
    }
    $value =~ s/\$comment/$comment/gi;
    $value =~ s/\$username/$un/gi;
    $value =~ s/\$wikiname/$wn/gi;
    $value =~ s/\$wikiusername/$wun/gi;

    return $value;
}

=pod

---++ ObjectMethod summariseChanges($user, $web, $topic, $orev, $nrev, $tml) -> $text

   * =$user= - user (null to ignore permissions)
   * =$web= - web
   * =$topic= - topic
   * =$orev= - older rev
   * =$nrev= - later rev
   * =$tml= - if true will generate renderable TML (i.e. HTML with NOPs. if false will generate a summary suitable for use in plain text (mail, for example)
Generate a (max 3 line) summary of the differences between the revs.

If there is only one rev, a topic summary will be returned.

If =$tml= is not set, all HTML will be removed.

In non-tml, lines are truncated to 70 characters. Differences are shown using + and - to indicate added and removed text.

=cut

sub summariseChanges {
    my( $this, $user, $web, $topic, $orev, $nrev, $tml ) = @_;
    my $summary = '';
    my $store = $this->{session}->{store};

    $orev = $nrev - 1 unless (defined($orev) || !defined($nrev));

    my( $nmeta, $ntext ) = $store->readTopic( $user, $web, $topic, $nrev );

    if( $nrev && $nrev > 1 && $orev ne $nrev ) {
        my $metaPick = qr/^[A-Z](?!OPICINFO)/; # all except TOPICINFO
        # there was a prior version. Diff it.
        $ntext = $this->TML2PlainText( $ntext, $web, $topic, 'nonop' )."\n".$nmeta->stringify( $metaPick );

        my( $ometa, $otext ) = $store->readTopic( $user, $web, $topic, $orev );
        $otext = $this->TML2PlainText( $otext, $web, $topic, 'nonop' )."\n".$ometa->stringify( $metaPick );

        if( $TWiki::cfg{SummariseSizeLimit} &&
            (length($ntext) > $TWiki::cfg{SummariseSizeLimit} ||
             length($otext) > $TWiki::cfg{SummariseSizeLimit})
        ) {
            $summary =
                $this->{session}{i18n}->maketext(
                    'Text is too big to show the difference.');
        }
        else {
        require TWiki::Merge;
            my $blocks = TWiki::Merge::simpleMerge( $otext, $ntext, qr/[\r\n]+/ );
            # sort through, keeping one line of context either side of a change
            my @revised;
            my $getnext = 0;
            my $prev = '';
            my $ellipsis = $tml ? '&hellip;' : '...';
            my $trunc = $tml ? $TMLTRUNC : $PLAINTRUNC;
            while ( scalar @$blocks && scalar( @revised ) < $SUMMARYLINES ) {
                my $block = shift( @$blocks );
                next unless $block =~ /\S/;
                my $trim = length($block) > $trunc;
                $block =~ s/^(.{$trunc}).*$/$1/ if( $trim );
                if ( $block =~ m/^[-+]/ ) {
                    if( $tml ) {
                        $block =~ s/^-(.*)$/CGI::del( $1 )/se;
                        $block =~ s/^\+(.*)$/CGI::ins( $1 )/se;
                    } elsif ( $this->{session}->inContext('rss')) {
                        $block =~ s/^-/REMOVED: /;
                        $block =~ s/^\+/INSERTED: /;
                    }
                    push( @revised, $prev ) if $prev;
                    $block .= $ellipsis if $trim;
                    push( @revised, $block );
                    $getnext = 1;
                    $prev = '';
                } else {
                    if( $getnext ) {
                        $block .= $ellipsis if $trim;
                        push( @revised, $block );
                        $getnext = 0;
                        $prev = '';
                    } else {
                        $prev = $block;
                    }
                }
            }
            if( $tml ) {
                $summary = join(CGI::br(), @revised );
            } else {
                $summary = join("\n", @revised );
            }
        }
    }

    unless( $summary ) {
        $summary = $this->makeTopicSummary( $ntext, $topic, $web );
    }

    if( ! $tml ) {
        $summary = $this->protectPlainText( $summary );
    }
    return $summary;
}

=pod

---++ ObjectMethod forEachLine( $text, \&fn, \%options ) -> $newText

Iterate over each line, calling =\&fn= on each.
\%options may contain:
   * =pre= => true, will call fn for each line in pre blocks
   * =verbatim= => true, will call fn for each line in verbatim blocks
   * =literal= => true, will call fn for each line in literal blocks
   * =noautolink= => true, will call fn for each line in =noautolink= blocks
The spec of \&fn is =sub fn( $line, \%options ) -> $newLine=. The %options
hash passed into this function is passed down to the sub, and the keys
=in_literal=, =in_pre=, =in_verbatim= and =in_noautolink= are set boolean
TRUE if the line is from one (or more) of those block types.

The return result replaces $line in $newText.

=cut

sub forEachLine {
    my( $this, $text, $fn, $options ) = @_;

    $options->{in_pre} = 0;
    $options->{in_script} = 0;
    $options->{in_verbatim} = 0;
    $options->{in_literal} = 0;
    $options->{in_noautolink} = 0;
    my $newText = '';
    foreach my $line ( split( /([\r\n]+)/, $text ) ) {
        if( $line =~ /[\r\n]/ ) {
            $newText .= $line;
            next;
        }
        $options->{in_verbatim}++ if( $line =~ m|^\s*<verbatim\b[^>]*>\s*$|i );
        $options->{in_verbatim}-- if( $line =~ m|^\s*</verbatim>\s*$|i );
        $options->{in_literal}++ if( $line =~ m|^\s*<literal\b[^>]*>\s*$|i );
        $options->{in_literal}-- if( $line =~ m|^\s*</literal>\s*$|i );
        unless (( $options->{in_verbatim} > 0 ) || (( $options->{in_literal} > 0 ))){
            $options->{in_pre}++ if( $line =~ m|<pre\b|i );
            $options->{in_pre}-- if( $line =~ m|</pre>|i );
            $options->{in_script}++ if( $line =~ m|<script\b|i );
            $options->{in_script}-- if( $line =~ m|</script\s*>|i );
            $options->{in_noautolink}++ if( $line =~ m|^\s*<noautolink\b[^>]*>\s*$|i );
            $options->{in_noautolink}-- if( $line =~ m|^\s*</noautolink>\s*|i );
        }
        unless( $options->{in_pre} > 0 && !$options->{pre} ||
                $options->{in_script} > 0 && !$options->{script} ||
                $options->{in_verbatim} > 0 && !$options->{verbatim} ||
                $options->{in_literal} > 0 && !$options->{literal} ||
                $options->{in_noautolink} > 0 && !$options->{noautolink} ) {
            $line = &$fn( $line, $options );
        }
        $newText .= $line;
    }
    return $newText;
}

=pod

---++ StaticMethod getReferenceRE($web, $topic, %options) -> $re

   * $web, $topic - specify the topic being referred to, or web if $topic is
     undef.
   * %options - the following options are available
      * =interweb= - if true, then fully web-qualified references are required.
      * =grep= - if true, generate a GNU-grep compatible RE instead of the
        default Perl RE.
      * =url= - if set, generates an expression that will match a TWiki
        URL that points to the web/topic, instead of the default which
        matches topic links in plain text.
Generate a regular expression that can be used to match references to the
specified web/topic. Note that the resultant RE will only match fully
qualified (i.e. with web specifier) topic names and topic names that
are wikiwords in text. Works for spaced-out wikiwords for topic names.

The RE returned is designed to be used with =s///=

=cut

sub getReferenceRE {
    my( $web, $topic, %options) = @_;

    my $matchWeb = $web;
    # Convert . and / to [./] (subweb separators)
    $matchWeb =~ s#[./]#[./]#go;

    # Note use of \< and \> to match the empty string at the
    # edges of a word.
    my( $bow, $eow, $forward, $back ) = ( '\b', '\b', '?=', '?<=' );
    if( $options{grep} ) {
        $bow = '\<';
        $eow = '\>';
        $forward = '';
        $back = '';
    }
    my $squabo = "($back\\[\\[)";
    my $squabc = "($forward\\][][])";

    my $re;

    if( $options{url} ) {
        # URL fragment. Assume / separator (while . is legal, it's
        # undocumented and is not common usage)
        $re = "/$web/";
        $re .= $topic.$eow if $topic;
    } else {
        if( defined( $topic )) {
            # Work out spaced-out version (allows lc first chars on words)
            my $sot = TWiki::spaceOutWikiWord( $topic, ' *' );
            if( $sot ne $topic ) {
                $sot =~ s/\b([a-zA-Z])/'['.uc($1).lc($1).']'/ge;
            } else {
                $sot = undef;
            }

            if( $options{interweb} ) {
                # Require web specifier
                $re = "$bow$matchWeb\\.$topic$eow";
                if( $sot ) {
                    # match spaced out in squabs only
                    $re .= "|$squabo$matchWeb\\.$sot$squabc";
                }
            } else {
                # Optional web specifier - but *only* if the topic name
                # is a wikiword
                if( $topic =~ /$TWiki::regex{wikiWordRegex}/ ) {
                    # Bit of jigger-pokery at the front to avoid matching
                    # subweb specifiers
                    $re = "(($back\[^./])|^)$bow($matchWeb\\.)?$topic$eow";
                    if( $sot ) {
                        # match spaced out in squabs only
                        $re .= "|$squabo($matchWeb\\.)?$sot$squabc";
                    }
                } else {
                    # Non-wikiword; require web specifier or squabs
                    $re = "(($back\[^./])|^)$bow$matchWeb\\.$topic$eow";
                    $re .= "|$squabo$topic$squabc";
                }
            }
        } else {
            # Searching for a web
            if( $options{interweb} ) {
                # web name used to refer to a topic
                $re = $bow . '\.' . $matchWeb . '(\.[$TWiki::regex{mixedAlphaNum}]+)' . $eow;
            } else {
                # most general search for a reference to a topic or subweb
                # note that replaceWebReferences() uses $1 from this regex
                $re = $bow . $matchWeb .
                      "(([\/\.][$TWiki::regex{upperAlpha}][$TWiki::regex{mixedAlphaNum}_]*)*" .
                      "\.[$TWiki::regex{mixedAlphaNum}]+)" . $eow;
            }
        }
    }

    return $re;
}

=pod

---++ StaticMethod replaceTopicReferences( $text, \%options ) -> $text

Callback designed for use with forEachLine, to replace topic references.
\%options contains:
   * =oldWeb= => Web of reference to replace
   * =oldTopic= => Topic of reference to replace
   * =newWeb= => Web of new reference
   * =newTopic= => Topic of new reference
   * =inWeb= => the web which the text we are presently processing resides in
   * =fullPaths= => optional, if set forces all links to full web.topic form
For a usage example see TWiki::UI::Manage.pm

=cut

sub replaceTopicReferences {
    my( $text, $args ) = @_;

    ASSERT(defined $args->{oldWeb}) if DEBUG;
    ASSERT(defined $args->{oldTopic}) if DEBUG;

    ASSERT(defined $args->{newWeb}) if DEBUG;
    ASSERT(defined $args->{newTopic}) if DEBUG;

    ASSERT(defined $args->{inWeb}) if DEBUG;

    # Do the traditional TWiki topic references first
    my $oldTopic = $args->{oldTopic};
    my $newTopic = $args->{newTopic};
    my $repl = $newTopic;

    # Canonicalise web names by converting . to /
    my $inWeb = $args->{inWeb}; $inWeb =~ s#\.#/#g;
    my $newWeb = $args->{newWeb}; $newWeb =~ s#\.#/#g;
    my $oldWeb = $args->{oldWeb}; $oldWeb =~ s#\.#/#g;
    my $sameWeb = ($oldWeb eq $newWeb);

    if( $inWeb ne $newWeb || $args->{fullPaths} ) {
        $repl = $newWeb.'.'.$repl;
    }

    my $re = getReferenceRE( $oldWeb, $oldTopic );

    $text =~ s/($re)/_doReplace($1, $newWeb, $repl)/ge;

    # Now URL form
    $repl = "/$newWeb/$newTopic";
    $re = getReferenceRE( $oldWeb, $oldTopic, url => 1);
    $text =~ s/$re/$repl/g;

    return $text;
}

sub _doReplace {
    my ($match, $web, $repl) = @_;
    # Bugs:Item4661 If there is a web defined in the match, then
    # make sure there's a web defined in the replacement.
    if ($match =~ /\./ && $repl !~ /\./) {
        $repl = "$web.$repl";
    }
    return $repl;
}

=pod

---++ StaticMethod replaceWebReferences( $text, \%options ) -> $text

Callback designed for use with forEachLine, to replace web references.
\%options contains:
   * =oldWeb= => Web of reference to replace
   * =newWeb= => Web of new reference
For a usage example see TWiki::UI::Manage.pm

=cut

sub replaceWebReferences {
    my( $text, $args ) = @_;

    ASSERT(defined $args->{oldWeb}) if DEBUG;
    ASSERT(defined $args->{newWeb}) if DEBUG;

    my $newWeb = $args->{newWeb}; $newWeb =~ s#\.#/#g;
    my $oldWeb = $args->{oldWeb}; $oldWeb =~ s#\.#/#g;

    return $text if $oldWeb eq $newWeb;

    my $re = getReferenceRE( $oldWeb, undef);

    $text =~ s/$re/$newWeb$1/g;

    $re = getReferenceRE( $oldWeb, undef, url => 1);

    $text =~ s#$re#/$newWeb/#g;

    return $text;
}

=pod

---++ ObjectMethod replaceWebInternalReferences( \$text, \%meta, $oldWeb, $oldTopic )

Change within-web wikiwords in $$text and $meta to full web.topic syntax.

\%options must include topics => list of topics that must have references
to them changed to include the web specifier.

=cut

sub replaceWebInternalReferences {
    my( $this, $text, $meta, $oldWeb, $oldTopic, $newWeb, $newTopic ) = @_;

    my @topics = $this->{session}->{store}->getTopicNames( $oldWeb );
    my $options = {
             # exclude this topic from the list
             topics  => [ grep { !/^$oldTopic$/ } @topics ],
             inWeb   => $oldWeb,
             inTopic => $oldTopic,
             oldWeb  => $oldWeb,
             newWeb  => $oldWeb,
           };

    $$text = $this->forEachLine( $$text, \&_replaceInternalRefs, $options );

    $meta->forEachSelectedValue( qw/^(FIELD|TOPICPARENT)$/, undef, \&_replaceInternalRefs, $options );
    $meta->forEachSelectedValue( qw/^TOPICMOVED$/,       qw/^by$/, \&_replaceInternalRefs, $options );
    $meta->forEachSelectedValue( qw/^FILEATTACHMENT$/, qw/^user$/, \&_replaceInternalRefs, $options );

    ## Ok, let's do it again, but look for links to topics in the new web and remove their full paths
    @topics = $this->{session}->{store}->getTopicNames( $newWeb );
    $options = {
          # exclude this topic from the list
          topics => [ @topics ],
          fullPaths => 0,
          inWeb => $newWeb,
          inTopic => $oldTopic,
          oldWeb => $newWeb,
          newWeb => $newWeb,
        };

    $$text = $this->forEachLine( $$text, \&_replaceInternalRefs, $options );

    $meta->forEachSelectedValue( qw/^(FIELD|TOPICPARENT)$/, undef, \&_replaceInternalRefs, $options );
    $meta->forEachSelectedValue( qw/^TOPICMOVED$/,       qw/^by$/, \&_replaceInternalRefs, $options );
    $meta->forEachSelectedValue( qw/^FILEATTACHMENT$/, qw/^user$/, \&_replaceInternalRefs, $options );
}

# callback used by replaceWebInternalReferences
sub _replaceInternalRefs {
    my( $text, $args ) = @_;
    foreach my $topic ( @{$args->{topics}} ) {
        $args->{fullPaths} =  ( $topic ne $args->{inTopic} ) if (!defined($args->{fullPaths}));
        $args->{oldTopic} = $topic;
        $args->{newTopic} = $topic;
        $text = replaceTopicReferences( $text, $args );
    }
    return $text;
}

=pod

---++ StaticMethod breakName( $text, $args) -> $text

   * =$text= - text to "break"
   * =$args= - string of format (\d+)([,\s*]\.\.\.)?)
Hyphenates $text every $1 characters, or if $2 is "..." then shortens to
$1 characters and appends "..." (making the final string $1+3 characters
long)

_Moved from Search.pm because it was obviously unhappy there,
as it is a rendering function_

=cut

sub breakName {
    my( $text, $args ) = @_;

    my @params = split( /[\,\s]+/, $args, 2 );
    if( @params ) {
        my $len = $params[0] || 1;
        $len = 1 if( $len < 1 );
        my $sep = '- ';
        $sep = $params[1] if( @params > 1 );
        if( $sep =~ /^\.\.\./i ) {
            # make name shorter like 'ThisIsALongTop...'
            $text =~ s/(.{$len})(.+)/$1.../s;

        } else {
            # split and hyphenate the topic like 'ThisIsALo- ngTopic'
            $text =~ s/(.{$len})/$1$sep/gs;
            $text =~ s/$sep$//;
        }
    }
    return $text;
}

=pod

---++ StaticMethod protectFormFieldValue($value, $attrs) -> $html

Given the value of a form field, and a set of attributes that control how
to display that value, protect the value from further processing.

The protected value is determined from the value of the field after:
   * newlines are replaced with value of $attrs->{newline} if defined
   * processing through breakName if $attrs->{break} is defined
   * escaping of $vars if $attrs->{protectdollar} is defined
   * | is replaced with &amp;#124; or the value of $attrs->{bar} if defined

=cut

sub protectFormFieldValue {
    my( $value, $attrs ) = @_;

    $value = '' unless defined( $value );

    if( $attrs && $attrs->{break} ) {
        $value =~ s/^\s*(.*?)\s*$/$1/g;
        $value = breakName( $value, $attrs->{break} );
    }

    if ( $attrs && $attrs->{encode} ) {
        $value = TWiki::_encode($attrs->{encode}, $value);
    }

    # Item3489, Item2837. Prevent $vars in formfields from
    # being expanded in formatted searches.
    # Fix-Item6167 Removing $attrs->{protectdollar} from
    # if( $attrs && $attrs->{protectdollar}) line to fix Item6167
    # the $attrs->{protectdollar} is mostly set to 1 in Search, but never reached up
    # this point.

    if( $attrs ) {
        $value =~ s/\$(n|nop|quot|percnt|dollar)/\$<nop>$1/g;
    }

    return $value if ( $attrs && $attrs->{encode} );

    # change newlines
    if( $attrs && defined $attrs->{newline} ) {
        my $newline = $attrs->{newline};
        $newline =~ s/\$n/\n/gs;
        $newline =~ s/\$br/<br \/>/gs;
        $value =~ s/\r?\n/$newline/g;
    }

    # change vbars
    my $bar = '&#124;';
    if( $attrs && $attrs->{bar} ) {
        $bar = $attrs->{bar};
    }
    $value =~ s/\|/$bar/g;

    return $value;
}

1;
