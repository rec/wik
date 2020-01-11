# Plugin for TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2005-2018 Peter Thoeny and TWiki Contributors.
# Copyright (C) 2005 ILOG http://www.ilog.fr
# Copyright (C) 2008-2012 Foswiki Contributors.
# All Rights Reserved. TWiki Contributors are listed in the 
# AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of the TWiki distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

=begin twiki

---+ package WysiwygPlugin

This plugin is responsible for translating TML to HTML before an edit starts
and translating the resultant HTML back into TML.

Note: In the case of a new topic, you might expect to see the "create topic"
screen in the editor when it goes back to TWiki for the topic content. This
doesn't happen because the earliest possible handler is called on the topic
content and not the template. The template is effectively ignored and a blank
document is sent to the editor.

Attachment uploads can be handled by URL requests from the editor to the rest
handler in this plugin. This avoids the need to add any scripts to the bin dir.
You will have to use a form, though, as XmlHttpRequest does not support file
uploads.

=cut

package TWiki::Plugins::WysiwygPlugin;

use strict;
use warnings;

use Assert;

our $SHORTDESCRIPTION  = 'Translator framework for WYSIWYG editors';
our $NO_PREFS_IN_TOPIC = 1;

our $VERSION = '$Rev: 30528 (2018-07-16) $';
our $RELEASE = '2018-07-06';

our %xmltag;

# The following are all used in Handlers, but declared here so we can
# check them without loading the handlers module
our $tml2html;
our $recursionBlock;
our %TWikiCompatibility;

# Set to 1 for reasons for rejection
sub WHY { 0 }

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # %OWEB%.%OTOPIC% is the topic where the initial content should be
    # grabbed from, as defined in templates/edit.skin.tmpl
    # Note; rather than declaring the handlers in this module, we use
    # the _execute function to hand off execution to
    # TWiki::Plugins::WysiwygPlugin::Handlers. The goal is to keep this
    # module small and light so it loads fast.
    TWiki::Func::registerTagHandler( 'OWEB',
        sub { _execute( '_OWEBTAG', @_ ) } );
    TWiki::Func::registerTagHandler( 'OTOPIC',
        sub { _execute( '_OTOPICTAG', @_ ) } );
    TWiki::Func::registerTagHandler( 'WYSIWYG_TEXT',
        sub { _execute( '_WYSIWYG_TEXT', @_ ) } );
    TWiki::Func::registerTagHandler( 'JAVASCRIPT_TEXT',
        sub { _execute( '_JAVASCRIPT_TEXT', @_ ) } );
    TWiki::Func::registerTagHandler( 'WYSIWYG_SECRET_ID',
        sub { _execute( '_SECRET_ID', @_ ) } );

    TWiki::Func::registerRESTHandler( 'tml2html',
        sub { _execute( '_restTML2HTML', @_ ) } );
    TWiki::Func::registerRESTHandler( 'html2tml',
        sub { _execute( '_restHTML2TML', @_ ) } );
    TWiki::Func::registerRESTHandler( 'upload',
        sub { _execute( '_restUpload', @_ ) } );
    TWiki::Func::registerRESTHandler( 'attachments',
        sub { _execute( '_restAttachments', @_ ) } );

    # Plugin correctly initialized
    return 1;
}

sub _execute {
    my $fn = shift;

    require TWiki::Plugins::WysiwygPlugin::Handlers;
    $fn = 'TWiki::Plugins::WysiwygPlugin::Handlers::' . $fn;
    no strict 'refs';
    return &$fn(@_);
    use strict 'refs';
}

=begin twiki

---++ StaticMethod notWysiwygEditable($text) -> $boolean
Determine if the given =$text= is WYSIWYG editable, based on the topic content
and the value of the TWiki preferences WYSIWYG_EXCLUDE and
WYSIWYG_EDITABLE_CALLS. Returns a descriptive string if the text is not
editable, 0 otherwise.

=cut

sub notWysiwygEditable {

    #my ($text, $exclusions) = @_;
    my $disabled = wysiwygEditingDisabledForThisContent( $_[0], $_[1] );
    return $disabled if $disabled;

    # Check that the topic text can be converted to HTML. This is an
    # *expensive* process, to be avoided if possible (hence all the
    # earlier checks)
    my $impossible = wysiwygEditingNotPossibleForThisContent( $_[0] );
    return $impossible if $impossible;

    return 0;
}

