# Plugin for TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (c) 2006-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (c) 2006 Fred Morris, m3047-twiki@inwa.net
# Copyright (c) 2007 Crawford Currie, http://c-dot.co.uk
# Copyright (c) 2007 Sven Dowideit, SvenDowideit@DistributedINFORMATION.com
# Copyright (c) 2007 Arthur Clemens, arthur@visiblearea.com
# Copyright (c) 2006-2018 TWiki Contributor
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# =========================
#
# This Plugin implements tags in TWiki.

# =========================
package TWiki::Plugins::TagMePlugin;

use strict;

# =========================
our $VERSION    = '$Rev: 30482 (2018-07-16) $';
our $RELEASE    = '2018-07-05';

# =========================
our $pluginName = 'TagMePlugin';    # Name of this Plugin
our $initialized = 0;
our $lineRegex   = "^0*([0-9]+), ([^,]+), (.*)";
our $tagChangeRequestTopic = 'TagMeChangeRequests';
our $tagChangeRequestLink = "[[$tagChangeRequestTopic][Tag change requests]]";
our $web;
our $topic;
our $user;
our $installWeb;
our $debug;
our $workAreaDir;
our $attachUrl;
our $logAction;
our $tagLinkFormat;
our $tagQueryFormat;
our $alphaNum;
our $doneHeader;
our $normalizeTagInput;
our $topicsRegex;
our $action;
our $style;
our $label;
our $header;
our $footer;
our $button;
our $NO_PREFS_IN_TOPIC = 1;
  # to avoid inefficiency of parsing the plug-in document for configuration
our $SHORTDESCRIPTION = 'Tag wiki content collectively or authoritatively to find content by keywords';
our $manipWeb;
our $userAgnostic;
our $canTag;
our $canChange;
our $inactiveSite;
our $showControl;
our $maxTagLen;


