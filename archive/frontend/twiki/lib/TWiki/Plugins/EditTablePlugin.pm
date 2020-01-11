# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2008 Arthur Clemens, arthur@visiblearea.com
# Copyright (C) 2002-2018 Peter Thoeny, peter[at]thoeny.org and TWiki
# Contributors.
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
#
# This is the EditTablePlugin used to edit tables in place.

package TWiki::Plugins::EditTablePlugin;

use strict;

our $VERSION = '$Rev: 30448 (2018-07-16) $';
our $RELEASE = '2018-07-05';

our $web;
our $topic;
our $user;
our $debug = 0;
our $usesJavascriptInterface = 0;
our $viewModeHeaderDone = 0;
our $editModeHeaderDone = 0;
our $prefsInitialized = 0;
our %editMode    = ( 'NONE', 0, 'EDIT', 1 );
our %saveMode    = ( 'NONE', 0, 'SAVE', 1, 'SAVEQUIET', 2 );
our $ASSET_URL   = '%PUBURL%/%SYSTEMWEB%/EditTablePlugin';

sub initPlugin {
    ( $topic, $web, $user ) = @_;

    # check for Plugins.pm versions
    if ( $TWiki::Plugins::VERSION < 1.026 ) {
        TWiki::Func::writeWarning(
            "Version mismatch between EditTablePlugin and Plugins.pm");
        return 0;
    }

    # disable plugin unless in cgi mode
    return 0 unless( TWiki::Func::getCgiQuery() );

    # Get plugin debug flag
    $debug = TWiki::Func::getPreferencesFlag('EDITTABLEPLUGIN_DEBUG');
    $usesJavascriptInterface =
      TWiki::Func::getPreferencesFlag('EDITTABLEPLUGIN_JAVASCRIPTINTERFACE');
    $viewModeHeaderDone = 0;
    $editModeHeaderDone = 0;
    $prefsInitialized   = 0;

    # Plugin correctly initialized
    TWiki::Func::writeDebug(
        "- TWiki::Plugins::EditTablePlugin::initPlugin( $web.$topic ) is OK")
      if $debug;

    return 1;
}

sub beforeCommonTagsHandler {
    return unless $_[0] =~ /%EDIT(TABLE|CELL)\{(.*)}%/os;
    require TWiki::Plugins::EditTablePlugin::Core;
    TWiki::Plugins::EditTablePlugin::Core::protectVariables(
        $_[0] );
}

sub commonTagsHandler {
    return unless $_[0] =~ /%EDIT(TABLE|CELL)\{(.*)}%/os;

    addViewModeHeadersToHead();
    require TWiki::Plugins::EditTablePlugin::Core;
    TWiki::Plugins::EditTablePlugin::Core::process( $_[0], $_[1], $_[2], $topic,
        $web );
}

=pod

Style sheet for table in view mode

=cut

sub addViewModeHeadersToHead {
    return if $viewModeHeaderDone;

    $viewModeHeaderDone = 1;

    my $header = <<'EOF';
<style type="text/css" media="all">
@import url("%PUBURL%/%SYSTEMWEB%/EditTablePlugin/edittable.css");
</style>
EOF
    TWiki::Func::addToHEAD( 'EDITTABLEPLUGIN', $header );
}

=pod

Style sheet and javascript for table in edit mode

=cut

sub addEditModeHeadersToHead {
    my ( $tableNr, $paramJavascriptInterface, $theTopic ) = @_;
    return if $editModeHeaderDone;
    return
      if !$usesJavascriptInterface && ( $paramJavascriptInterface ne 'on' );

    require TWiki::Contrib::BehaviourContrib;
    TWiki::Contrib::BehaviourContrib::addHEAD();

    $editModeHeaderDone = 1;

    my $formName = "${theTopic}edittable$tableNr";
    my $header   = "";
    $header .=
      '<meta name="EDITTABLEPLUGIN_FormName" content="' . $formName . '" />';
    $header .= "\n"
      . '<meta name="EDITTABLEPLUGIN_EditTableUrl" content="'
      . $ASSET_URL . '" />';
    $header .= <<'EOF';
<style type="text/css" media="all">
@import url("%PUBURL%/%SYSTEMWEB%/EditTablePlugin/edittable.css");
</style>
<script type="text/javascript" src="%PUBURL%/%SYSTEMWEB%/EditTablePlugin/edittable.js"></script>
EOF

    TWiki::Func::addToHEAD( 'EDITTABLEPLUGIN', $header );
}

sub addJavaScriptInterfaceDisabledToHead {
    my ($tableNr) = @_;

    my $tableId = "edittable$tableNr";
    my $header  = "";
    $header .=
'<meta name="EDITTABLEPLUGIN_NO_JAVASCRIPTINTERFACE_EditTableId" content="'
      . $tableId . '" />';
    $header .= "\n";
    TWiki::Func::addToHEAD( 'EDITTABLEPLUGIN_NO_JAVASCRIPTINTERFACE', $header );
}

sub addHeaderAndFooterCountToHead {
    my ( $headerCount, $footerCount ) = @_;
    my $header = "";
    $header .= '<meta name="EDITTABLEPLUGIN_headerRows" content="'
      . $headerCount . '" />';
    $header .= "\n";
    $header .= '<meta name="EDITTABLEPLUGIN_footerRows" content="'
      . $footerCount . '" />';
    $header .= "\n";
    TWiki::Func::addToHEAD( 'EDITTABLEPLUGIN_HEADERFOOTERCOUNT', $header );
}

1;