sub wysiwygEditingDisabledForThisContent {

    #my ($text, $exclusions) = @_;

    my $exclusions = $_[1];
    unless ( defined($exclusions) ) {
        $exclusions = TWiki::Func::getPreferencesValue('WYSIWYG_EXCLUDE')
          || '';
    }

    # Check for explicit exclusions before generic, non-configurable
    # purely content-related reasons for exclusion
    if ($exclusions) {
        my $calls_ok =
          TWiki::Func::getPreferencesValue('WYSIWYG_EDITABLE_CALLS')
          || '---';
        $calls_ok =~ s/\s//g;

        my $ok = 1;
        if (   $exclusions =~ /calls/
            && $_[0] =~ /%((?!($calls_ok){)[A-Z_]+{.*?})%/s )
        {
            print STDERR "WYSIWYG_DEBUG: has calls $1 (not in $calls_ok)\n"
              if (WHY);
            return "Text contains calls";
        }
        if ( $exclusions =~ /(macros|variables)/ && $_[0] =~ /%([A-Z_]+)%/s ) {
            print STDERR "$exclusions WYSIWYG_DEBUG: has variables $1\n"
              if (WHY);
            return "Text contains variables";
        }
        if (   $exclusions =~ /html/
            && $_[0] =~ /<\/?((?!literal|verbatim|noautolink|nop|br)\w+)/i )
        {
            print STDERR "WYSIWYG_DEBUG: has html: $1\n"
              if (WHY);
            return "Text contains HTML";
        }
        if ( $exclusions =~ /comments/ && $_[0] =~ /<[!]--/ ) {
            print STDERR "WYSIWYG_DEBUG: has comments\n"
              if (WHY);
            return "Text contains comments";
        }
        if ( $exclusions =~ /pre/ && $_[0] =~ /<pre\w/i ) {
            print STDERR "WYSIWYG_DEBUG: has pre\n"
              if (WHY);
            return "Text contains PRE";
        }
        if ( $exclusions =~ /script/ && $_[0] =~ /<script\W/i ) {
            print STDERR "WYSIWYG_DEBUG: has script\n"
              if (WHY);
            return "Text contains script";
        }
        if ( $exclusions =~ /style/ && $_[0] =~ /<style\W/i ) {
            print STDERR "WYSIWYG_DEBUG: has style\n"
              if (WHY);
            return "Text contains style";
        }
        if ( $exclusions =~ /table/ && $_[0] =~ /<table\W/i ) {
            print STDERR "WYSIWYG_DEBUG: has table\n"
              if (WHY);
            return "Text contains table";
        }
    }

    # SMELL: Item7594 hack to disable WYSIWYG editor if |>> ... <<| table syntax is used.
    # FIXME: The TML2HTML and HTML2TML need to be enhanced to handle TML in table syntax.
    if( $_[0] =~ /\|>>.*?<<\|/s ) {
        print STDERR "WYSIWYG_DEBUG: has table with |>> ... <<| cells\n"
          if (WHY);
        return "Text contains table with |&gt;&gt;&gt; ... &lt;&lt;| cells"
    }

    # Copy the content.
    # Then crunch verbatim blocks, because verbatim blocks may
    # contain *anything*.
    my $text = $_[0];

    # Look for combinations of sticky and other markup that cause
    # problems together
    for my $tag ('literal') {
        while ( $text =~ /<$tag\b[^>]*>(.*?)<\/$tag>/gsi ) {
            my $inner = $1;
            if ( $inner =~ /<sticky\b[^>]*>/i ) {
                print STDERR "WYSIWYG_DEBUG: <sticky> inside <$tag>\n"
                  if (WHY);
                return "&lt;sticky&gt; inside &lt;$tag&gt;";
            }
        }
    }

    my $wasAVerbatimTag = "\000verbatim\001";
    while ( $text =~ s/<verbatim\b[^>]*>(.*?)<\/verbatim>/$wasAVerbatimTag/i ) {

        #my $content = $1;
        # If there is any content that breaks conversion if it is inside
        # a verbatim block, check for it here:
    }

    # Look for combinations of verbatim and other markup that cause
    # problems together
    for my $tag ('literal') {
        while ( $text =~ /<$tag\b[^>]*>(.*?)<\/$tag>/gsi ) {
            my $inner = $1;
            if ( $inner =~ /$wasAVerbatimTag/i ) {
                print STDERR "WYSIWYG_DEBUG: <verbatim> inside <$tag>\n"
                  if (WHY);
                return "&lt;verbatim&gt; inside &lt;$tag&gt;";
            }
        }
    }

    return 0;
}

sub wysiwygEditingNotPossibleForThisContent {
    eval {
        require TWiki::Plugins::WysiwygPlugin::Handlers;
        TWiki::Plugins::WysiwygPlugin::Handlers::TranslateTML2HTML( $_[0],
            'Fakewebname', 'FakeTopicName', dieOnError => 1 );
    };
    if ($@) {
        print STDERR
          "WYSIWYG_DEBUG: TML2HTML conversion threw an exception: $@\n"
          if (WHY);
        return "TML2HTML conversion fails";
    }

    return 0;
}

sub addXMLTag {
    require TWiki::Plugins::WysiwygPlugin::Handlers;
    TWiki::Plugins::WysiwygPlugin::Handlers::addXMLTag(@_);
}

sub postConvertURL {
    require TWiki::Plugins::WysiwygPlugin::Handlers;
    TWiki::Plugins::WysiwygPlugin::Handlers::postConvertURL(@_);
}

sub beforeEditHandler {
    _execute( 'beforeEditHandler', @_ );
}

sub beforeSaveHandler {
    _execute( 'beforeSaveHandler', @_ );
}

sub beforeMergeHandler {
    _execute( 'beforeMergeHandler', @_ );
}

sub afterEditHandler {
    _execute( 'afterEditHandler', @_ );
}

# The next few handlers have to be executed on topic views, so have to
# avoid lazy-loading the handlers unless absolutely necessary.

$TWikiCompatibility{startRenderingHandler} = 2.1;

sub startRenderingHandler {
    $_[0] =~ s#</?sticky>##g;
}

sub beforeCommonTagsHandler {
    return if $recursionBlock;
    return unless TWiki::Func::getContext()->{body_text};

    my $query = TWiki::Func::getCgiQuery();

    return unless $query;

    return unless defined( $query->param('wysiwyg_edit') );
    _execute( 'beforeCommonTagsHandler', @_ );
}

sub postRenderingHandler {
    return if ( $recursionBlock || !$tml2html );
    _execute( 'postRenderingHandler', @_ );
}

sub modifyHeaderHandler {
    my ( $headers, $query ) = @_;

    if ( $query->param('wysiwyg_edit') ) {
        _execute( 'modifyHeaderHandler', @_ );
    }
}

1;
