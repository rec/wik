# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2016-2018 Peter Thoeny, peter[at]thoeny.org 
# Copyright (C) 2016-2018 TWiki Contributors. All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# As per the GPL, removal of this notice is prohibited.

package TWiki::Plugins::TWikiSheetPlugin;

# =========================
our $VERSION = '$Rev: 30604 (2018-07-16) $';
our $RELEASE = '2018-07-15';
our $SHORTDESCRIPTION = 'Add TWiki Sheet spreadsheet functionality to TWiki tables';
our $NO_PREFS_IN_TOPIC = 1;

# =========================
our $debug = $TWiki::cfg{Plugins}{TWikiSheetPlugin}{Debug} || 0;
our $web;
our $topic;
our $core;

# =========================
sub initPlugin {
    ( $topic, $web ) = @_;

    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1.2 ) {
        TWiki::Func::writeWarning( "Version mismatch between TWikiSheetPlugin and Plugins.pm" );
        return 0;
    }

    ##TWiki::Func::registerTagHandler( 'TWIKISHEET', \&_TWIKISHEET );
    TWiki::Func::registerRESTHandler( 'get', \&_restGetTable );
    TWiki::Func::registerRESTHandler( 'save', \&_restSaveTable );

    $core = undef;

    # Plugin correctly initialized
    TWiki::Func::writeDebug( "- TWiki::Plugins::TWikiSheetPlugin::initPlugin( $web.$topic ) is OK" )
      if( $debug );

    return 1;
}

# =========================
sub beforeCommonTagsHandler {
    return unless $_[0] =~ /\%TWIKISHEET\{.*?}%/os;
    unless( $core ) {
        require TWiki::Plugins::TWikiSheetPlugin::Core;
        $core = new TWiki::Plugins::TWikiSheetPlugin::Core( "$web.$topic" );
    }
    $core->protectVariables( @_ );
}

# =========================
sub commonTagsHandler {
    return unless $_[0] =~ /\%TWIKISHEET\{.*?}%/os;
    unless( $core ) {
        require TWiki::Plugins::TWikiSheetPlugin::Core;
        $core = new TWiki::Plugins::TWikiSheetPlugin::Core( "$web.$topic" );
    }
    $core->processText( @_ );
}

# =========================
sub _restGetTable {
#   my ($session) = @_;
    my $query = TWiki::Func::getCgiQuery();
    unless( $core ) {
        require TWiki::Plugins::TWikiSheetPlugin::Core;
        $core = new TWiki::Plugins::TWikiSheetPlugin::Core( "$web.$topic" );
    }
    return $core->restGetTable( $query );
}

# =========================
sub _restSaveTable {
#   my ($session) = @_;
    my $query = TWiki::Func::getCgiQuery();
    unless( $query->request_method() eq 'POST' ) {
        return '{ error: 1, message: "Only http POST method allowed" }';
    }
    unless( $core ) {
        require TWiki::Plugins::TWikiSheetPlugin::Core;
        $core = new TWiki::Plugins::TWikiSheetPlugin::Core( "$web.$topic" );
    }
    return $core->restSaveTable( $query );
}

# =========================
1;
