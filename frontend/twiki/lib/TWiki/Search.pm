# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2018 Peter Thoeny, peter[at]thoeny.org
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

package TWiki::Search;

=pod

---+ package TWiki::Search

This module implements all the search functionality.

=cut

use strict;
use Assert;
use Error qw( :try );

require TWiki;
require TWiki::Sandbox;
require TWiki::Render; # SMELL: expensive

my $queryParser;

BEGIN {

    # 'Use locale' for internationalisation of Perl sorting and searching -
    # main locale settings are done in TWiki::setupLocale
    # Do a dynamic 'use locale' for this module
    if ( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

=pod

---++ ClassMethod new ($session)

Constructor for the singleton Search engine object.

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
    undef $this->{session};
}

=pod

---++ StaticMethod getTextPattern (  $text, $pattern  )

Sanitise search pattern - currently used for FormattedSearch only

=cut

sub getTextPattern {
    my ( $text, $pattern, $args ) = @_;
    $args ||= '';

    # escape some special chars
    $pattern =~ s/([^\\])([\$\@\%\&\#\'\`\/])/$1\\$2/go;
    $pattern = TWiki::Sandbox::untaintUnchecked($pattern);

    my $OK = 0;
    eval { $OK = ( $text =~ s/$pattern/$1/is ); };
    $text = '' unless ($OK);

    if ( $args =~ /\bencode:(\w+)/ ) {
        $text = TWiki::_encode($1, $text);
    }

    return $text;
}

# Split the search string into tokens depending on type of search.
# Search is an 'AND' of all tokens - various syntaxes implemented
# by this routine.
sub _tokensFromSearchString {
    my ( $this, $searchString, $type ) = @_;

    my @tokens = ();
    if ( $type eq 'regex' ) {

        # Regular expression search Example: soap;wsdl;web service;!shampoo
        @tokens = split( /;/, $searchString );

    }
    elsif ( $type eq 'literal' || $type eq 'query' ) {

        if( $searchString eq '' ) {
            # Legacy: empty search returns nothing
        } else {
            # Literal search (old style) or query
            $tokens[0] = $searchString;
        }

    }
    else {

        # Keyword search (Google-style) - implemented by converting
        # to regex format. Example: soap +wsdl +"web service" -shampoo

        # Prevent tokenizing on spaces in "literal string"
        $searchString =~ s/\"(.*?)\"/&_translateSpace($1)/geo;
        $searchString =~ s/[\+\-]\s+//go;

        # Build pattern of stop words
        my $prefs = $this->{session}->{prefs};
        my $stopWords = $prefs->getPreferencesValue('SEARCHSTOPWORDS') || '';
        $stopWords =~ s/[\s\,]+/\|/go;
        $stopWords =~ s/[\(\)]//go;

        # Tokenize string taking account of literal strings, then remove
        # stop words and convert '+' and '-' syntax.
        @tokens =
          map {
            s/^\+//o;
            s/^\-/\!/o;
            $_
          }    # remove +, change - to !, remove "
          grep { !/^($stopWords)$/i }    # remove stopwords
          map { s/$TWiki::TranslationToken/ /go; $_ }    # restore space
          split( /[\s]+/, $searchString );               # split on spaces
    }

    return @tokens;
}

# Convert spaces into translation token characters (typically NULs),
# preventing tokenization.
#
# FIXME: Terminology confusing here!
sub _translateSpace {
    my $text = shift;
    $text =~ s/\s+/$TWiki::TranslationToken/go;
    return $text;
}

# get a list of topics to search in the web, filtered by the $topic
# spec
sub _getTopicList {
    my( $this, $web, $topic, $options ) = @_;

    my @topicList = ();
    my $store = $this->{session}->{store};
    if ($topic) {

        # limit search to topic list
        if ( $topic =~ /^\^\([\_\-\+$TWiki::regex{mixedAlphaNum}\|]+\)\$$/ ) {

            # topic list without wildcards
            # for speed, do not get all topics in web
            # but convert topic pattern into topic list
            my $topics = $topic;
            $topics =~ s/^\^\(//o;
            $topics =~ s/\)\$//o;

            # build list from topic pattern
            @topicList = grep( $store->topicExists($web, $_), split( /\|/, $topics ));
        }
        else {

            # topic list with wildcards
            @topicList = $store->getTopicNames($web);
            if ( $options->{caseSensitive} ) {

                # limit by topic name,
                @topicList = grep( /$topic/, @topicList );
            }
            else {

                # Codev.SearchTopicNameAndTopicText
                @topicList = grep( /$topic/i, @topicList );
            }
        }
    }
    else {
        @topicList = $store->getTopicNames( $web );
    }
    return @topicList;
}

# Run a query over a list of topics
sub _queryTopics {
    my( $this, $web, $query, @topicList ) = @_;

    my $store = $this->{session}->{store};
    my $matches = $store->searchInWebMetaData( $query, $web, \@topicList );

    return keys %$matches;
}

# Run a search over a list of topics - @tokens is a list of
# search terms to be ANDed together
sub _searchTopics {
    my ( $this, $web, $scope, $type, $options, $tokens, @topicList ) = @_;

    my $store = $this->{session}->{store};

    # default scope is 'text'
    $scope = 'text' unless ( $scope =~ /^(topic|all)$/ );

    # AND search - search once for each token, ANDing result together
    my @tokens = @$tokens;
    foreach my $token ( @tokens ) {

        my $invertSearch = 0;

        $invertSearch = ( $token =~ s/^\!//o );

        # flag for AND NOT search
        my @scopeTextList  = ();
        my @scopeTopicList = ();

        # scope can be 'topic' (default), 'text' or "all"
        # scope='text', e.g. Perl search on topic name:
        unless ( $scope eq 'text' ) {
            my $qtoken = $token;

            # FIXME I18N
            $qtoken = quotemeta($qtoken) if ( $type ne 'regex' );
            if ( $options->{'caseSensitive'} ) {

                # fix for Codev.SearchWithNoPipe
                @scopeTopicList = grep( /$qtoken/, @topicList );
            }
            else {
                @scopeTopicList = grep( /$qtoken/i, @topicList );
            }
        }

        # scope='text', e.g. grep search on topic text:
        unless ( $scope eq 'topic' ) {
            my $matches = $store->searchInWebContent(
                $token, $web,
                \@topicList,
                {
                    type                => $type,
                    scope               => $scope,
                    casesensitive       => $options->{'caseSensitive'},
                    wordboundaries      => $options->{'wordBoundaries'},
                    files_without_match => 1
                   }
               );
            @scopeTextList = keys %$matches;
        }

        if ( @scopeTextList && @scopeTopicList ) {

            # join 'topic' and 'text' lists
            push( @scopeTextList, @scopeTopicList );
            my %seen = ();

            # make topics unique
            @scopeTextList = sort grep { !$seen{$_}++ } @scopeTextList;
        }
        elsif( @scopeTopicList ) {
            @scopeTextList = @scopeTopicList;
        }

        if( $invertSearch ) {

            # do AND NOT search
            my %seen = ();
            foreach my $topic (@scopeTextList) {
                $seen{$topic} = 1;
            }
            @scopeTextList = ();
            foreach my $topic ( @topicList ) {
                push( @scopeTextList, $topic ) unless ( $seen{$topic} );
            }
        }

        # reduced topic list for next token
        @topicList = @scopeTextList;
    }
    return @topicList;
}

sub _makeTopicPattern {
    my ( $topic ) = @_;
    return '' unless ( $topic );

    # 'Web*, FooBar' ==> ( 'Web*', 'FooBar' ) ==> ( 'Web.*', "FooBar" )
    my @arr =
      map { s/[^\*\_\-\+$TWiki::regex{mixedAlphaNum}]//go; s/\*/\.\*/go; $_ }
      split( /,\s*/, $topic );
    return '' unless ( @arr );

    # ( 'Web.*', 'FooBar' ) ==> "^(Web.*|FooBar)$"
    return '^(' . join( '|', @arr ) . ')$';
}

sub _fixHeadingOffset
{
    my ( $prefix, $level, $offset ) = @_;
    $level += $offset;
    $level = 1 if( $level < 1);
    $level = 6 if( $level > 6);
    return $prefix . '+' x $level;
}

=pod

---++ ObjectMethod searchWeb (...)

Search one or more webs according to the parameters.

If =_callback= is set, that means the caller wants results as
soon as they are ready. =_callback_ should be set to a reference
to a function which takes =_cbdata= as the first parameter and
remaining parameters the same as 'print'.

If =_callback= is set, the result is always undef. Otherwise the
result is a string containing the rendered search results.

If =inline= is set, then the results are *not* decorated with
the search template head and tail blocks.

The function will throw Error::Simple if it encounters any problems with the
syntax of the search string.

Note: If =format= is set, =template= will be ignored.

Note: For legacy, if =regex= is defined, it will force type='regex'

If =type="word"= it will be changed to =type="keyword"= with 
=wordBoundaries=1=. This will be used for searching with scope="text" 
only, because scope="topic" will do a Perl search on topic names.

SMELL: If =template= is defined =bookview= will not work

SMELL: it seems that if you define =_callback= or =inline= then you are
responsible for converting the TML to HTML yourself!

FIXME: =callback= cannot work with format parameter (consider format='| $topic |'

=cut

sub searchWeb {
    my $this = shift;
    my %params        = @_;
    my $callback      = $params{_callback};
    my $cbdata        = $params{_cbdata};
    my $baseTopic     = $params{basetopic} || $this->{session}->{topicName};
    my $baseWeb       = $params{baseweb} || $this->{session}->{webName};
    my $doBookView    = TWiki::isTrue( $params{bookview} );
    my $caseSensitive = TWiki::isTrue( $params{casesensitive} );
    my $excludeTopic  = $params{excludetopic} || '';
    my $doExpandVars  = TWiki::isTrue( $params{expandvariables} );
    my $format        = $params{format} || '';
    my $header        = $params{header};
    my $headingoffset = $params{headingoffset} || 0;
    $headingoffset    =~ s/.*?([-+]?[0-9]).*/$1/ || 0;
    my $footer        = $params{footer};
    my $default       = $params{default};
    my $inline        = $params{inline};
    my $limit         = $params{limit} || '';
    my $start         = defined($params{start}) ? int($params{start}) : '';
    my $doMultiple    = TWiki::isTrue( $params{multiple} );
    my $nonoise       = TWiki::isTrue( $params{nonoise} );
    my $noEmpty       = TWiki::isTrue( $params{noempty}, $nonoise );

    # Note: a defined header overrides noheader
    my $noHeader =
      !defined( $header )
      && TWiki::isTrue( $params{noheader}, $nonoise )
      # Note: This is done for Cairo compatibility
      || ( !$header && $format && $inline );

   # Note: a defined footer overrides nofooter
    my $noFooter =
      !defined( $footer )
      && TWiki::isTrue( $params{nofooter}, $nonoise )
      # Note: This is done for Cairo compatibility
      || ( !$footer && $format && $inline );


    my $noSearch       = TWiki::isTrue( $params{nosearch},  $nonoise );
    my $noSummary      = TWiki::isTrue( $params{nosummary}, $nonoise );
    my $zeroResults    = 1 - TWiki::isTrue( ( $params{zeroresults} || 'on' ), $nonoise );
    my $noTotal        = TWiki::isTrue( $params{nototal}, $nonoise );
    my $newLine        = $params{newline} || '';
    my $sortOrder      = $params{sort} || $params{order} || '';
    my $revSort        = $params{reverse} || '';
    my $scope          = $params{scope} || '';
    my $searchString   = $params{search} || '';
    my $separator      = $params{separator};
    my $template       = $params{template} || '';
    my $topic          = $params{topic} || '';
    my $type           = $params{type} || '';

    my $wordBoundaries = 0;
    if ( $type eq 'word' ) {
        # 'word' is exactly the same as 'keyword', except we will be searching
        # with word boundaries
        $type = 'keyword';
        $wordBoundaries = 1;
    }

    my $webName        = $params{web} || '';
    my $date           = $params{date} || '';
    my $createDate     = $params{createdate} || '';
    my $recurse        = $params{'recurse'} || '';
    my $finalTerm      = $inline ? ( $params{nofinalnewline} || 0 ) : 0;
    my $users          = $this->{session}->{users};

    $baseWeb =~ s/\./\//go;

    my $session  = $this->{session};
    my $renderer = $session->renderer;

    # Limit search results
    if ( $limit =~ /(^\d+$)/o ) {

        # only digits, all else is the same as
        # an empty string.  "+10" won't work.
        $limit = $1;
    }
    else {

        # change 'all' to 0, then to big number
        $limit = 0;
    }
    $limit = 32000 unless( $limit );

    # Limit DoD attack, Item6784: DoS on bin/search whith an asterisk wildcard 
    $limit = 64 if( $doBookView && $limit > 64 );

    $type = 'regex' if( $params{regex} );

    my $mixedAlpha = $TWiki::regex{mixedAlpha};
    if( defined($separator) ) {
        $separator =~ s/\$br/<br \/>/gos;
        $separator =~ s/\$n\(\)/\n/gos;    # expand "$n()" to new line
        $separator =~ s/\$n([^$mixedAlpha]|$)/\n$1/gos;
    }
    if( $newLine ) {
        $newLine =~ s/\$br/<br \/>/gos;
        $newLine =~ s/\$n\(\)/\n/gos;      # expand "$n()" to new line
        $newLine =~ s/\$n([^$mixedAlpha]|$)/\n$1/gos;
    }

    my $searchResult = '';
    my $homeWeb      = $session->{webName};
    my $homeTopic    = $TWiki::cfg{HomeTopicName};
    my $store        = $session->{store};

    my %excludeWeb;
    my @tmpWebs;

    # A value of 'all' or 'on' by itself gets all webs,
    # otherwise ignored (unless there is a web called 'All'.)
    $webName =~ s/\b(all|on)\b//ig if ( $TWiki::cfg{NoInAllPublicWebs} );
    $webName =~ s/^[,\s]+//; $webName =~ s/[,\s]+$//;
    # all and on are ignored when necessary as per Item7575
    my $searchAllFlag = ( $webName =~ /(^|[\,\s])(all|on)([\,\s]|$)/i );

    if( $webName ) {
        foreach my $web ( split( /[\,\s]+/, $webName ) ) {
            $web =~ s#\.#/#go;

            # the web processing loop filters for valid web names,
            # so don't do it here.
            if( $web =~ s/^-// ) {
                $excludeWeb{$web} = 1;
            }
            else {
                push( @tmpWebs, $web );
                if ( TWiki::isTrue( $recurse ) || $web =~ /^(all|on)$/i ) {
                    my $webarg = ( $web =~ /^(all|on)$/i ) ? undef: $web;
                    push( @tmpWebs, $store->getListOfWebs( 'user,allowed', $webarg ) );
                }
            }
        }

    }
    else {

        # default to current web
        push( @tmpWebs, $session->{webName} );
        if ( TWiki::isTrue( $recurse ) ) {
            push( @tmpWebs,
                $store->getListOfWebs( 'user,allowed', $session->{webName} ) );
        }
    }

    my @webs;
    foreach my $web ( @tmpWebs ) {
        push( @webs, $web ) unless $excludeWeb{$web};
        $excludeWeb{$web} = 1;
    }

    # E.g. "Bug*, *Patch" ==> "^(Bug.*|.*Patch)$"
    $topic = _makeTopicPattern( $topic );

    # E.g. "Web*, FooBar" ==> "^(Web.*|FooBar)$"
    $excludeTopic = _makeTopicPattern( $excludeTopic );

    my $output = '';
    my $tmpl   = '';

    $searchString =~ s/$TWiki::percentSubstitute/%/go; # Item7847
    my $originalSearch = $searchString;
    my $spacedTopic;

    if( $format ) {
        $template = 'searchformat';
    }
    elsif( $template ) {

        # template definition overrides book and rename views
    }
    elsif( $doBookView ) {
        $template = 'searchbookview';
    }
    else {
        $template = 'search';
    }
    $tmpl = $session->templates->readTemplate( $template );

    # SMELL: the only META tags in a template will be METASEARCH
    # Why the heck are they being filtered????
    $tmpl =~ s/\%META\{.*?}\%//go;    # remove %META{'parent'}%

    # Split template into 5 sections
    my ( $tmplHead, $tmplSearch, $tmplTable, $tmplNumber, $tmplTail ) =
      split( /%SPLIT%/, $tmpl );

    # Invalid template?
    unless( $tmplTail ) {
        my $mess =
            CGI::h1( 'TWiki Installation Error' )
          . 'Incorrect format of '
          . $template
          . ' template (missing sections? There should be 4 %SPLIT% tags)';
        if ( defined $callback ) {
            &$callback( $cbdata, $mess );
            return undef;
        }
        else {
            return $mess;
        }
    }

    # Expand tags in template sections
    $tmplSearch = $session->handleCommonTags( $tmplSearch, $homeWeb, $homeTopic );
    $tmplNumber = $session->handleCommonTags( $tmplNumber, $homeWeb, $homeTopic );

    # If not inline search, also expand tags in head and tail sections
    unless( $inline ) {
        $tmplHead = $session->handleCommonTags( $tmplHead, $homeWeb, $homeTopic );

        if ( defined $callback ) {
            $tmplHead = $renderer->getRenderedVersion( $tmplHead, $homeWeb, $homeTopic );
            $tmplHead =~ s|</*nop/*>||goi;    # remove <nop> tags
            &$callback( $cbdata, $tmplHead );
        }
        else {

            # don't getRenderedVersion; this will be done by a single
            # call at the end.
            $searchResult .= $tmplHead;
        }
    }

    # Generate 'Search:' part showing actual search string used
    unless( $noSearch ) {
        my $searchStr = $searchString;
        $searchStr  =~ s/&/&amp;/go; # escape entities
        $searchStr  =~ s/</&lt;/go;  # escape HTML
        $searchStr  =~ s/>/&gt;/go;  # escape HTML
        $searchStr  =~ s/%/&#37;/go; # escape TWiki variables
        $searchStr  =~ s/ /&#32;/go; # escape TWiki text formatting
        $searchStr  =~ s/^\.\*$/Index/go;
        $tmplSearch =~ s/%SEARCHSTRING%/$searchStr/go;
        if( defined $callback ) {
            $tmplSearch =
              $renderer->getRenderedVersion( $tmplSearch, $homeWeb, $homeTopic );
            $tmplSearch =~ s|</*nop/*>||goi;    # remove <nop> tag
            &$callback( $cbdata, $tmplSearch );
        }
        else {

            # don't getRenderedVersion; will be done later
            $searchResult .= $tmplSearch;
        }
    }

    # Write log entry
    # FIXME: Move log entry further down to log actual webs searched
    if( ( $TWiki::cfg{Log}{search} ) && ( !$inline ) ) {
        my $t = join( ' ', @webs );
        $session->writeLog( 'search', $t, $searchString );
    }

    my $query;
    my @tokens;

    if( $type eq 'query' ) {
        unless( defined( $queryParser ) ) {
            require TWiki::Query::Parser;
            $queryParser = new TWiki::Query::Parser();
        }
        my $error = '';
        try {
            $query = $queryParser->parse( $searchString );
        } catch TWiki::Infix::Error with {
            # Pass the error on to the caller
            throw Error::Simple( shift->stringify() );
        };
        return $error unless $query;
    } else {
        # Split the search string into tokens depending on type of search -
        # each token is ANDed together by actual search
        @tokens = _tokensFromSearchString( $this, $searchString, $type );
        return '' unless scalar( @tokens );
    }

    # Loop through webs
    my $isAdmin = $session->{users}->isAdmin( $session->{user} );
    my $ttopics = 0;
    my $prefs = $session->{prefs};
    foreach my $web ( @webs ) {
        $web =~ s/$TWiki::cfg{NameFilter}//go;
        $web = TWiki::Sandbox::untaintUnchecked( $web );

        next unless $store->webExists( $web );    # can't process what ain't thar

        my $thisWebNoSearchAll = $prefs->getWebPreferencesValue( 'NOSEARCHALL', $web ) || '';

        # make sure we can report this web on an 'all' search
        # DON'T filter out unless it's part of an 'all' search.
        next if( $searchAllFlag &&
                 !$isAdmin &&
                 ( $thisWebNoSearchAll =~ /on/i || $web =~ /^[\.\_]/ ) &&
                 $web ne $session->{webName}
               );

        my $options = {
            caseSensitive  => $caseSensitive,
            wordBoundaries => $wordBoundaries,
        };

        # Run the search on topics in this web
        my @topicList = _getTopicList( $this, $web, $topic, $options );

        # exclude topics, Codev.ExcludeWebTopicsFromSearch
        if( $caseSensitive && $excludeTopic ) {
            @topicList = grep( !/$excludeTopic/, @topicList );
        }
        elsif( $excludeTopic ) {
            @topicList = grep( !/$excludeTopic/i, @topicList );
        }
        next if( $noEmpty && !@topicList );    # Nothing to show for this web

        if( $type eq 'query' ) {
            @topicList = _queryTopics( $this, $web, $query, @topicList );
        } else {
            @topicList = _searchTopics( $this, $web, $scope, $type, $options, \@tokens, @topicList );
        }

        my $topicInfo = {};

        # sort the topic list by date, author or topic name, and cache the
        # info extracted to do the sorting
        if ( $sortOrder eq 'modified' ) {

            # For performance:
            #   * sort by approx time (to get a rough list)
            #   * shorten list to the limit + some slack
            #   * sort by rev date on shortened list to get the accurate list
            # SMELL: Ciaro had efficient two stage handling of modified sort.
            # SMELL: In Dakar this seems to be pointless since latest rev
            # time is taken from topic instead of dir list.
            my @saveShortened;
            my $slack = 10;
            if( $limit + 2 * $slack < scalar(@topicList) ) {

                # sort by approx latest rev time
                my @tmpList =
                  map  { $_->[1] }
                  sort { $a->[0] <=> $b->[0] }
                  map  { [ $store->getTopicLatestRevTime( $web, $_ ), $_ ] }
                  @topicList;

                @tmpList = reverse( @tmpList ) if( TWiki::isTrue( $revSort ) );

                # then shorten list and build the hashes for date and author
                my $idx = $limit + $slack;
                @topicList = @tmpList[0 .. $idx - 1];
                @saveShortened = @tmpList[$idx .. $#tmpList];
                    # removed elements are saved for later use
            }

            # sort topics and store topic info in $topicInfo
            _sortTopics( $this, $topicInfo, $web, \@topicList, $sortOrder, $revSort );
            if ( $start ne '' && @saveShortened ) {
                # for pagination, which is indicated by the presense of the
                # =start= parameter, the removed elements for optimization are
                # put back
                push(@topicList, @saveShortened);
            }
        }
        elsif ( $sortOrder =~ /\b(created?|editby|formfield\((.*?)\)|parent(\(.*?\))?)([, ]|$)/ ) {
            # sort by topic creation time, author, parent, and store topic info in $topicInfo
            _sortTopics( $this, $topicInfo, $web, \@topicList, $sortOrder, $revSort );
        }
        else {

            # simple sort, see Codev.SchwartzianTransformMisused
            # note no extraction of topic info here, as not needed
            # for the sort. Instead it will be read lazily, later on.
            if( TWiki::isTrue( $revSort ) ) {
                @topicList = sort { $b cmp $a } @topicList;
            }
            else {
                @topicList = sort { $a cmp $b } @topicList;
            }
        }

        if( $date ) {
            require TWiki::Time;
            my @ends       = TWiki::Time::parseInterval( $date );
            my @resultList = ();
            foreach my $topic ( @topicList ) {

                # if date falls out of interval: exclude topic from result
                my $topicdate = $store->getTopicLatestRevTime( $web, $topic );
                push( @resultList, $topic )
                  unless( $topicdate < $ends[0] || $topicdate > $ends[1] );
            }
            @topicList = @resultList;
        }
        if( $createDate ) {
            require TWiki::Time;
            my @ends       = TWiki::Time::parseInterval( $createDate );
            my @resultList = ();
            foreach my $topic ( @topicList ) {

                # if date falls out of interval: exclude topic from result
		my $info = {};
		$this->_getRev1Info( $web, $topic, undef, $info);
                push( @resultList, $topic )
                  unless( $info->{date} < $ends[0] || $info->{date} > $ends[1] );
            }
            @topicList = @resultList;
        }

        # header and footer of $web
        my ( $beforeText, $repeatText, $afterText ) = split( /%REPEAT%/, $tmplTable );
        if ( defined $header ) {
            $beforeText = TWiki::expandStandardEscapes($header);
            $beforeText =~ s/\$web/$web/gos;    # expand name of web
            if( defined($separator) ) {
                $beforeText .= $separator;
            } else {
                $beforeText =~ s/([^\n])$/$1\n/os; # add new line at end if needed
            }
        }

        # output the list of topics in $web
        my $ntopics    = 0; # number of topics in current web
        my $ntopicsExclSkipped = 0;
            # number of topics in current web excluding the ones skipped by
            # the start parameter
        my $tntopics   = @topicList;
        my $nhits      = 0; # number of hits (if multiple=on) in current web
        my $headerDone = $noHeader;
        if ( $start ) {
            if ( $start < @topicList ) {
                $ntopics = $nhits = $start;
                splice(@topicList, 0, $start);
            }
            else {
                $ntopics = $nhits = @topicList;
                @topicList = ();
            }
        }
        foreach my $topic ( @topicList ) {
            my $forceRendering = 0;
            unless ( exists( $topicInfo->{$topic} ) ) {
                # not previously cached
                $topicInfo->{$topic} = _extractTopicInfo( $this, $topicInfo, $web, $topic, 0 );
            }
            my $epochSecs = $topicInfo->{$topic}->{modified};
            require TWiki::Time;
            my $revDate = TWiki::Time::formatTime( $epochSecs );
            my $isoDate =
              TWiki::Time::formatTime( $epochSecs, '$iso', 'gmtime' );

            my $cUID   = $topicInfo->{$topic}->{cUID};
            my $revNum = $topicInfo->{$topic}->{revNum} || 0;

            # Check security
            my $allowView = $topicInfo->{$topic}->{allowView};
            next unless $allowView;

            my ( $meta, $text );

            # Special handling for format='...'
            if( $format ) {
                ( $meta, $text ) = _getTextAndMeta( $this, $topicInfo, $web, $topic );
                if( $headingoffset ) {
                    $text =~ s/^(---*)(\++)/_fixHeadingOffset( $1, length( $2 ), $headingoffset )/gem;
                }
                if( $doExpandVars ) {
                    if( $web eq $baseWeb && $topic eq $baseTopic ) {

                        # primitive way to prevent recursion
                        $text =~ s/%SEARCH/%<nop>SEARCH/g;
                    }
                    $text = $session->handleCommonTags( $text, $web, $topic, $meta );
                }
            }

            my @multipleHitLines = ();
            if( $doMultiple ) {
                my $pattern = $tokens[$#tokens];   # last token in an AND search
                $pattern = quotemeta( $pattern ) if( $type ne 'regex' );
                unless( $text ) {
                    ( $meta, $text ) = _getTextAndMeta( $this, $topicInfo, $web, $topic );
                    if( $headingoffset ) {
                        $text =~ s/^(---*)(\++)/_fixHeadingOffset( $1, length( $2 ), $headingoffset )/gem;
                    }
                }
                if ($caseSensitive) {
                    @multipleHitLines = reverse grep { /$pattern/ } split( /[\n\r]+/, $text );
                }
                else {
                    @multipleHitLines = reverse grep { /$pattern/i } split( /[\n\r]+/, $text );
                }
            }

            $ntopics += 1;
            $ntopicsExclSkipped += 1;
            $ttopics += 1;

            do {    # multiple=on loop

                $nhits += 1;
                my $out = '';

                $text = pop( @multipleHitLines ) if( scalar(@multipleHitLines) );

                my $wikiname = $topicInfo->{$topic}->{editby};
                my $wikiusername = $TWiki::cfg{UsersWebName}.'.'.$wikiname;

                if( $format ) {
                    $out = $format;
                    $out =~ s/\$web/$web/gs;
                    $out =~ s/\$topictitle/$meta->topicTitle()/ges;
                    $out =~ s/\$topic\(([^\)]*)\)/TWiki::Render::breakName( $topic, $1 )/ges;
                    $out =~ s/\$topic/$topic/gs;
                    $out =~ s/\$date/$revDate/gs;
                    $out =~ s/\$isodate/$isoDate/gs;
                    $out =~ s/\$rev/$revNum/gs;
                    $out =~ s/\$wikiusername/$wikiusername/ges;
                    $out =~ s/\$ntopics/$ntopics/gs;
                    $out =~ s/\$tntopics/$tntopics/gs;
                    $out =~ s/\$nwebs/scalar(@webs)/gse;
                    $out =~ s/\$nhits/$nhits/gs;
                    $out =~ s/\$wikiname/$wikiname/ges;
                    
                    my $username = $users->getLoginName( $cUID );
                    $username = 'unknown' unless defined $username;
                    $out =~ s/\$username/$username/ges;
                    
                    my $r1info = {};
                    $out =~ s/\$createdate/_getRev1Info(
                            $this, $web, $topic, 'date', $r1info )/ges;
                    $out =~ s/\$createusername/_getRev1Info(
                            $this, $web, $topic, 'username', $r1info )/ges;
                    $out =~ s/\$createwikiname/_getRev1Info(
                            $this, $web, $topic, 'wikiname', $r1info )/ges;
                    $out =~ s/\$createwikiusername/_getRev1Info(
                            $this, $web, $topic, 'wikiusername', $r1info )/ges;

                    if ( $out =~ m/\$text(?:\(([^\)]*)\))?/ ) {
                        my $textArgs = $1;
                        $textArgs = '' unless ( defined($textArgs) );
                        unless( $text || $doMultiple ) {
                            ( $meta, $text ) = _getTextAndMeta( $this, $topicInfo, $web, $topic );
                            if( $headingoffset ) {
                                $text =~ s/^(---*)(\++)/_fixHeadingOffset( $1, length( $2 ), $headingoffset )/gem;
                            }
                        }
                        if ( $topic eq $session->{topicName} ) {
                            # defuse SEARCH in current topic to prevent loop
                            $text =~ s/%SEARCH\{.*?}%/SEARCH{...}/go;
                        }
                        my $textInserted;
                        if ( $textArgs =~ /\bencode:(\w+)/ ) {
                            $textInserted = TWiki::_encode($1, $text);
                        }
                        else {
                            $textInserted = $text;
                        }
                        $out =~ s/\$text(?:\(([^\)]*)\))?/$textInserted/gos;
                        $forceRendering = 1 unless( $doMultiple );
                    }
                }
                else {
                    $out = $repeatText;
                }
                $out =~ s/%WEB%/$web/go;
                $out =~ s/%TOPICNAME%/$topic/go;
                $out =~ s/%TIME%/$revDate/o;

                my $srev = 'r' . $revNum;
                if( $revNum eq '0' || $revNum eq '1' ) {
                    $srev = CGI::span( { class => 'twikiNew' }, ( $this->{session}->i18n->maketext('NEW') ) );
                }
                $out =~ s/%REVISION%/$srev/o;
                $out =~ s/%AUTHOR%/[[$wikiusername][$wikiname]]/;

                if( $doBookView ) {

                    # BookView
                    ( $meta, $text ) = _getTextAndMeta( $this, $topicInfo, $web, $topic )
                      unless $text;
                    if( $web eq $baseWeb && $topic eq $baseTopic ) {

                        # primitive way to prevent recursion
                        $text =~ s/%SEARCH/%<nop>SEARCH/g;
                    }
                    $text = $session->handleCommonTags( $text, $web, $topic, $meta );
                    $text = $session->renderer->getRenderedVersion( $text, $web, $topic );

                    # FIXME: What about meta data rendering?
                    $out =~ s/%TEXTHEAD%/$text/go;

                } elsif( $format ) {
                    $out =~
s/\$summary(?:\(([^\)]*)\))?/$renderer->makeTopicSummary( $text, $topic, $web, $1 )/ges;
                    $out =~
s/\$changes(?:\(([^\)]*)\))?/$renderer->summariseChanges($cUID,$web,$topic,$1,$revNum)/ges;
                    $out =~
s/\$formfield\(\s*([^\)]*)\s*\)/displayFormField( $meta, $1 )/ges;
                    $out =~
s/\$parent\(([^\)]*)\)/TWiki::Render::breakName( $meta->getParent(), $1 )/ges;
                    # undocumented $breadcrumb returning list with "parents, topic",
                    # where parents is parent breadcrumb (only if sort by parent(...))
                    $out =~ s/\$breadcrumb/
                        if( $topicInfo->{$topic}{parent} ) {
                            $topicInfo->{$topic}{parent};
                        } else {
                            my $p = $meta->getParent();
                            ( $p ? "$p, $topic" : $topic );
                        }
                      /ges;
                    $out =~ s/\$parent/$meta->getParent()/ges;
                    $out =~ s/\$formname/$meta->getFormName()/ges;
                    $out =~ s/\$count\((.*?\s*\.\*)\)/_countPattern( $text, $1 )/ges;
                    $out =~ s/\$query\(\s*([^\)]*)\s*\)/formatQuery( $meta, $1 )/ges;

                    # FIXME: Allow all regex characters but escape them
                    # Note: The RE requires a .* at the end of a pattern to avoid false positives
                    # in pattern matching
                    $out =~ s/\$pattern\((.*?\s*\.\*)\s*(?:,\s*([^\)]*))?\)/getTextPattern( $text, $1, $2 )/ges;
                    $out =~ s/\r?\n/$newLine/gos if( $newLine );
                    if( defined($separator) ) {
                        $out .= $separator;
                    } else {
                        # add new line at end if needed
                        $out =~ s/([^\n])$/$1\n/s;
                    }
                    $out = TWiki::expandStandardEscapes( $out );

                } elsif( $noSummary ) {
                    $out =~ s/%TEXTHEAD%//go;
                    $out =~ s/&nbsp;//go;

                } else {
                    # regular search view
                    ( $meta, $text ) = _getTextAndMeta( $this, $topicInfo, $web, $topic )
                      unless $text;
                    $text = $renderer->makeTopicSummary( $text, $topic, $web );
                    $out =~ s/%TEXTHEAD%/$text/go;
                }

                # lazy output of header (only if needed for the first time)
                unless( $headerDone ) {
                    $headerDone = 1;
                    my $prefs = $session->{prefs};
                    my $thisWebBGColor = $prefs->getWebPreferencesValue( 'WEBBGCOLOR', $web ) || '#FF00FF';
                    $beforeText =~ s/%WEBBGCOLOR%/$thisWebBGColor/go;
                    $beforeText =~ s/%WEB%/$web/go;
                    $beforeText =~ s/\$ntopics/0/gs;
                    $beforeText =~ s/\$tntopics/0/gs;
                    $beforeText =~ s/\$nwebs/scalar(@webs)/gse;
                    $beforeText =~ s/\$nhits/0/gs;
                    $beforeText = $session->handleCommonTags( $beforeText, $web, $topic );
                    if( defined $callback ) {
                        $beforeText = $renderer->getRenderedVersion( $beforeText, $web, $topic );
                        $beforeText =~ s|</*nop/*>||goi;    # remove <nop> tag
                        &$callback( $cbdata, $beforeText );
                    }
                    else {
                        $searchResult .= $beforeText;
                    }
                }

                #don't expand if a format is specified - it breaks tables and stuff
                unless( $format ) {
                    $out = $renderer->getRenderedVersion( $out, $web, $topic );
                }

                # output topic (or line if multiple=on)
                if( defined $callback ) {
                    $out =~ s|</*nop/*>||goi;    # remove <nop> tag
                    &$callback( $cbdata, $out );
                }
                else {
                    $searchResult .= $out;
                }

            } while( @multipleHitLines );    # multiple=on loop

            # delete topic info to clear any cached data
            undef $topicInfo->{$topic};

            last if( $ntopicsExclSkipped >= $limit );

        } # end topic loop

        # output footer only if hits in web, else output default if defined
        if( $ntopics || $default ) {

            $afterText = $footer if( defined $footer );
            $afterText = $default if( ! $ntopics && $default );
            $afterText = TWiki::expandStandardEscapes( $afterText );
            $afterText =~ s/\$web/$web/gos;    # expand name of web
            $afterText =~ s/\$ntopics/$ntopics/gs;
            $afterText =~ s/\$tntopics/$tntopics/gs;
            $afterText =~ s/\$nwebs/scalar(@webs)/gse;
            $afterText =~ s/\$nhits/$nhits/gs;
            $afterText = $session->handleCommonTags( $afterText, $web, $homeTopic );
            if( $afterText && $afterText ne '' ) {
                if( defined( $separator ) ) {
                    $afterText .= $separator;
                } else {
                    $afterText =~ s/([^\n])$/$1\n/os; # add new line at end if needed
                }

                if( defined $callback ) {
                    $afterText = $renderer->getRenderedVersion( $afterText, $web, $homeTopic );
                    $afterText =~ s|</*nop/*>||goi;    # remove <nop> tag
                    &$callback( $cbdata, $afterText );
                } else {
                    $searchResult .= $afterText;
                }
            }
        }

        # output number of topics (only if hits in web or if
        # only searching one web)
        if( $ntopics || scalar(@webs) < 2 ) {
            unless( $noTotal ) {
                my $thisNumber = $tmplNumber;
                if ( $start eq '' ) {
                    $thisNumber =~ s/%NTOPICS%/$ntopics/go;
                }
                else {
                    $thisNumber =~ s/%NTOPICS%/$tntopics/go;
                }
                if( defined $callback ) {
                    $thisNumber = $renderer->getRenderedVersion( $thisNumber, $web, $homeTopic );
                    $thisNumber =~ s|</*nop/*>||goi;    # remove <nop> tag
                    &$callback( $cbdata, $thisNumber );
                }
                else {
                    $searchResult .= $thisNumber;
                }
            }
        }
    }    # end of: foreach my $web ( @webs )
    return '' if( $ttopics == 0 && $zeroResults );

    if( $format && !$finalTerm ) {
        if( $separator ) {
            $separator = quotemeta( $separator );
            $searchResult =~ s/$separator$//s;    # remove separator at end
        }
        else {
            $searchResult =~ s/\n$//os;           # remove trailing new line
        }
    }

    unless( $inline ) {
        $tmplTail = $session->handleCommonTags( $tmplTail, $homeWeb, $homeTopic );

        if ( defined $callback ) {
            $tmplTail =
              $renderer->getRenderedVersion( $tmplTail, $homeWeb, $homeTopic );
            $tmplTail =~ s|</*nop/*>||goi;        # remove <nop> tag
            &$callback( $cbdata, $tmplTail );
        }
        else {
            $searchResult .= $tmplTail;
        }
    }

    return undef         if( defined $callback );
    return $searchResult if( $inline );

    $searchResult = $session->handleCommonTags( $searchResult, $homeWeb, $homeTopic );
    $searchResult = $renderer->getRenderedVersion( $searchResult, $homeWeb, $homeTopic );

    return $searchResult;
}

# RE for a full-spec floating-point number
my $number = qr/^[-+]?[0-9]+(\.[0-9]*)?([Ee][-+]?[0-9]+)?$/s;

# extract topic info required for sorting and sort.
sub _sortTopics {
    my ( $this, $topicInfo, $web, $topics, $sortfield, $revSort ) = @_;

    my $users = $this->{session}->{users};
    my $topicParents = {}; # initialize parent hash, used to optimize sorting by parents
    foreach my $topic ( @$topics ) {
        $topicInfo->{$topic} = _extractTopicInfo( $this, $topicInfo, $web, $topic,
                                                  $sortfield, $topicParents );
    }

    $sortfield =~ s/\bformfield\((.*?)\)/$1/g;
    $sortfield =~ s/\bparent\(.*?\)/parent/g;
    $sortfield =~ s/^ +//;
    $sortfield =~ s/ +$//;
    my @sortTokens =
      reverse
      split( / *, */, $sortfield );
    my @reverseTokens =
      reverse
      map { TWiki::isTrue( $_ ) }
      split( / *, */, $revSort );

    # fix reverse tokens to same size like sort tokens
    my $diff = $#reverseTokens - $#sortTokens;
    if( $diff > 0 ) {
       splice( @reverseTokens, 0, $diff ); # cut front to make same size
    } elsif( $diff < 0 ) {
        # repeat first state at front to make same size
       unshift( @reverseTokens, ($reverseTokens[0]) x abs( $diff ) );
    }
    if( $#reverseTokens > 0 ) {
        # xor reverse to counteract repeated reverse
        my $o = $reverseTokens[$#reverseTokens];
        for ( my $i = $#reverseTokens-1; $i >= 0; $i-- ) {
            my $n = ( $o xor $reverseTokens[$i] );
            $o = $reverseTokens[$i];
            $reverseTokens[$i] = $n;
        }
    }

    # sort by multiple fields
    my $i = 0;
    foreach my $sortToken ( @sortTokens ) {
        @$topics =
          map { $_->[1] }
          sort {
              $_ = 0;
              if( defined $a->[0] && defined $b->[0] ) {
                  if( $a->[0] =~ /$number/o && $b->[0] =~ /$number/o ) {
                      # when sorting numbers do it largest first; this is just because
                      # this is what date comparisons need.
                      $_ = $a->[0] <=> $b->[0];
                  } else {
                      $_ = $a->[0] cmp $b->[0];
                  }
              }
              $_;
          }
          map { [ $topicInfo->{$_}->{$sortToken}, $_ ] }
          @$topics;
        @$topics = reverse @$topics if( $reverseTokens[$i++] );
    }

    return $topicInfo;
}

# extract topic info
sub _extractTopicInfo {
    my ( $this, $topicInfo, $web, $topic, $sortfield, $topicParents ) = @_;
    my $info    = {};
    my $session = $this->{session};
    my $store   = $session->{store};
    my $users   = $this->{session}->{users};

    my ( $meta, $text ) = _getTextAndMeta( $this, $topicInfo, $web, $topic );

    $info->{text} = $text;
    $info->{meta} = $meta;

    my ( $revdate, $cUID, $revnum ) = $meta->getRevisionInfo();
    $info->{cUID}     = $cUID || 'unknown';
    $info->{editby}   = $users->getWikiName($cUID);
    $info->{modified} = $revdate;
    $info->{revNum}   = $revnum;

    $info->{allowView} =
      $session->security->checkAccessPermission( 'VIEW', $session->{user}, $text, $meta, $topic, $web );

    return $info unless( $sortfield );

    # sort field can have multiple tokens, such as: sort="parent, formfield(Title)"
    if ( $sortfield =~ /\bcreated?\b/ ) {
        ( $info->{created} ) = $meta->getRevisionInfo( 1 );
    }
    if ( $sortfield =~ /\bparent(\(([0-9]+)\))?/ ) {
        # sort by parent breadcrumb up to indicated level.
        # for example, sorting on 3 levels is done with string "GrandParent, Parent, Topic"
        my $level = $2 || 1;
        my @parents = ( $topic );
        my $parent = $meta->getParent();
        $parent =~ s/.*\.//; # cut web prefix if present
        while( $level-- >= 1 && $parent ) {
            $topicParents->{$topic} = $parent if( $topicParents ); # remember for later use
            push( @parents, $parent );
            if( $level >= 1 ) {
                my $gParent = '';
                if( $topicParents && $topicParents->{$parent} ) {
                    $gParent = $topicParents->{$parent};
                } elsif( $store->topicExists( $web, $parent ) ) {
                    my ( $gpMeta ) = _getTextAndMeta( $this, $topicInfo, $web, $parent );
                    $gParent = $gpMeta->getParent();
                    $gParent =~ s/.*\.//; # cut web prefix if present
                }
                $gParent = '' if( $gParent eq $parent ); # stop if topic points to itself as parent
                $topic = $parent;
                $parent = $gParent || '';
            }
        };
        ( $info->{parent} ) = join( ', ', reverse @parents );
    }
    # handle possily multiple formfield(Name)
    $sortfield =~ s/\bformfield\((.*?)\)/_setFormFieldInfo( $info, $meta, $1 )/ge;

    return $info;
}

# set formfield info
sub _setFormFieldInfo {
    my ( $info, $meta, $formfield ) = @_;
    unless ( defined( $info->{$formfield} ) ) {
        $info->{$formfield} = displayFormField( $meta, $formfield, 1 );
    }
}

# pre-compile regex
my $reATTACHURL     = qr/%ATTACHURL%/;
my $reATTACHURLPATH = qr/%ATTACHURLPATH%/;

# get the text and meta for a topic
sub _getTextAndMeta {
    my ( $this, $topicInfo, $web, $topic ) = @_;
    my ( $meta, $text );
    my $store = $this->{session}->{store};

    # read from cache if it's there
    if( $topicInfo ) {
        $text = $topicInfo->{$topic}->{text};
        $meta = $topicInfo->{$topic}->{meta};
    }

    unless( defined $text ) {
        ( $meta, $text ) = $store->readTopic( undef, $web, $topic, undef );
        $text =~ s/%WEB%/$web/gos;
        $text =~ s/%TOPIC%/$topic/gos;
        if ( $text =~ $reATTACHURL ) {
            my $attachUrl = $this->{session}->getPubUrl(1, $web, $topic);
            $text =~ s/$reATTACHURL/$attachUrl/gos;
        }
        if ( $text =~ $reATTACHURLPATH ) {
            my $attachUrlPath = $this->{session}->getPubUrl(0, $web, $topic);
            $text =~ s/$reATTACHURLPATH/$attachUrlPath/gos;
        }
    }
    return( $meta, $text );
}

=pod

---++ StaticMethod formatQuery( $meta, $query ) -> $text

=cut

sub formatQuery {
    my( $meta, $queryString ) = @_;

    my $encodeType = '';
    if ( $queryString =~ s/\s*,\s*encode:(\w+)\s*// ) {
        $encodeType = $1;
    }
    my $strQuote = '';
    if ( $queryString =~ s/\s*,\s*quote:([^\s\)]+)\s*// ) {
        $strQuote = $1;
    }
    unless( defined( $queryParser ) ) {
        require TWiki::Query::Parser;
        $queryParser = new TWiki::Query::Parser();
    }
    my $error = '';
    my $query;
    try {
        $query = $queryParser->parse( $queryString );
    } catch TWiki::Infix::Error with {
        return "\$query() format parse error " . shift->stringify();
    };
    return "\$query() format error $error" unless $query;

    my $result = $query->evaluate( tom => $meta, data => $meta );
    return $encodeType ? TWiki::_encode( $encodeType,
                                         _queryResultToString( $result, $strQuote ) )
                       : _queryResultToString( $result, $strQuote );
}

sub _queryResultToString {
    my( $a, $strQuote ) = @_;
    return 'undef' unless( defined $a );
    if( ref( $a ) eq 'ARRAY' ) {
        return join(', ', map { _queryResultToString( $_, $strQuote ) } @$a );
    } elsif( UNIVERSAL::isa( $a, 'TWiki::Meta' ) ) {
        return $a->stringify();
    } elsif( ref( $a ) eq 'HASH' ) {
        return '{'.join(', ', map { "$_=>"._queryResultToString($a->{$_}, $strQuote) } keys %$a).'}'
    } else {
        return "$strQuote$a$strQuote";
    }
}

=pod

---++ StaticMethod displayFormField( $meta, $args ) -> $text

Parse the arguments to a $formfield specification and extract
the relevant formfield from the given meta data.

   * =args= string containing name of form field

In addition to the name of a field =args= can be appended with a commas
followed by a string format (\d+)([,\s*]\.\.\.)?). This supports the formatted
search function $formfield and is used to shorten the returned string or a 
hyphenated string.

=cut

sub displayFormField {
    my( $meta, $args, $skipRendering ) = @_;

    my $render = '';
    if( $args =~ s/\s*,\s*render:(\w+)// ) {
        $render = $1;
    }
    my $attrs = { protectdollar => 1, showhidden => 1 };
    if( $args =~ s/\s*,\s*encode:(\w+)// ) {
        $attrs->{encode} = $1;
    }
    my $name = $args;
    if( $name =~ /\,/ ) {
        my @params = split( /\,\s*/, $name, 2 );
        if( @params > 1 ) {
            $name = $params[0] || '';
            $attrs->{break} = $params[1] || 1;
        }
    }
    return '' unless $name;

    # Item7616: Reverting partly to TWiki-5.1's Item6082 fix for performance.
    # $meta->renderFormFieldForDisplay is slow, doubling the time of a SEARCH
    # with formfields. Let's avoid it where feasible, e.g. avoid in sorting and
    # if no formatting needed.
    if( $skipRendering || ! ( $render eq 'display' || $attrs->{break} || $attrs->{encode} ) ) {
        my $form =  $meta->get( 'FORM' );
        my $fields;
        if( $form ) {
            $fields = $meta->get( 'FIELD', $name );
            unless( $fields ) {
                # not a valid field name, maybe it's a title.
                require TWiki::Form;
                $fields = $meta->get( 'FIELD', TWiki::Form::fieldTitle2FieldName( $name ) );
            }
        }
        if( ref( $fields ) eq 'HASH' ){
            # fix for Item6167, this line was not added for fixing Item6082
            my $val = $fields->{value};
            $val =~ s/\$(n|nop|quot|percnt|dollar)/\$<nop>$1/g;
            return $val;
        }
        return ''; # form field not found
    }

    return $meta->renderFormFieldForDisplay( $name, '$value', $attrs );
}

# Returns the topic revision info of the base version,
# attributes are 'date', 'username', 'wikiname',
# 'wikiusername'. Revision info is cached in the search
# object for speed.
sub _getRev1Info {
    my ( $this, $web, $topic, $attr, $info ) = @_;
    my $key   = $web . '.' . $topic;
    my $store = $this->{session}->{store};
    my $users = $this->{session}->{users};

    unless ( $info->{webTopic} && $info->{webTopic} eq $key ) {
        require TWiki::Meta;
        my $meta = new TWiki::Meta( $this->{session}, $web, $topic );
        my ( $d, $u ) = $meta->getRevisionInfo( 1 );
        $info->{date}     = $d;
        $info->{user}     = $u;
        $info->{webTopic} = $key;
    }
    if( $attr eq 'username' ) {
        return $users->getLoginName( $info->{user} );
    }
    if( $attr eq 'wikiname' ) {
        return $users->getWikiName( $info->{user} );
    }
    if( $attr eq 'wikiusername' ) {
        return $users->webDotWikiName( $info->{user} );
    }
    if( $attr eq 'date' ) {
        require TWiki::Time;
        return TWiki::Time::formatTime( $info->{date} );
    }

    return 1;
}

# With the same argument as $pattern, returns a number which is the count of
# occurences of the pattern argument.
sub _countPattern {
    my ( $theText, $thePattern ) = @_;

    $thePattern =~ s/([^\\])([\$\@\%\&\#\'\`\/])/$1\\$2/go;    # escape some special chars
    $thePattern =~ /(.*)/;                                     # untaint
    $thePattern = $1;
    my $OK = 0;
    eval {
        # counting hack, see: http://dev.perl.org/perl6/rfc/110.html
        $OK = () = $theText =~ /$thePattern/g;
    };

    return $OK;
}

1;