# =========================
BEGIN {
    # I18N initialization
    if ( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

# =========================
sub initPlugin {
    ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $TWiki::Plugins::VERSION < 1.024 ) {
        TWiki::Func::writeWarning(
            "Version mismatch between $pluginName and Plugins.pm");
        return 0;
    }

    # Get plugin debug flag
    $debug = $TWiki::cfg{TagMePlugin}{Debug};
    
    TWiki::Func::registerTagHandler( 'TAGME',
				     \&_handleTagMe );
    TWiki::Func::registerTagHandler( 'TAGMEPLUGIN_USER_AGNOSTIC',
				     \&_TAGMEPLUGIN_USER_AGNOSTIC );

    _writeDebug("initPlugin( $web.$topic ) is OK");
    $initialized = 0;
    $doneHeader  = 0;
    $canTag = undef;
    $canChange = undef;
    $userAgnostic = undef;

    return 1;
}

# =========================
sub _isTrue {
    if ( TWiki::Func->can('isTrue') ) {
        return TWiki::Func::isTrue(@_);
    }
    else {
        # last resort
        return TWiki::isTrue(@_);
    }
}

# =========================
sub _manipWeb {
    my $w = shift;
    if ( $TWiki::cfg{UserSubwebs}{Enabled} &&
         $TWiki::cfg{UsersWebName} &&
	 $w =~ m|^(${TWiki::cfg{UsersWebName}}[./][^./]+)|
    ) {
	$w = $1;
	$w =~ s:\.:/:g;
	return $w;
    }
    else {
	$w =~ s:[./].*$::;
	return $w;
    }
}

# =========================
sub _initialize {
    return if ($initialized);

    # Initialization
    my $ctx = TWiki::Func::getContext();
    $inactiveSite = ref $ctx && ( $ctx->{inactive} || $ctx->{content_slave} );
    $workAreaDir = TWiki::Func::getWorkArea($pluginName);
    $attachUrl = TWiki::Func::getPubUrlPath($installWeb) . "/$installWeb/$pluginName";
    $logAction = $TWiki::cfg{TagMePlugin}{LogAction} || '';
    $normalizeTagInput = $TWiki::cfg{TagMePlugin}{NormalizeTagInput} || 0;
    if ( $TWiki::cfg{TagMePlugin}{SplitSpace} ) {
	$manipWeb = _manipWeb($web);
        # Only if each top level web has its own tag namespace,
        # it can choose user conscious tagging or user agnostic tagging.
        # If there is only one tag namespace, user conscious or user agnostic
        # needs to be a global parameter.
        $userAgnostic = TWiki::Func::getPreferencesValue(
            'TAGMEPLUGIN_USER_AGNOSTIC_TAGGING', $web);
    }
    else {
	$manipWeb = '%SYSTEMWEB%';
    }
    if ( !defined($userAgnostic) ) {
        $userAgnostic = $TWiki::cfg{TagMePlugin}{UserAgnostic};
    }
    $userAgnostic = _isTrue($userAgnostic);
    $tagChangeRequestLink =
	"[[$manipWeb.$tagChangeRequestTopic][Tag change requests]]";
    $tagLinkFormat =
        '<a rel="nofollow" href="%SCRIPTURL{view}%/'
      . $manipWeb
      . '/TagMeSearch?tag=$tag;by=$by">$tag</a>';
    $tagQueryFormat =
'<table class="tagmeResultsTable tagmeResultsTableHeader" cellpadding="0" cellspacing="0" border="0"><tr>$n'
      . '<td class="tagmeTopicTd"> <b>[[$web.$topic][<nop>$topic]]</b> '
      . '<span class="tagmeTopicTdWeb">in <nop>$web web</span></td>$n'
      . '<td class="tagmeDateTd">'
      . '[[%SCRIPTURL{rdiff}%/$web/$topic][$date]] - r$rev </td>$n'
      . '<td class="tagmeAuthorTd"> $wikiusername </td>$n'
      . '</tr></table>$n'
      . '<p class="tagmeResultsDetails">'
      . '<span class="tagmeResultsSummary">$summary</span>%BR% $n'
      . '<span class="tagmeResultsTags">Tags: $taglist</span>' . '</p>';
    $alphaNum = TWiki::Func::getRegularExpression('mixedAlphaNum');

    $maxTagLen =
	TWiki::Func::getPreferencesValue('TAGMEPLUGIN_MAX_TAG_LEN', $web) || 30;
      # by default maximum tag length is 30
    my $lenLimit = $TWiki::cfg{TagMePlugin}{TagLenLimit} || 0;
    if ( $lenLimit && $maxTagLen > $lenLimit ) {
	$maxTagLen = $lenLimit;
    }
      # if $TWiki::cfg{TagMePlugin}{TagLenLimit} is defined, maximum tag length
      # cannot exceed the value

    _addHeader();

    $initialized = 1;
}

# =========================
sub afterRenameHandler {
    my ($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment)
	= @_;
    return if ( $oldAttachment ne '' ); # do nothing for attachment rename
    _writeDebug("afterRenameHandler: $oldWeb.$oldTopic -> $newWeb.$newTopic");
    _initialize();
    renameOrCopyTagInfo("$oldWeb.$oldTopic", "$newWeb.$newTopic", 'rename');
}

# =========================
sub afterSaveHandler {
    ### my ( $text, $topic, $web, $error, $meta, $options ) = @_;
    ###      0      1       2     3       4      5
    ### TWiki::Store::saveStopic needs to be slightly modified to get $_[5]

    return unless ( $_[5] && ref $_[5] && defined $_[5]->{comment} &&
		    $_[5]->{comment} eq 'copy' );
    # this is only for page copy
    my ($newWeb, $newTopic) = ($_[2], $_[1]);
    _writeDebug("copy $web.$topic -> $newWeb.$newTopic");
    _initialize();
    renameOrCopyTagInfo("$web.$topic", "$newWeb.$newTopic", 'copy');
}

# =========================
sub _addHeader {
    return if $doneHeader;

    my $header =
"\n<style type=\"text/css\" media=\"all\">\n\@import url(\"$attachUrl/tagme.css\");\n</style>\n";
    TWiki::Func::addToHEAD( 'TAGMEPLUGIN', $header );
    $doneHeader = 1;
}

# =========================
sub _handleTagMe {
#    my($session, $params, $theTopic, $theWeb) = @_;
    my $attr = $_[1];
    $action = defined($attr->{tpaction}) ? $attr->{tpaction} : '';
    $style = defined($attr->{style}) ? $attr->{style} : '';
    $label = defined($attr->{label}) ? $attr->{label} : '';
    $button = defined($attr->{button}) ? $attr->{button} : '';
    $header = defined($attr->{header}) ? $attr->{header} : '';
    $header =~ s/\$n/\n/go;
    $footer = defined($attr->{footer}) ? $attr->{footer} : '';
    $footer =~ s/\$n/\n/go;
    $showControl = _isTrue($attr->{showcontrol}, 1);
    my $text = '';
    _initialize();

    if ( $action eq 'show' ) {
	$text = _showDefault();
    }
    elsif ( $action eq 'showalltags' ) {
        $text = _showAllTags($attr);
    }
    elsif ( $action eq 'query' ) {
        $text = _queryTag($attr);
    }
    elsif ( $action eq 'newtag' ) {
        $text = _newTag($attr);
    }
    elsif ( $action eq 'newtaginit' ) {
        $text = _modifyTagInit( 'create', $attr );
    }
    elsif ( $action eq 'newtagsandadd' ) {
        $text = _newTagsAndAdd($attr);
    }
    elsif ( $action eq 'autonewadd' ) {
        $text = _newTag($attr, 'silent', 1);
        $text = _addTag($attr) unless $text =~ /twikiAlert/; 
    }
    elsif ( $action eq 'add' ) {
        $text = _addTag($attr);
    }
    elsif ( $action eq 'remove' ) {
        $text = _removeTag($attr);
    }
    elsif ( $action eq 'removeall' ) {
        $text = _removeAllTag($attr);
    }
    elsif ( $action eq 'renametag' ) {
        $text = _renameTag($attr);
    }
    elsif ( $action eq 'renametaginit' ) {
        $text = _modifyTagInit( 'rename', $attr );
    }
    elsif ( $action eq 'deletetag' ) {
        $text = _deleteTag($attr);
    }
    elsif ( $action eq 'deletethetag' ) {
        $text = _deleteTheTag($attr);
    }
    elsif ( $action eq 'deletetaginit' ) {
        $text = _modifyTagInit( 'delete', $attr );
    }
    elsif ( $action eq 'nop' ) {

        # no operation
    }
    elsif ($action) {
        $text = 'Unrecognized action';
    }
    else {
	$text = _showDefault();
    }
    return $text;
}

# =========================
sub _showDefault {
    return '' unless ( TWiki::Func::topicExists( $web, $topic ) );
    
    # overriden by the relevant "show" functions for each style
    if ($style eq 'blog') {
        return _showStyleBlog(@_);
    }

    my %arg = @_;
    my @tagInfo;
    @tagInfo = @{$arg{tagInfo}} if ( $arg{tagInfo} && ref $arg{tagInfo} );
    my $status = $arg{status} || '';

    my $query = TWiki::Func::getCgiQuery();
    my $tagMode = $query->param('tagmode') || '';

    my $webTopic = "$web.$topic";
    @tagInfo = _readTagInfo($webTopic) unless ( scalar(@tagInfo) );
    my $text  = '';
    my $tag   = '';
    my $num   = '';
    my $users = '';
    my $line  = '';
    my %seen  = ();
    foreach (@tagInfo) {

        # Format:  3 digit number of users, tag, comma delimited list of users
        # Example: 004, usability, UserA, UserB, UserC, UserD
        # SMELL: This format is a quick hack for easy sorting, parsing, and
        # for fast rendering
        if (/$lineRegex/o) {
            $num   = $1;
            $tag   = $2;
            $users = $3;
            $line =
              _printTagLink( $tag, '' ) .
	      ($userAgnostic ? '' :
	       "<span class=\"tagMeVoteCount\">$num</span>");
	    if ( $showControl && _canTag() ) {
		if ( $users =~ /\b$user\b/ ) {
		    $line .= _imgTag( 'tag_remove',
			($userAgnostic ? 'Remove this tag' :
			 'Remove my vote on this tag'),
			'remove', $tag, $tagMode );
		}
		else {
		    $line .= _imgTag( 'tag_add', 'Add my vote for this tag',
			'add', $tag, $tagMode );
		}
	    }
            $seen{$tag} = _wrapHtmlTagControl($line);
        }
    }
    if ($normalizeTagInput) {

        # plain sort can be used and should be just a little faster
        $text .= join( ' ', map { $seen{$_} } sort keys(%seen) );
    }
    else {

        # uppercase characters are possible, so sort with lowercase comparison
        $text .=
          join( ' ', map { $seen{$_} } sort { lc $a cmp lc $b } keys(%seen) );
    }
    if ( $showControl ) {
        my @allTags = _readAllTags();
        my @notSeen = ();
        foreach (@allTags) {
            push( @notSeen, $_ ) unless ( $seen{$_} );
        }
        if ( _canTag() && scalar @notSeen ) {
            if ( $tagMode eq 'nojavascript' ) {
                $text .= _createNoJavascriptSelectBox(@notSeen);
            }
            else {
                $text .= _createJavascriptSelectBox(@notSeen);
            }
        }
	if ( _canTag() ) {
	    $text .= ' '.
		_wrapHtmlTagControl(
	    '<a rel="nofollow" ' .
	    'href="%SCRIPTURL{viewauth}%/' . $manipWeb . '/TagMeCreateNewTag'.
	    "?from=$web.$topic\">create new tag</a>");
	}
    }

    return _wrapHtmlTagMeShowForm($text) . $status;
}

# =========================
# displays a comprehensive tag management frame, with a common UI
sub _showStyleBlog {
    my %arg = @_;
    my @tagInfo;
    @tagInfo = @{$arg{tagInfo}} if ( $arg{tagInfo} && ref $arg{tagInfo} );
    my $status = $arg{status} || '';
    my $text  = '';

    # View mode
    if (!$action) {
	if ($button) {
	    $text .= $button;
	} elsif ($label) {
	    if ( _canTag() ) {
		$text = "<a rel='nofollow' class='tagmeEditLink' href='%SCRIPTURL{viewauth}%/%WEB%/%TOPIC%?tpaction=show' title='Open tag edit menu'>" . $label . "</a>" if $label;
	    }
	    else {
		$text = '';
	    }
	}
	return $text;
    }
    return _htmlErrorFeedbackChangeMessage('edit', '') unless (_canChange());

    my $query = TWiki::Func::getCgiQuery();
    my $tagMode = $query->param('tagmode') || '';

    my $webTopic = "$web.$topic";
    @tagInfo = _readTagInfo($webTopic) unless ( scalar(@tagInfo) );
    my @allTags = _readAllTags();
    my $tag   = '';
    my $num   = '';
    my $users = '';
    my $line  = '';
    my %seen = ();
    my %seen_my  = ();
    my %seen_others  = ();
    my %tagCount = ();
    # header
    $text .= $header."<fieldset class='tagmeEdit'><legend class='tagmeEdit'>Edit Tags - <a rel='nofollow' href='".
	$topic . "' name='tagmeEdit'>Done</a></legend>";

    $text .= $status;

    # My tags on this topic + Tags from others on this topic
    foreach (@tagInfo) {
        # Format:  3 digit number of users, tag, comma delimited list of users
        # Example: 004, usability, UserA, UserB, UserC, UserD
        # SMELL: This format is a quick hack for easy sorting, parsing, and
        # for fast rendering
        if (/$lineRegex/o) {
            $num   = $1;
            $tag   = $2;
            $users = $3;
            $seen{$tag} = lc $1;
            if ( $users =~ /\b$user\b/ ) { # we tagged this topic
                $line = "<a rel='nofollow' class='tagmeTag' href='" . $topic .
  	        "?tpaction=remove;tag=" . &_urlEncode($tag) . "'>". $tag .
		"</a> ";
		$seen_my{$tag} = _wrapHtmlTagControl($line);
            } else {                       # others tagged it
                $line = "<a rel='nofollow' class='tagmeTag' href='" . $topic .
  	        "?tpaction=add;tag=" . &_urlEncode($tag) . "'>". $tag .
		"</a> ";
		$line .= _imgTag( 'tag_remove', 'Force untagging',
				  'removeall', $tag, $tagMode );
		$seen_others{$tag} = _wrapHtmlTagControl($line);
            }
        }
    }

    if ($normalizeTagInput) {
        # plain sort can be used and should be just a little faster
        $text .= "<p class='tagmeBlog'><b>" .
	    ($userAgnostic ? '' : 'My ') . "Tags on this topic: </b>" . 
	    join( ' ', map { $seen_my{$_} } sort keys(%seen_my) ) .
	        "<br /><i>click to untag</i></p>";
        $text .= "<p class='tagmeBlog'><b>Tags on this topic by others: </b>". 
	    join( ' ', map { $seen_others{$_} } sort keys(%seen_others) ) . 
	        "<br /><i>click tag to also tag with, click delete icon to force untag by all</i></p>" if %seen_others;
    } else {
        # uppercase characters are possible, so sort with lowercase comparison
        $text .= "<p class='tagmeBlog'><b>" .
	    ($userAgnostic ? '' : "My ") . "Tags on this topic: </b>" . 
            join( ' ', map { $seen_my{$_} } sort { lc $a cmp lc $b } keys(%seen_my) ) .
	        "<br /><i>click to untag</i></p>";
        $text .= "<p class='tagmeBlog'><b>Tags on this topic by others: </b>" . 
            join( ' ', map { $seen_others{$_} } sort { lc $a cmp lc $b } keys(%seen_others) ) .
	        "<br /><i>click tag to also tag with, click delete icon to force untag by all</i></p>" if %seen_others;
    }

    # Related tags (and we compute counts)
    my %related   = ();
    my $tagWebTopic = '';
    foreach $tagWebTopic ( _getTagInfoList() ) {
	my @tagInfo = _readTagInfo($tagWebTopic);
	my @seenTopic = ();
	my $topicIsRelated = 0;
	foreach my $line (@tagInfo) {
	    if ( $line =~ /$lineRegex/o ) {
		$num   = $1;
                $tag   = $2;
		push (@seenTopic, $tag);
		$topicIsRelated = 1 if $seen{$tag};
		if ($tagCount{$tag}) {
		    $tagCount{$tag} += $num;
		} else {
		    $tagCount{$tag} = 1;
		}
	    }
	}
	if ($topicIsRelated) {
	    foreach my $tag (@seenTopic) {
		$related{$tag} = 1 unless ($seen{$tag});
	    }
	}
    }
    if ( %related ) {
        $text .= "<p class='tagmeBlog'><b>Related tags:</b> ";
	foreach my $tag (keys %related) {
	    $text .= "<a rel='nofollow' class='tagmeTag' href='" . $topic .
  	        "?tpaction=add;tag=" . &_urlEncode($tag) . "'>". $tag .
		    "</a> ";
	}
	$text .= "<br /><i>click to tag with</i></p>"
    }

    # Bundles, space or commas-seprated of titles: and tags
    my $bundles = TWiki::Func::getPreferencesValue('TAGMEPLUGIN_BUNDLES');
    if ( defined($bundles) && $bundles =~ /\S/ ) {
	my $tagsep = ( $bundles =~ /[^,]*/ ) ? qr/[\,\s]+/ :  qr/\s*\,+\s*/;
	my $listsep = '';
	$text .= "<p class='tagmeBlog'><b>Bundles:</b><ul><li> ";
	foreach my $tag ( split( $tagsep, $bundles )) {
	    if ( $tag =~ /:$/ ) {
		$text .= $listsep . "<b>$tag</b> ";
	    } else {
		if ( $seen{lc $tag} ) {
		    $text .= "<span class='tagmeTagNoclick'>" . $tag . 
			"</span> ";
		} else {
		    $text .= "<a rel='nofollow' class='tagmeTag' href='" . $topic .
			"?tpaction=autonewadd;tag=" . &_urlEncode($tag) . 
			    "'>". $tag . "</a> ";
		}
	    }
	    $listsep ="</li><li>";
	}
	$text .= "</li></ul></p>";
    }

    # Unused, available, tags in the system
    my @notSeen = ();
    foreach (@allTags) {
        push( @notSeen, $_ ) unless ( $seen_my{$_} || $seen_others{$_} );
    }

    if ( @notSeen ) {
        $text .= "<p class='tagmeBlog'><b>Available tags:</b> ";
	foreach my $tag (@notSeen) {
	    $text .= "<a rel='nofollow' class='tagmeTag' href='" . $topic .
  	        "?tpaction=add;tag=" . &_urlEncode($tag) . "'>". $tag .
		"</a>";
	    if ($tagCount{$tag}) {
		$text .= "<span class=\"tagMeVoteCount\">($tagCount{$tag})</span>";
	    } else {
		if ( _canChange() ) {
		    $text .= _imgTag( 'tag_remove', 'Delete tag',
				      'deletethetag', $tag, $tagMode );
		}
	    }
	    $text .= " ";
	}
	$text .= "<br /><i>click to tag with" .
            (_canChange() ? ", click delete icon to delete unused tags" : '') .
            "</i></p>";
    }

    # create and add tag
    if ( _canChange() ) {
        $text .= "<p class='tagmeBlog'><b>Tag with a new tag:</b>
            <form name='createtag' style='display:inline'>
            <input type='text' class='twikiInputField' name='tag' size='64' />
            <input type='hidden' name='tpaction' value='newtagsandadd' />
            <input type='submit' class='twikiSubmit' value='Create and Tag' />
            </form>
            <br /><i>You can enter multiple tags separated by spaces</i></p>";
    }

    # more
    $text .= "<p class='tagmeBlog'><b>Tags management:</b> 
        [[$manipWeb.TagMeCreateNewTag][create tags]] -
        [[$manipWeb.TagMeRenameTag][rename tags]] -
	[[$manipWeb.TagMeDeleteTag][delete tags]] -
	[[$manipWeb.TagMeViewAllTags][view all tags]] - " .
	($userAgnostic ? '' :
	 "[[$manipWeb.TagMeViewMyTags][view my tags]] - ") .
	"[[$manipWeb.TagMeSearch][search with tags]]
        </p>";
    # footer
    $text .= "</fieldset>".$footer;
    return $text;
}

# =========================
# Used as fallback for noscript
sub _createNoJavascriptSelectBox {
    my (@notSeen) = @_;

    my $selectControl = '';
    $selectControl .= '<select class="twikiSelect" name="tag"> <option></option> ';
    foreach (@notSeen) {
        $selectControl .= "<option>$_</option> ";
    }
    $selectControl .= '</select>';
    $selectControl .= _addNewButton();
    $selectControl = _wrapHtmlTagControl($selectControl);

    return $selectControl;
}

# =========================
# The select box plus contents is written using Javascript to prevent the tags
# getting indexed by search engines
sub _createJavascriptSelectBox {
    my (@notSeen) = @_;

    my $random          = int( rand(1000) );
    my $selectControlId = "tagMeSelect$random";
    my $selectControl   = "<span id=\"$selectControlId\"></span>";
    my $script          = <<'EOF';
<script type="text/javascript" language="javascript">
//<![CDATA[
function createSelectBox(inText, inElemId) {
	var selectBox = document.createElement('SELECT');
	selectBox.name = "tag";
	selectBox.className = "twikiSelect";
	document.getElementById(inElemId).appendChild(selectBox);
	var items = inText.split("#");
	var i, ilen = items.length;
	for (i=0; i<ilen; ++i) {
		selectBox.options[i] = new Option(items[i], items[i]);
	}
}
EOF
    $script .= 'var text="#' . join( "#", @notSeen ) . '";';
    $script .=
"\nif (text.length > 0) {createSelectBox(text, \"$selectControlId\"); document.getElementById(\"tagmeAddNewButton\").style.display=\"inline\";}\n//]]>\n</script>";

    my $noscript .=
'<noscript><a rel="nofollow" href="%SCRIPTURL{viewauth}%/%BASEWEB%/%BASETOPIC%?tagmode=nojavascript">tag this topic</a></noscript>';

    $selectControl .=
        '<span id="tagmeAddNewButton" style="display:none;">'
      . _addNewButton()
      . '</span>';
    $selectControl .= $script;

    $selectControl = _wrapHtmlTagControl($selectControl);
    $selectControl .= $noscript;

    return $selectControl;
}

# =========================
sub _addNewButton {

    my $input = '<input type="hidden" name="tpaction" value="add" />';
    $input .=
        '<input type="image"' . ' src="'
      . $attachUrl
      . '/tag_addnew.gif"'
      . ' class="tag_addnew"'
      . ' name="add"'
      . ' alt="Select tag and add to topic"'
      . ' value="Select tag and add to topic"'
      . ' title="Select tag and add to topic"' . ' />';
    return $input;
}

# =========================
sub _showAllTags {
    my ($attr) = @_;
    
    my @allTags = _readAllTags();
    return '' if scalar @allTags == 0;
  
    my $qWeb      = defined($attr->{web}) ? $attr->{web} : '';
    $qWeb =~ s:\.:/:g;
    my $qTopic    = defined($attr->{topic}) ? $attr->{topic} : '';
    my $exclude   = defined($attr->{exclude}) ? $attr->{exclude} : '';
    my $by        = defined($attr->{by}) ? $attr->{by} : '';
    my $format    = defined($attr->{format}) ? $attr->{format} : '';
    my $header    = defined($attr->{header}) ? $attr->{header} : '';
    my $separator = defined($attr->{separator}) ? $attr->{separator} : '';
    my $footer    = defined($attr->{footer}) ? $attr->{footer} : '';
    my $minSize   = defined($attr->{minsize}) ? $attr->{minsize} : '';
    my $maxSize   = defined($attr->{maxsize}) ? $attr->{maxsize} : '';
    my $minCount  = defined($attr->{mincount}) ? $attr->{mincount} : '';

    $minCount = 1 if !defined($minCount) || $qWeb || $qTopic || $exclude || $by;

    # a comma separated list of 'selected' options (for html forms)
    my $selection = defined($attr->{selection}) ? $attr->{selection} : '';
    my %selected = map { $_ => 1 } split( /,\s*/, $selection );

    $topicsRegex = '';
    if ($qTopic) {
        $topicsRegex = $qTopic;
        $topicsRegex =~ s/, */\|/go;
        $topicsRegex =~ s/\*/\.\*/go;
        $topicsRegex = '^.*\.(' . $topicsRegex . ')$';
    }
    my $excludeRegex = '';
    if ($exclude) {
        $excludeRegex = $exclude;
        $excludeRegex =~ s/, */\|/go;
        $excludeRegex =~ s/\*/\.\*/go;
        $excludeRegex = '^(' . $excludeRegex . ')$';
    }
    my $hasSeparator = $separator ne '';
    my $hasFormat    = $format    ne '';

    $separator = ', ' unless ( $hasSeparator || $hasFormat );
    $separator =~ s/\$n/\n/go;

    $format = '$tag' unless $hasFormat;
    $format .= "\n" unless $separator;
    $format =~ s/\$n/\n/go;

    $by = $user if ( $by eq 'me' );
    if ( $by eq 'all' ) {
        $by = '';
    } else {
        # $user is login name, convert to login name if needed
        $by = TWiki::Func::wikiToUserName( $by ) || $by;
    }
    $maxSize = 180 unless ($maxSize);    # Max % size of font
    $minSize = 90  unless ($minSize);
    my $text = '';
    my $line = '';
    unless ( $format =~ /\$(size|count|order)/ || $by || $qWeb || $qTopic || $exclude ) {

        # fast processing
        $text = join(
            $separator,
            map {
                my $tag = $_;
                $line = $format;
                $line =~ s/\$tag/$tag/go;
                $line =~ s/\$manipweb/$manipWeb/g;
                my $marker = '';
                $marker = ' selected="selected" ' if ( $selected{$tag} );
                $line =~ s/\$marker/$marker/g;
                $line;
              } @allTags
        );
    }
    else {

        # slow processing
        # SMELL: Quick hack, should be done with nice data structure
        my %tagCount = ();
        my %allTags  = map {$_=>1} @allTags;
        my %myTags   = ();
        my $webTopic = '';

        foreach (keys %allTags) {
          $tagCount{$_} = 0;
        }

        foreach $webTopic ( _getTagInfoList() ) {
            next if ( $qWeb        && $webTopic !~ /^$qWeb\./ );
            next if ( $topicsRegex && $webTopic !~ /$topicsRegex/ );
            my @tagInfo = _readTagInfo($webTopic);
            my $tag     = '';
            my $num     = '';
            my $users   = '';
            foreach $line (@tagInfo) {
                if ( $line =~ /$lineRegex/o ) {
                    $num   = $1;
                    $tag   = $2;
                    $users = $3;
                    unless ( $excludeRegex && $tag =~ /$excludeRegex/ ) {
                        $tagCount{$tag} += $num
                          unless ( $by && $users !~ /$by/ );
                        $myTags{$tag} = 1 if ( $users =~ /$by/ );
                    }
                }
            }
        }
        
        if ($minCount) {

            # remove items below the threshold
            foreach my $item ( keys %allTags ) {
                delete $allTags{$item} if ( $tagCount{$item} < $minCount );
            }
        }

        my @tags = ();
        if ($by) {
            if ($normalizeTagInput) {
                @tags = sort keys(%myTags);
            }
            else {
                @tags = sort { lc $a cmp lc $b } keys(%myTags);
            }
        }
        else {
            if ($normalizeTagInput) {
                @tags = sort keys(%allTags);
            }
            else {
                @tags = sort { lc $a cmp lc $b } keys(%allTags);
            }
        }
        if ( $by && !scalar @tags ) {
            if( $by eq $user ) {
                return
                  '__Note:__ You haven\'t yet added any tags. To add a tag, go to '
                  . 'a topic of interest, and add a tag from the list, or put your '
                  . 'vote on an existing tag.';
             } else {
                $by = TWiki::Func::getWikiName( $by ) || $by;
                return "__Note:__ <nop>$by hasn't yet added any tags."
             }
        }

#        my @ordered = sort { $tagCount{$a} <=> $tagCount{$b} } @tags;
        my @ordered = sort { $tagCount{$a} <=> $tagCount{$b} } keys(%tagCount);
        my %order = map { ( $_, $tagCount{$_} ) }
          @ordered;
        my $smallestItem = $ordered[0];
        my $largestItem = $ordered[$#ordered];
        my $smallest = $order{$smallestItem};
        my $largest = $order{$largestItem};
        my $div = ($largest - $smallest) || 1; # prevent division by zero
        my $sizingFactor = ($maxSize - $minSize) / $div;
        my $size   = 0;
        my $tmpSep = '_#_';
        $text = join(
            $separator,
            map {
                $size = int( $minSize + ( $order{$_} * $sizingFactor ) );
                $size = $minSize if ( $size < $minSize );
                $line = $format;
                $line =~ s/(tag\=)\$tag/$1$tmpSep\$tag$tmpSep/go;
                $line =~ s/$tmpSep\$tag$tmpSep/&_urlEncode($_)/geo;
                $line =~ s/\$tag/$_/go;
                $line =~ s/\$size/$size/go;
                $line =~ s/\$count/$tagCount{$_}/go;
                $line =~ s/\$order/$order{$_}/go;
                $line =~ s/\$manipweb/$manipWeb/g;
                $line;
              } @tags
        );
    }
    return $text ? $header.$text.$footer : $text;
}

# =========================
sub _queryTag {
    my ($attr) = @_;

    my $qWeb   = defined($attr->{web}) ? $attr->{web} : '';
    my $qTopic = defined($attr->{topic}) ? $attr->{topic} : '';
    my $qTag = _urlDecode( defined($attr->{tag}) ? $attr->{tag} : '' );
    my $refine = $attr->{refine} || $TWiki::cfg{TagMePlugin}{AlwaysRefine} ||
	'';
    my $qBy       = defined($attr->{by}) ? $attr->{by} : '';
    my $noRelated = defined($attr->{norelated}) ? $attr->{norelated} : '';
    my $noTotal   = defined($attr->{nototal}) ? $attr->{nototal} : '';
    my $sort =  $attr->{sort} || 'tagcount';
    my $format = $attr->{format} || $tagQueryFormat;
    my $separator = defined($attr->{separator}) ? $attr->{separator} : "\n";
    my $minSize      = defined($attr->{minsize}) ? $attr->{minsize} : '';
    my $maxSize      = defined($attr->{maxsize}) ? $attr->{maxsize} : '';
    my $resultLimit  = defined($attr->{limit}) ? $attr->{limit} : '';
    my $formatHeader = defined($attr->{header}) ? $attr->{header} :
	'---+++ $web';
    my $formatFooter = defined($attr->{footer}) ? $attr->{footer} :
      'Showing $limit out of $count results $showmore';

    return '__Note:__ Please select a tag' unless ($qTag);

    my $topicsRegex = '';
    if ($qTopic) {
        $topicsRegex = $qTopic;
        $topicsRegex =~ s/, */\|/go;
        $topicsRegex =~ s/\*/\.\*/go;
        $topicsRegex = '^.*\.(' . $topicsRegex . ')$';
    }
    $qBy = '' unless ($qBy);
    if ( $qBy eq 'all' ) {
        $qBy = '';    
    } else {    
        # $user is login name, convert to login name if needed
        $qBy = TWiki::Func::wikiToUserName( $qBy ) || $qBy;
    }
    my $by = $qBy;
    $by = $user if ( $by eq 'me' );
    $format    =~ s/([^\\])\"/$1\\\"/go;
    $separator =~ s/\$n\b/\n/go;
    $separator =~ s/\$n\(\)/\n/go;
    $maxSize = 180 unless ($maxSize);    # Max % size of font
    $minSize = 90  unless ($minSize);

    my @qTagsA = split( /,\s*/, $qTag );
    my $qTagsRE = join( '|', @qTagsA );

    # SMELL: Quick hack, should be done with nice data structure
    my $text      = '';
    my %tagVotes  = ();
    my %topicTags = ();
    my %related   = ();
    my %sawTag;
    my $tag   = '';
    my $num   = '';
    my $users = '';
    my @tags;
    my $webTopic = '';

    foreach $webTopic ( _getTagInfoList() ) {
        next if ( $qWeb        && $webTopic !~ /^$qWeb\./ );
        next if ( $topicsRegex && $webTopic !~ /$topicsRegex/ );
        my @tagInfo = _readTagInfo($webTopic);
        @tags   = ();
        %sawTag = ();
        foreach my $line (@tagInfo) {
            if ( $line =~ /$lineRegex/o ) {
                $num   = $1;
                $tag   = $2;
                $users = $3;
                push( @tags, $tag );
                if ( $tag =~ /^($qTagsRE)$/ ) {
                    $sawTag{$tag}        = 1;
                    $tagVotes{$webTopic} = $num
                      unless ( $by && $users !~ /$by/ );
                }
            }
        }
        if ( scalar keys %sawTag < scalar @qTagsA ) {

            # Not all tags seen, skip this topic
            delete $tagVotes{$webTopic};
        }
        elsif ( $tagVotes{$webTopic} ) {
            $topicTags{$webTopic} = [ sort { lc $a cmp lc $b } @tags ];
            foreach $tag (@tags) {
                unless( $tag =~ /^($qTagsRE)$/ ) {
                    $num = $related{$tag} || 0;
                    $related{$tag} = $num + 1;
                }
            }
        }
    }

    return "__Note:__ No topics found tagged with \"$qTag\""
      unless ( scalar keys(%tagVotes) );

    # related tags
    unless ($noRelated) {

        # TODO: should be conditional sort
        my @relatedTags = map { _printTagLink( $_, $qBy, undef, $refine ) }
          grep { !/^\Q$qTagsRE\E$/ }
          sort { lc $a cmp lc $b } keys(%related);
        if (@relatedTags) {
            $text .= '<span class="tagmeRelated">%MAKETEXT{"Related tags"}%';
            $text .= ' (%MAKETEXT{"Click to refine the search"}%)' if $refine;
            $text .= ': </span> ' . join( ', ', @relatedTags ) . "\n\n";
        }
    }

    my @topics = ();
    if ( $sort eq 'tagcount' ) {

        # Sort topics by tag count
        @topics = sort { $tagVotes{$b} <=> $tagVotes{$a} } keys(%tagVotes);
    }
    elsif ( $sort eq 'topic' ) {

        # Sort topics by topic name
        @topics = sort {
            substr( $a, rindex( $a, '.' ) ) cmp substr( $b, rindex( $b, '.' ) )
          }
          keys(%tagVotes);
    }
    else {

        # Sort topics by web, then topic
        @topics = sort keys(%tagVotes);
    }
    if ( $format =~ /\$size/ ) {

        # handle formatting with $size (slower)
        my %order = ();
        my $max   = 1;
        my $size  = 0;
        %order = map { ( $_, $max++ ) }
          sort { $tagVotes{$a} <=> $tagVotes{$b} }
          keys(%tagVotes);
        foreach $webTopic (@topics) {
            $size = int( $maxSize * ( $order{$webTopic} + 1 ) / $max );
            $size = $minSize if ( $size < $minSize );
            $text .=
              _printWebTopic( $webTopic, $topicTags{$webTopic}, $qBy, $format,
                $tagVotes{$webTopic}, $size );
            $text .= $separator;
        }
    }
    else {

        # normal formatting without $size (faster)
        if ( $qWeb =~ /\|/ ) {

            #multiple webs selected
            my %webText;
            my %resultCount;
            foreach $webTopic (@topics) {
                my ( $thisWeb, $thisTopic ) =
                  TWiki::Func::normalizeWebTopicName( '', $webTopic );

                #initialise this new web with the header
                unless ( defined( $webText{$thisWeb} ) ) {
                    $webText{$thisWeb}     = '';
                    $resultCount{$thisWeb} = 0;
                    if ( defined($formatHeader) ) {
                        my $header = $formatHeader;
                        $header =~ s/\$web/$thisWeb/g;
                        $webText{$thisWeb} .= "\n$header\n";
                    }
                }
                $resultCount{$thisWeb}++;

                #limit by $resultLimit
                next
                  if ( ( defined($resultLimit) )
                    && ( $resultLimit ne '' )
                    && ( $resultLimit < $resultCount{$thisWeb} ) );

                $webText{$thisWeb} .=
                  _printWebTopic( $webTopic, $topicTags{$webTopic}, $qBy,
                    $format, $tagVotes{$webTopic} );
                $webText{$thisWeb} .= $separator;
            }
            my @webOrder = split( /[)(|]/, $qWeb );
            foreach my $thisWeb (@webOrder) {
                if ( defined( $webText{$thisWeb} ) ) {
                    if ( defined($formatFooter) ) {
                        my $footer = $formatFooter;
                        $footer =~ s/\$web/$thisWeb/g;
                        my $c =
                          ( $resultLimit < $resultCount{$thisWeb} )
                          ? $resultLimit
                          : $resultCount{$thisWeb};
                        $footer =~ s/\$limit/$c/g;
                        my $morelink = '';

                        #TODO: make link
                        $morelink =
"\n %BR%<div class='tagShowMore'> *Show All results*: "
                          . _printTagLink( $qTag, $qBy, $thisWeb )
                          . "</div>\n"
                          if ( $c < $resultCount{$thisWeb} );
                        $footer =~ s/\$showmore/$morelink/g;
                        $footer =~ s/\$count/$resultCount{$thisWeb}/g;
                        $webText{$thisWeb} .= "\n$footer\n";
                    }
                    $text .= $webText{$thisWeb} . "\n";
                }
            }
        }
        else {
            foreach $webTopic (@topics) {
                $text .=
                  _printWebTopic( $webTopic, $topicTags{$webTopic}, $qBy,
                    $format, $tagVotes{$webTopic} );
                $text .= $separator;
            }
        }
    }
    $text =~ s/\Q$separator\E$//s;
    $text .= "\n%MAKETEXT{\"Number of topics\"}%: " . scalar( keys(%tagVotes) )
      unless ($noTotal);
    _handleMakeText($text);
    return $text;
}

# =========================
sub _printWebTopic {
    my ( $webTopic, $tagsRef, $qBy, $format, $voteCount, $size ) = @_;
    $webTopic =~ /^(.*)\.(.)(.*)$/;
    my $qWeb = $1;
    my $qT1  = $2
      ; # Workaround for core bug Bugs:Item2625, fixed in SVN 11484, hotfix-4.0.4-4
    my $qTopic = quotemeta("$2$3");
    my $text   = '%SEARCH{ '
      . "\"^$qTopic\$\" scope=\"topic\" web=\"$qWeb\" topic=\"$qT1\*\" "
      . 'regex="on" limit="1" nosearch="on" nototal="on" '
      . "format=\"$format\"" . ' }%';
    $text = TWiki::Func::expandCommonVariables( $text, $qTopic, $qWeb );

    # TODO: should be conditional sort
    $text =~
s/\$taglist/join( ', ', map{ _printTagLink( $_, $qBy ) } sort { lc $a cmp lc $b} @{$tagsRef} )/geo;
    $text =~ s/\$size/$size/go if ($size);
    $text =~ s/\$votecount/$voteCount/go;
    return $text;
}

# =========================
sub _printTagLink {
    my ( $qTag, $by, $web, $refine ) = @_;
    $web = '' unless ( defined($web) );

    my $links = '';

    foreach my $tag ( split( /,\s*/, $qTag ) ) {
        my $text = $tagLinkFormat;
        if ($refine) {
            $text = '<a rel="nofollow" href="'
              . TWiki::Func::getCgiQuery()->url( -path_info => 1 ) . '?'
              . TWiki::Func::getCgiQuery()->query_string();
            $text .= ";tag=" . _urlEncode($tag) . '">' . $tag . '</a>';
        }

        # urlencode characters
        # in 2 passes
        my $tmpSep = '_#_';
        $text =~ s/(tag=)\$tag/$1$tmpSep\$tag$tmpSep/go;
        $text =~ s/$tmpSep\$tag$tmpSep/&_urlEncode($tag)/geo;
        $text =~ s/\$tag/$tag/go;
        $text =~ s/\$by/$by/go;
        $text =~ s/\$web/$web/go;
        $links .= $text;
    }
    return $links;
}

# =========================
# Add new tag to system
sub _newTag {
    my ($attr) = @_;

    my $tag = defined($attr->{tag}) ? $attr->{tag} : '';
    my $note = defined($attr->{note}) ? $attr->{note} : '';
    my $silent = defined($attr->{silent}) ? $attr->{silent} : '';

    my $query = TWiki::Func::getCgiQuery();
    my $postChangeRequest = $query->param('postChangeRequest') || '';
    if ($postChangeRequest) {
        return _handlePostChangeRequest( 'create', undef, $tag, $note );
    }
    if ( !_canChange() || $user =~ /^(TWikiGuest|guest)$/ ) {
        return _htmlErrorFeedbackChangeMessage( 'create', $note );
    }

    $tag = _makeSafeTag($tag);

    return _wrapHtmlErrorFeedbackMessage( "Please enter a tag", $note )
      unless ($tag);
    my @allTags = _readAllTags();
    if ( grep( /^\Q$tag\E$/, @allTags ) ) {
	return _wrapHtmlErrorFeedbackMessage("Tag \"$tag\" already exists", $note ) unless (defined $silent) ;
    }
    else {
        push( @allTags, $tag );
        writeAllTags(\@allTags);
        _writeLog("New tag '$tag'");
        my $query = TWiki::Func::getCgiQuery();
        my $from  = $query->param('from');
        if ($from) {
            $note = '<a rel="nofollow" href="%SCRIPTURL{viewauth}%/%URLPARAM{"from"}%?tpaction=add;tag=%URLPARAM{newtag}%">'
                  . 'Add tag "%URLPARAM{newtag}%" to %URLPARAM{"from"}%</a>%BR%'
                  . $note;
        }
        return _wrapHtmlFeedbackMessage( "Tag \"$tag\" is successfully added",
            $note );
    }
    return "";
}

# =========================
# Normalize tag, strip illegal characters, limit length
sub _makeSafeTag {
    my ($tag) = @_;
    if ($normalizeTagInput) {
        $tag =~ s/[- \/]/_/go;
        $tag = lc($tag);
        $tag =~ s/[^${alphaNum}_]//go;
        $tag =~ s/_+/_/go;              # replace double underscores with single
    }
    else {
        $tag =~ s/[\x01-\x1f^\#\,\'\"\|\*]//go;    # strip #,'"|*
    }
    $tag = substr($tag, 0, $maxTagLen) if ( length($tag) > $maxTagLen ); # limit tag length
    $tag =~ s/^\s*//;                              # trim spaces at start
    $tag =~ s/\s*$//;                              # trim spaces at end
    return $tag;
}

# =========================
# Add tag to topic
# The tag must already exist
sub _addTag {
    my ( $attr ) = @_;

    my $addTag = defined($attr->{tag}) ? $attr->{tag} : '';
    my $noStatus = defined($attr->{nostatus}) ? $attr->{nostatus} : '';

    my $webTopic = "$web.$topic";
    my @tagInfo  = _readTagInfo($webTopic);

    my $text     = '';
    my $tag      = '';
    my $num      = '';
    my $users    = '';
    my @result   = ();
    my $tagExists = scalar( grep{ /^\Q$addTag\E$/ } _readAllTags() );
    if ( !$tagExists ) {
        $text .= _wrapHtmlFeedbackErrorInline("tag not added, it needs to be created first");

    } elsif ( TWiki::Func::topicExists( $web, $topic ) ) {
	if ( _canTag() ) {
	    foreach my $line (@tagInfo) {
		if ( $line =~ /$lineRegex/o ) {
		    $num   = $1;
		    $tag   = $2;
		    $users = $3;
		    if ( $tag eq $addTag ) {
			if ( $users =~ /\b$user\b/ ) {
			    $text .=
			      _wrapHtmlFeedbackErrorInline(
				"you already added this tag");
			}
			else {

			    # add user to existing tag
			    $line =
				_tagDataLine( $num + 1, $tag, $users, $user );
			    $text .= _wrapHtmlFeedbackInline(
				"added tag vote on \"$tag\"");
			    _writeLog("Added tag vote on '$tag'");
			}
		    }
		}
		push( @result, $line );
	    }
	    unless ($text) {

		# tag does not exist yet
		if ($addTag) {
		    push( @result, "001, $addTag, $user" );
		    $text .= _wrapHtmlFeedbackInline("added tag \"$addTag\"");
		    _writeLog("Added tag '$addTag'");
		}
		else {
		    $text .= _wrapHtmlFeedbackInline(" (please select a tag)");
		}
	    }
	    @tagInfo = reverse sort(@result);
	    _writeTagInfo( $webTopic, @tagInfo );
	}
	else {
	    $text .= "You are not allowed to add tags to this topic";
	}
    } else {
        $text .= _wrapHtmlFeedbackErrorInline("tag not added, topic does not exist");
    }

    # Suppress status? FWM, 03-Oct-2006
    return _showDefault(tagInfo => \@tagInfo,
			status => ($noStatus ? '' : $text) );
}

# =========================
# Create and tag with multiple tags
sub _newTagsAndAdd {
    my ( $attr ) = @_;
    my $text;
    my $args;
    my $tags = defined($attr->{tag}) ? $attr->{tag} : '';
    my $noStatus = defined($attr->{nostatus}) ? $attr->{nostatus} : '';
    $tags =~ s/^\s+//o;
    $tags =~ s/\s+$//o;
    $tags =~ s/\s\s+/ /go;
    foreach my $tag ( split( ' ', $tags )) {
	$tag = _makeSafeTag($tag);
	if ($tag) {
	    $args = { tag => $tag };
	    $text = _newTag($args);
	    unless ( $text =~ /twikiAlert/ ) {
		$args->{nostatus} = 'on' if ( $noStatus );
		$text = _addTag($args);
	    }
	}
    }
    return $text;
}

# =========================
# Remove my tag vote from topic
sub _removeTag {
    my ( $attr ) = @_;

    my $removeTag = defined($attr->{tag}) ? $attr->{tag} : '';
    my $noStatus = defined($attr->{nostatus}) ? $attr->{nostatus} : '';

    my $webTopic = "$web.$topic";
    my @tagInfo  = _readTagInfo($webTopic);
    my $text     = '';
    my $tag      = '';
    my $num      = '';
    my $users    = '';
    my $found    = 0;
    my @result   = ();
    if ( _canTag() ) {
	foreach my $line (@tagInfo) {
	    if ( $line =~ /$lineRegex/o ) {
		$num   = $1;
		$tag   = $2;
		$users = $3;
		if ( $tag eq $removeTag ) {
		    my %userHash = map { $_ => 1 } split(/, */, $users);
		    if ( $userHash{$user} ) {
			$found = 1;
                        delete $userHash{$user};
			$users = join(', ', sort keys %userHash);
			$num--;
			if ($num) {
			    $line = _tagDataLine( $num, $tag, $users );
			    $text .=
			      _wrapHtmlFeedbackInline(
				"removed my tag vote on \"$tag\"");
			    _writeLog("Removed tag vote on '$tag'");
			    push( @result, $line );
			}
			else {
			    $text .=
			      _wrapHtmlFeedbackInline("removed tag \"$tag\"");
			    _writeLog("Removed tag '$tag'");
			}
		    }
		}
		else {
		    push( @result, $line );
		}
	    }
	    else {
		push( @result, $line );
	    }
	}
	if ($found) {
	    @tagInfo = reverse sort(@result);
	    _writeTagInfo( $webTopic, @tagInfo );
	}
	else {
	    $text .=
		_wrapHtmlFeedbackErrorInline("Tag \"$removeTag\" not found");
	}
    }
    else {
	$text = _wrapHtmlFeedbackErrorInline(
	    "You are not allowed to remove tags from this topic");
    }

    # Suppress status? FWM, 03-Oct-2006
    return _showDefault(tagInfo => \@tagInfo,
			status => ($noStatus ? '' : $text));
}

# =========================
# Force remove tag from topic (clear all users votes)
sub _removeAllTag {
    my ( $attr ) = @_;

    my $removeTag = defined($attr->{tag}) ? $attr->{tag} : '';
    my $noStatus = defined($attr->{nostatus}) ? $attr->{nostatus} : '';

    my $webTopic = "$web.$topic";
    my @tagInfo  = _readTagInfo($webTopic);
    my $text     = '';
    my $tag      = '';
    my $num      = '';
    my $found    = 0;
    my @result   = ();
    if ( _canTag() ) {
	foreach my $line (@tagInfo) {
	    if ( $line =~ /$lineRegex/o ) {
		$num   = $1;
		$tag   = $2;
		if ( $tag eq $removeTag ) {
		    $text .= _wrapHtmlFeedbackInline("removed tag \"$tag\"");
		    _writeLog("Removed tag '$tag'");
		    $found = 1;
		} else {
		    push( @result, $line );
		}
	    } else {
		push( @result, $line );
	    }
	}
	if ($found) {
	    @tagInfo = reverse sort(@result);
	    _writeTagInfo( $webTopic, @tagInfo );
	} else {
	    $text .=
		_wrapHtmlFeedbackErrorInline("Tag \"$removeTag\" not found");
	}
    }
    else {
	$text = _wrapHtmlFeedbackErrorInline(
	    "You are not allowed to remove tags from this topic");
    }

    # Suppress status? FWM, 03-Oct-2006
    return _showDefault(tagInfo => \@tagInfo,
			status => ($noStatus ? '' : $text));
}

# =========================
sub _tagDataLine {
    my ( $num, $tag, $users, $user ) = @_;

    my $line = sprintf( '%03d', $num );
    $line .= ", $tag, $users";
    $line .= ", $user" if $user;
    return $line;
}

# =========================
sub _imgTag {
    my ( $image, $title, $action, $tag, $tagMode ) = @_;
    my $text = '';

    #my $tagMode |= '';

    if ($tag) {
        $text =
"<a rel=\"nofollow\" class=\"tagmeAction $image\" href=\"%SCRIPTURL{viewauth}%/%BASEWEB%/%BASETOPIC%?"
          . "tpaction=$action;tag="
          . _urlEncode($tag)
          . ";tagmode=$tagMode\">";
    }
    $text .=
        "<img src=\"$attachUrl/$image.gif\""
      . " alt=\"$title\" title=\"$title\""
      . " width=\"11\" height=\"10\""
      . " align=\"middle\""
      . " border=\"0\"" . " />";
    $text .= "</a>" if ($tag);
    return $text;
}

# =========================
sub _workAreaDir {
    if ( $TWiki::cfg{TagMePlugin}{SplitSpace} ) {
	my ($w, $withTopic) = @_;
	$w =~ s:/:.:g;
	$w =~ s/\.[^.]+$// if ( $withTopic );
	$w = _manipWeb($w);
	return TWiki::Func::getPubDir($w) . "/$w/.tags";
    }
    else {
	return $workAreaDir;
    }
}

# =========================
use Sys::Hostname;

sub mkdirRecursive {
    my $dir = shift;
    my $parent = $dir;
    $parent =~ s:/[^/]+$::;
    if ( ! -d $parent && $dir ne $parent ) {
        mkdirRecursive($parent) or
            return 0;
    }
    return mkdir($dir);
}

sub _saveFile {
    my ($file, $text) = @_;
    _writeDebug("_saveFile($file, ...)");
    my $dir = $file;
    if ( $dir =~ s:/[^/]+$:: ) {
        unless ( -d $dir ) {
            mkdirRecursive($dir) or do {
                _writeWarning("mkdir: $dir: $!");
                return 0;
            };
        }
    }
    my $tmpFile = "$file.$$." . hostname() . '.tmp';
    open(FILE, ">$tmpFile") or do {
	_writeWarning("open: >$tmpFile: $!");
	return 0;
    };
    print FILE $text or do {
	_writeWarning("print: >$tmpFile: $!");
	return 0;
    };
    close(FILE) or do {
	_writeWarning("close: >$tmpFile: $!");
	return 0;
    };
    rename($tmpFile, $file) or do {
	_writeWarning("rename: $tmpFile -> $file: $!");
	return 0;
    };
    return 1
}

# =========================
sub _getTagInfoList {
    my @list;
    my $workDir = _workAreaDir($web);
    if ( opendir( DIR, $workDir ) ) {
        my @files = sort
                    grep { !/^\./ } # eliminate . and ..
                    readdir(DIR);
        closedir DIR;
	for ( @files ) {
	    if ( /^_tags_(.*)\.txt$/ ) {
		next if ( $1 eq 'all' );
		push(@list, $1);
	    }
	}
    }
    return sort @list;
}

# =========================
sub _readTagInfo {
    my ($webTopic) = @_;

    $webTopic =~ s/[\/\\]/\./g;
    my $workDir = _workAreaDir($webTopic, 1);
    my $text = TWiki::Func::readFile("$workDir/_tags_$webTopic.txt");
    my @info = grep { /^[0-9]/ } split( /\n/, $text );
    if ( $userAgnostic ) {
	for ( @info ) {
	    s/$lineRegex/001, $2, $user/o;
	}
    }
    return @info;
}

# =========================
sub _writeTagInfo {
    my ( $webTopic, @info ) = @_;
    $webTopic =~ s/[\/\\]/\./g;
    my $workDir = _workAreaDir($webTopic, 1);
    my $file = "$workDir/_tags_$webTopic.txt";
    if ( scalar @info ) {
        my $text =
          "# This file is generated, do not edit\n"
          . join( "\n", reverse sort @info ) . "\n";
        _saveFile( $file, $text );
    }
    elsif ( -e $file ) {
        unlink($file);
    }
}

# =========================
sub renameOrCopyTagInfo {
    my ( $oldWebTopic, $newWebTopic, $opr ) = @_;

    $oldWebTopic =~ s/[\/\\]/\./g;
    $newWebTopic =~ s/[\/\\]/\./g;
    my $workDirO = _workAreaDir($oldWebTopic, 1);
    my $workDirN = _workAreaDir($newWebTopic, 1);
    my $oldFile = "$workDirO/_tags_$oldWebTopic.txt";
    my $newFile = "$workDirN/_tags_$newWebTopic.txt";
    if ( -e $oldFile ) {
	my $newTrash = $newWebTopic =~ /^Trash\./;
	# the tag file is moved to Trash so that it can be undeleted.
	if ( -d $workDirN || $newTrash ) {
	    my $text = TWiki::Func::readFile($oldFile);
	    if ( $workDirO ne $workDirN && !$newTrash ) {
		# If there are missing tags in the tag list of the destination
		# (_tags_all.txt), add them.
		my @tagsOfTopic;
		for ( split(/\n/, $text) ) {
		    if ( /$lineRegex/ ) {
			push(@tagsOfTopic, $2);
		    }
		}
		my $newWeb = $newWebTopic;
		$newWeb =~ s/\.[^.]+$//;
		my %tagOfNewWeb = map { $_ => 1 }  _readAllTags($newWeb);
		my $nTags = keys %tagOfNewWeb;
		@tagOfNewWeb{@tagsOfTopic} = (1) x @tagsOfTopic;
		my @tagsOfNewWeb = keys %tagOfNewWeb;
		if ( $nTags != @tagsOfNewWeb ) {
		    writeAllTags(\@tagsOfNewWeb, $newWeb);
		}
	    }
	    _saveFile( $newFile, $text );
	}
	else {
	    _writeWarning(
"tags are not copied from $oldWebTopic to $newWebTopic because " .
"the destination web is not using tags"
	    );
	}
	unlink($oldFile) if ( $opr ne 'copy' );
    }
}

# =========================
sub _readAllTags {
    my ($w) = @_;
    $w ||= $web;
    my $workDir = _workAreaDir($w);
    my $text = TWiki::Func::readFile("$workDir/_tags_all.txt");

    #my @tags = grep{ /^[${alphaNum}_]/ } split( /\n/, $text );
    # we assume that this file has been written by TagMe, so tags should be
    # valid, and we only need to filter out the comment line
    my @tags = grep { !/^\#.*/ } split( /\n/, $text );
    return @tags;
}

# =========================
# Sorting of tags (lowercase comparison) is done just before writing of
# the _tags_all file.
sub writeAllTags {
    my ($tagsRef, $w) = @_;
    $w ||= $web;
    my $text =
      "# This file is generated, do not edit\n"
      . join( "\n", sort { lc $a cmp lc $b } @$tagsRef ) . "\n";
    my $workDir = _workAreaDir($w);
    _saveFile( "$workDir/_tags_all.txt", $text );
}

# =========================
sub _modifyTag {
    my ( $oldTag, $newTag, $changeMessage, $note ) = @_;

    return _htmlErrorFeedbackChangeMessage( 'modify', $note ) if !_canChange();

    my @allTags = _readAllTags();

    if ($oldTag) {
        if ( !grep( /^\Q$oldTag\E$/, @allTags ) ) {
            return _wrapHtmlErrorFeedbackMessage(
                "Tag \"$oldTag\" does not exist", $note );
        }
    }
    if ($newTag) {
        if ( grep( /^\Q$newTag\E$/, @allTags ) ) {
            return _wrapHtmlErrorFeedbackMessage(
                "Tag \"$newTag\" already exists", $note );
        }
    }

    my @newAllTags = grep( !/^\Q$oldTag\E$/, @allTags );
    push( @newAllTags, $newTag ) if ($newTag);
    writeAllTags(\@newAllTags);

    my $webTopic = '';
    foreach $webTopic ( _getTagInfoList() ) {
        next if ( $topicsRegex && $webTopic !~ /$topicsRegex/ );
        my @tagInfo = _readTagInfo($webTopic);
        my $tag     = '';
        my $num     = '';
        my $users   = '';
        my $tagChanged = 0;    # only save new file if content should be updated
        my @result     = ();
        foreach my $line (@tagInfo) {

            if ( $line =~ /^($lineRegex)$/o ) {
                $line  = $1;
                $num   = $2;
                $tag   = $3;
                $users = $4;
                if ($newTag) {

                    # rename
                    if ( $tag eq $oldTag ) {
                        $line = _tagDataLine( $num, $newTag, $users );
                        $tagChanged = 1;
                    }
                    push( @result, $line );
                }
                else {

                    # delete
                    if ( $tag eq $oldTag ) {
                        $tagChanged = 1;
                    }
                    else {
                        push( @result, $line );
                    }
                }
            }
        }
        if ($tagChanged) {
            @result = reverse sort(@result);
            $webTopic =~ /(.*)/;
            $webTopic = $1;    # untaint
            _writeTagInfo( $webTopic, @result );
        }
    }

    _writeLog($changeMessage);
    return _wrapHtmlFeedbackMessage( $changeMessage, $note );
}

# =========================
sub _canTag {
    return $canTag if ( defined($canTag) );
    return $canTag = 0 if ( $inactiveSite );
    my $allowTopic = TWiki::Func::getPreferencesValue('ALLOWTOPICTAG') || '';
    my $allowWeb = TWiki::Func::getPreferencesValue('ALLOWWEBTAG', $web) || '';
    my $denyTopic = TWiki::Func::getPreferencesValue('DENYTOPICTAG') || '';
    my $denyWeb = TWiki::Func::getPreferencesValue('DENYWEBTAG', $web) || '';
    my $mode =
	( $allowTopic =~ /\S/ || $allowWeb =~ /\S/ ||
	  $denyTopic =~ /\S/ || $denyWeb =~ /\S/ ) ? 'TAG' : 'CHANGE';
    my $wikiUserName = TWiki::Func::getWikiName();
    # You may think that under user conscious taggin, everybody is supposed to
    # be able to tag every topic.
    # But it's better for users owning a topic or a web to be able to restrict
    # who can tag even under user conscious tagging.
    return $canTag = 1
      if ( TWiki::Func::checkAccessPermission( $mode, $wikiUserName, undef, $topic, $web, undef) );
    return $canTag = _canChange();
    # Everybody who can change tags needs to be able to tag and untag pages.
    # This is because to delete a tag from the tag set, the tag needs to be
    # removed from all topics
}

# =========================
sub _canChange {
    return $canChange if ( defined($canChange) );
    my $session = $TWiki::Plugins::SESSION;
    return $canChange = 0 if ( $inactiveSite );
    my $deny;
    my $allow;
    if ( $TWiki::cfg{TagMePlugin}{SplitSpace} ) {
        $deny = TWiki::Func::getPreferencesValue('DENY_TAG_CHANGE', $web);
        $allow = TWiki::Func::getPreferencesValue('ALLOW_TAG_CHANGE', $web);
    }
    else {
        $deny = TWiki::Func::getPreferencesValue('DENY_TAG_CHANGE');
        $allow = TWiki::Func::getPreferencesValue('ALLOW_TAG_CHANGE');
    }
    $deny ||= '';
    $allow ||= '';

    if ( $deny =~ /\S/ || $allow =~ /\S/ ) {
	# If either or both of DENY_TAG_CHANGE and ALLOW_TAG_CHANGE are
	# defined, then they are used to determine tag change permission.
	# Even if they deny tag change, site admins and web admins have
	# tag change permission.
        my $wikiName = TWiki::Func::getWikiName();
	if ( $deny =~ /\S/ ) {
	    if ( _isInList($deny) ) {
                return $canChange = 0 unless ( TWiki::Func->can('isAnAdmin') );
                return $canChange =
                    TWiki::Func::isAnAdmin($wikiName, $topic, $web);
	    }
	}
	if ( $allow =~ /\S/ ) {
	    unless ( _isInList($allow) ) {
                return $canChange = 0 unless ( TWiki::Func->can('isAnAdmin') );
                return $canChange =
                    TWiki::Func::isAnAdmin($wikiName, $topic, $web);
	    }
	}
	return $canChange = 1;
    }
    elsif ( $TWiki::cfg{TagMePlugin}{SplitSpace} ) {
	# If neither DENY_TAG_CHANGE or ALLOW_TAG_CHANGE is defined, then
	# change permission to WebPreferences dictates it.
        my $wikiUserName = TWiki::Func::getWikiName();
	return $canChange = TWiki::Func::checkAccessPermission(
	    'CHANGE', $wikiUserName, undef, $TWiki::cfg{WebPrefsTopicName}, $manipWeb,
	    undef);
    }
    else {
        return $canChange = 1;
    }
}

# =========================
sub _renameTag {
    my ($attr) = @_;

    my $oldTag = defined($attr->{oldtag}) ? $attr->{oldtag} : '';
    my $newTag = defined($attr->{newtag}) ? $attr->{newtag} : '';
    my $note   = defined($attr->{note}) ? $attr->{note} : '';

    my $query = TWiki::Func::getCgiQuery();
    my $postChangeRequest = $query->param('postChangeRequest') || '';
    if ($postChangeRequest) {
        return _handlePostChangeRequest( 'rename', $oldTag, $newTag, $note );
    }
    return _htmlErrorFeedbackChangeMessage( 'rename', $note ) if !_canChange();

    $newTag = _makeSafeTag($newTag);

    return _wrapHtmlErrorFeedbackMessage( "Please select a tag to rename",
        $note )
      unless ($oldTag);

    return _wrapHtmlErrorFeedbackMessage( "Please enter a new tag name", $note )
      unless ($newTag);

    my $changeMessage =
      "Tag \"$oldTag\" is successfully renamed to \"$newTag\"";
    return _modifyTag( $oldTag, $newTag, $changeMessage, $note );
}

# =========================
sub _handlePostChangeRequest {
    my ( $mode, $oldTag, $newTag, $note ) = @_;

    my $userName    = TWiki::Func::getWikiUserName();
    my $requestLine = '';
    my $message     = '';
    my $logMessage  = '';
    my $ctx = TWiki::Func::getContext();
    my $inactiveSite = ref $ctx && ( $ctx->{inactive} || $ctx->{content_slave} );
    if ( $inactiveSite ) {
	$message = "Your request cannot be added to $tagChangeRequestLink " .
	    "since this web is read-only: $mode, $oldTag, $newTag";
	$logMessage = $message . " (requested by $userName)";
    }
    else {
	my $date = TWiki::Time::formatTime(time(), '$day $mon $year', 'gmtime');
	if ( $mode eq 'rename' ) {
	    $requestLine =
		"| Rename | $oldTag | $newTag | $userName | $date |";
	    $message .=
"Your request to rename \"$oldTag\" to \"$newTag\" is added to $tagChangeRequestLink";
	    $logMessage .=
    "Posted tag rename request: from '$oldTag' to '$newTag' (requested by $userName)";
	}
	elsif ( $mode eq 'delete' ) {
	    $requestLine =
"| %RED% Delete %ENDCOLOR% | %RED% $oldTag %ENDCOLOR%  | | $userName | $date |";
	    $message .=
"Your request to delete \"$oldTag\" is added to $tagChangeRequestLink";
	    $logMessage .=
	      "Posted tag delete request: '$oldTag' (requested by $userName)";
	}
	elsif ( $mode eq 'create' ) {
	    $requestLine =
"| %RED% Add %ENDCOLOR% | %RED% $newTag %ENDCOLOR%  | | $userName | $date |";
	    $message .=
"Your request to create \"$newTag\" is added to $tagChangeRequestLink";
	    $logMessage .=
	      "Posted tag create request: '$newTag' (requested by $userName)";
	}

	my ( $meta, $text ) =
	  TWiki::Func::readTopic( $manipWeb, $tagChangeRequestTopic );
	$text =~ s/\s+$//;
	$text .= "\n" . $requestLine;
	TWiki::Func::saveTopic( $manipWeb, $tagChangeRequestTopic, $meta, $text,
	    { comment => 'posted tag change request' } );
    }

    $message .= _htmlPostChangeRequestFormField();

    _writeLog($logMessage);

    return _wrapHtmlFeedbackMessage( $message, $note );
}

# =========================
# Default (starting) modify action so we can post a useful feedback message if
# this user is not allowed to change tags.
# Is he can change no feedback message will be shown.
sub _modifyTagInit {
    my ( $mode, $attr ) = @_;

    my $note = defined($attr->{note}) ? $attr->{note} : '';

    return _htmlErrorFeedbackChangeMessage( $mode, $note ) if !_canChange();

    return $note;
}

# =========================
sub _deleteTag {
    my ($attr) = @_;
    my $deleteTag = defined($attr->{oldtag}) ? $attr->{oldtag} : '';
    my $note = defined($attr->{note}) ? $attr->{note} : '';

    my $query = TWiki::Func::getCgiQuery();
    my $postChangeRequest = $query->param('postChangeRequest') || '';
    if ($postChangeRequest) {
        return _handlePostChangeRequest( 'delete', $deleteTag, undef, $note );
    }
    return _htmlErrorFeedbackChangeMessage( 'delete', $note ) if !_canChange();

    return _wrapHtmlErrorFeedbackMessage( "Please select a tag to delete",
        $note )
      unless ($deleteTag);

    my $changeMessage = "Tag \"$deleteTag\" is successfully deleted";
    return _modifyTag( $deleteTag, '', $changeMessage, $note );
}

# =========================
# same as above but to be used inlinr on a topic, for some styles
sub _deleteTheTag {
    my ($attr) = @_;
    my $deleteTag = defined($attr->{tag}) ? $attr->{tag} : '';
    my $note = defined($attr->{note}) ? $attr->{note} : '';

    return _htmlErrorFeedbackChangeMessage( 'delete', $note ) if !_canChange();

    return _wrapHtmlErrorFeedbackMessage( "Please select a tag to delete",
        $note )
      unless ($deleteTag);

    my $changeMessage = "Tag \"$deleteTag\" is successfully deleted";
    $note = _modifyTag( $deleteTag, '', $changeMessage, $note );
    return _showDefault(status => $note);
}

# =========================
sub _wrapHtmlFeedbackMessage {
    my ( $text, $note ) = @_;
    return defined($note) && $note ne '' ?
	"<div class=\"tagMeNotification\">$text<div>$note</div></div>" :
	"<span class=\"tagMeNotification\">$text</span>";
}

# =========================
sub _wrapHtmlErrorFeedbackMessage {
    my ( $text, $note ) = @_;
    return _wrapHtmlFeedbackMessage( "<span class=\"twikiAlert\">$text</span>",
        $note );
}

# =========================
sub _wrapHtmlFeedbackInline {
    my ($text) = @_;
    return " <span class=\"tagMeNotification\">$text</span>";
}

# =========================
sub _wrapHtmlFeedbackErrorInline {
    my ($text) = @_;
    return _wrapHtmlFeedbackInline("<span class=\"twikiAlert\">$text</span>");
}

# =========================
sub _wrapHtmlTagControl {
    my ($text) = @_;
    return "<span class=\"tagMeControl\">$text</span>";
}

# =========================
sub _wrapHtmlTagMeShowForm {
    my ($text) = @_;
    return
"<form name=\"tagmeshow\" style=\"display:inline\" action=\"%SCRIPTURL{viewauth}%/%BASEWEB%/%BASETOPIC%\" method=\"post\">$text</form>";
}

# =========================
sub _htmlErrorFeedbackChangeMessage {
    my ( $changeMode, $note ) = @_;

    my $errorMessage = '%ICON{"warning"}%';
    my $op;
    if ( $changeMode =~ /^(create|rename|delete)$/ ) {
	$op = $changeMode;
    }
    else {
	$op = 'modify';
    }
    my $extraNote = '';
    if ( $inactiveSite ) {
	$errorMessage .= "You cannot $op tags since this web is read-only.";
    }
    else {
	$errorMessage .= " You are not allowed to $op tags";
	$extraNote =
"But you may use this form to post a change request to $tagChangeRequestLink";
    }
    $note = '%BR%' . $note if $note;
    $note = $extraNote . $note;
    $note .= _htmlPostChangeRequestFormField();
    return _wrapHtmlErrorFeedbackMessage( $errorMessage, $note );
}

# =========================
sub _htmlPostChangeRequestFormField {
    return '<input type="hidden" name="postChangeRequest" value="on" />';
}

# =========================
sub _urlEncode {
    my $text = shift;
    $text =~ s/([^0-9a-zA-Z-_.:~!*'()\/%])/'%'.sprintf('%02x',ord($1))/ge;
    return $text;
}

# =========================
sub _urlDecode {
    my $text = shift;
    $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;
    return $text;
}

# =========================
sub _handleMakeText {
### my( $text ) = @_; # do not uncomment, use $_[0] instead

    # for compatibility with TWiki 3
    return unless ( $TWiki::Plugins::VERSION < 1.1 );

    # very crude hack to remove MAKETEXT{"...."}
    # Note: parameters are _not_ supported!
    $_[0] =~ s/[%]MAKETEXT\{ *\"(.*?)." *}%/$1/go;
}

# =========================
sub _writeDebug {
    my ($text) = @_;
    TWiki::Func::writeDebug("- ${pluginName}: $text") if $debug;
}

# =========================
sub _writeWarning {
    my ($text) = @_;
    TWiki::Func::writeWarning("- ${pluginName}: $text");
}

# =========================
sub _writeLog {
    my ($theText) = @_;
    if ($logAction) {
        $TWiki::Plugins::SESSION
          ? $TWiki::Plugins::SESSION->writeLog( "tagme", "$web.$topic",
            $theText )
          : TWiki::Store::writeLog( "tagme", "$web.$topic", $theText );
        _writeDebug("TAGME action, $web.$topic, $theText");
    }
}

# =========================
sub _isGroupMember {
    my $group = shift;
    
    return TWiki::Func::isGroupMember ( $group, undef ) if $TWiki::Plugins::VERSION >= 1.2;
    return $TWiki::Plugins::SESSION->{user}->isInList($group);
}

# =========================
sub _isInList {
    my $list = shift; # we know it is not null

    foreach my $name ( split(/[,\s]+/, $list) ) {
        $name =~ s/(Main\.|\%MAINWEB\%\.)//go;
        return 1 if ( $name eq TWiki::Func::getWikiName(undef) );
            # user is listed
        return 1 if _isGroupMember( $name );
    }
    # this user is not in list
    return 0;
    
}

# =========================
sub _TAGMEPLUGIN_USER_AGNOSTIC {
    _initialize();
    return $userAgnostic ? 'on' : 'off';
}

# =========================
1;
