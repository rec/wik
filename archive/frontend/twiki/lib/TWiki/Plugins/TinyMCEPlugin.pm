# Plugin for TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2007-2018 Peter Thoeny and TWiki Contributors.
# Copyright (C) 2008-2012 Foswiki Contributors. 
# All Rights Reserved. TWiki Contributors are listed in the 
# AUTHORS file in the root of this distribution.
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

package TWiki::Plugins::TinyMCEPlugin;

use strict;
use warnings;

use Assert;

our $VERSION = '$Rev: 30541 (2018-07-16) $';
our $RELEASE = '2018-07-10';
our $SHORTDESCRIPTION  = 'Integration of the Tiny MCE WYSIWYG Editor';
our $NO_PREFS_IN_TOPIC = 1;

use TWiki::Func ();

our %defaultINIT_BROWSER = (
    MSIE   => '',
    OPERA  => '',
    GECKO  => '"gecko_spellcheck" : true',
    SAFARI => '',
    CHROME => '',
);
my $query;

# Info about browser type
my %browserInfo;

sub initPlugin {
    $query = TWiki::Func::getCgiQuery();
    return 0 unless $query;
    unless ( $TWiki::cfg{Plugins}{WysiwygPlugin}{Enabled} ) {
        TWiki::Func::writeWarning(
"TinyMCEPlugin is enabled but WysiwygPlugin is not. Both must be installed and enabled for TinyMCE."
        );
        return 0;
    }
    unless ( $TWiki::cfg{Plugins}{JQueryPlugin}{Enabled} ) {
        TWiki::Func::writeWarning(
"TinyMCEPlugin is enabled but JQueryPlugin is not. Both must be installed and enabled for TinyMCE."
        );
        return 0;
    }

    # Identify the browser from the user agent string
    my $ua = $query->user_agent();
    if ($ua) {
        $browserInfo{isMSIE} = $ua =~ /MSIE/;
        $browserInfo{isMSIE5}   = $browserInfo{isMSIE} && ( $ua =~ /MSIE 5/ );
        $browserInfo{isMSIE5_0} = $browserInfo{isMSIE} && ( $ua =~ /MSIE 5.0/ );
        $browserInfo{isMSIE6} = $browserInfo{isMSIE} && $ua =~ /MSIE 6/;
        $browserInfo{isMSIE7} = $browserInfo{isMSIE} && $ua =~ /MSIE 7/;
        $browserInfo{isMSIE8} = $browserInfo{isMSIE} && $ua =~ /MSIE 8/;
        $browserInfo{isGecko}  = $ua =~ /Gecko/;   # Will also be true on Safari
        $browserInfo{isSafari} = $ua =~ /Safari/;  # Will also be true on Chrome
        $browserInfo{isOpera}  = $ua =~ /Opera/;
        $browserInfo{isChrome} = $ua =~ /Chrome/;
        $browserInfo{isMac}    = $ua =~ /Mac/;
        $browserInfo{isNS7}  = $ua =~ /Netscape\/7/;
        $browserInfo{isNS71} = $ua =~ /Netscape\/7.1/;
    }

    my $disable = TWiki::Func::getPreferencesValue('TINYMCEPLUGIN_DISABLE');
    my $available = 1;
    if ( $disable ) {
        if ( $disable =~ /%/ ) {
            $disable = TWiki::Func::expandCommonVariables($disable);
        }
        if ( TWiki::Func::isTrue($disable) ) {
            $available = 0;
        }
    }
    TWiki::Func::getContext()->{TinyMCEPluginAvailable} = $available;

    return 1;
}

sub _notAvailable {
    for my $c (qw(TINYMCEPLUGIN_DISABLE NOWYSIWYG)) {
        return "Disabled by * Set $c = "
          . TWiki::Func::getPreferencesValue($c)
          if TWiki::Func::getPreferencesFlag($c);
    }

    # Disable TinyMCE if we are on a specialised edit skin
    my $skin = TWiki::Func::getPreferencesValue('WYSIWYGPLUGIN_WYSIWYGSKIN');
    return "$skin is active"
      if ( $skin && TWiki::Func::getSkin() =~ /\b$skin\b/o );

    return "No browser" unless $query;

    return "Disabled by URL parameter" if $query->param('nowysiwyg');

    # Check the client browser to see if it is blacklisted
    my $ua = TWiki::Func::getPreferencesValue('TINYMCEPLUGIN_BAD_BROWSERS')
      || '(?i-xsm:Konqueror)';
    return 'Unsupported browser: ' . $query->user_agent()
      if $ua && $query->user_agent() && $query->user_agent() =~ /$ua/;

    return 0;
}

sub beforeEditHandler {
    my ( $text, $topic, $web ) = @_;

    my $mess = _notAvailable();
    if ($mess) {
        if ( ( $mess !~ /^Disabled/ || DEBUG )
            && defined &TWiki::Func::setPreferencesValue )
        {
            TWiki::Func::setPreferencesValue( 'EDITOR_MESSAGE',
                'WYSIWYG could not be started: ' . $mess );
        }
        return;
    }
    if ( defined &TWiki::Func::setPreferencesValue ) {
        TWiki::Func::setPreferencesValue( 'EDITOR_HELP', 'TinyMCEQuickHelp' );
    }

    my $initTopic =
      TWiki::Func::getPreferencesValue('TINYMCEPLUGIN_INIT_TOPIC')
      || $TWiki::cfg{SystemWebName} . '.TinyMCEPlugin';
    my $init = TWiki::Func::getPreferencesValue('TINYMCEPLUGIN_INIT')
      || TWiki::Func::expandCommonVariables(
        '%INCLUDE{"'
          . $initTopic
          . '" section="TINYMCEPLUGIN_INIT" warn="off"}%',
        $topic, $web
      );
    my $browser = '';

    # The order of these conditions is important, because browsers
    # spoof eachother
    if ( $browserInfo{isChrome} ) {
        $browser = 'CHROME';
    }
    elsif ( $browserInfo{isSafari} ) {
        $browser = 'SAFARI';
    }
    elsif ( $browserInfo{isOpera} ) {
        $browser = 'OPERA';
    }
    elsif ( $browserInfo{isGecko} ) {
        $browser = 'GECKO';
    }
    elsif ( $browserInfo{isMSIE} ) {
        $browser = 'MSIE';
    }
    if ($browser) {
        my $settings =
          TWiki::Func::getPreferencesValue( 'TINYMCEPLUGIN_INIT_' . $browser )
          || $defaultINIT_BROWSER{$browser};
        if ($settings) {
            $init =
              join( ',', ( split( ',', $init ), split( ',', $settings ) ) );
        }
    }

    require TWiki::Plugins::WysiwygPlugin;

    $mess = TWiki::Plugins::WysiwygPlugin::notWysiwygEditable($text);
    if ($mess) {
        if ( defined &TWiki::Func::setPreferencesValue ) {
            TWiki::Func::setPreferencesValue( 'EDITOR_MESSAGE',
                'WYSIWYG could not be started: ' . $mess );
            TWiki::Func::setPreferencesValue( 'EDITOR_HELP', undef );
        }
        return;
    }

    my $USE_SRC = '';
    if ( TWiki::Func::getPreferencesValue('TINYMCEPLUGIN_DEBUG') ) {
        $USE_SRC = '_src';
    }

    # Add the Javascript for the editor. When it starts up the editor will
    # use a REST call to the WysiwygPlugin tml2html REST handler to convert
    # the textarea content from TML to HTML.
    my $pluginURL = '%PUBURLPATH%/%SYSTEMWEB%/TinyMCEPlugin';
    my $tmceURL   = $pluginURL . '/tinymce/jscripts/tiny_mce';

    # URL-encode the version number to include in the .js URLs, so that
    # the browser re-fetches the .js when this plugin is upgraded.
    my $encodedVersion = $VERSION;

    # SMELL: This regex (and the one applied to $metainit, above)
    # duplicates TWiki::urlEncode(), but TWiki::Func.pm does not
    # expose that function, so plugins may not use it
    $encodedVersion =~
      s/([^0-9a-zA-Z-_.:~!*'\/%])/'%'.sprintf('%02x',ord($1))/ge;

    # Inline JS to set config? Heresy! Well, we were encoding into <meta tags
    # but this caused problems with non-8bit encodings (See Item9973). Given
    # that we blindly eval'd the unescaped TINYMCEPLUGIN_INIT anyway, PaulHarvey
    # doesn't think it was any more secure anyway. Alternative is to use
    # https://github.com/douglascrockford/JSON-js lib
    my $scripts = <<"SCRIPT";
<script type="text/javascript" src="$tmceURL/tiny_mce$USE_SRC.js?v=$encodedVersion"></script>
<script type="text/javascript" src="$pluginURL/twiki_tiny$USE_SRC.js?v=$encodedVersion"></script>
<script type="text/javascript">
TWikiTiny.init = {
  $init
};</script>
<script type="text/javascript" src="$pluginURL/twiki$USE_SRC.js?v=$encodedVersion"></script>
SCRIPT

    TWiki::Func::addToHEAD( 'TinyMCEPlugin', $scripts );

    # See %SYSTEMWEB%.IfStatements for a description of this context id.
    TWiki::Func::getContext()->{textareas_hijacked} = 1;

    return;
}

1;
