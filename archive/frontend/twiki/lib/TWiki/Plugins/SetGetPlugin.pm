# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2015 Alba Power Quality Solutions
# Copyright (C) 2015 Wave Systems Corp.
# Copyright (C) 2010-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2010-2018 TWiki Contributors
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
#
# =========================
#
# This is the TWiki SET/GET Plugin.

package TWiki::Plugins::SetGetPlugin;

# =========================
our $VERSION = '$Rev: 30472 (2018-07-16) $';
our $RELEASE = '2018-07-05';
our $SHORTDESCRIPTION = 'Set and get variables and JSON objects in topics, optionally persistently across topic views';
our $NO_PREFS_IN_TOPIC = 1;

our $web;
our $topic;
our $user;
our $installWeb;
our $debug = $TWiki::cfg{Plugins}{SetGetPlugin}{Debug};
our $core;
our $moduleLoaded = 0;

# =========================
sub initPlugin {
    ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1 ) {
        TWiki::Func::writeWarning( "Version mismatch between SetGetPlugin and Plugins.pm" );
        return 0;
    }

    TWiki::Func::registerTagHandler( 'GET',        \&_GET );
    TWiki::Func::registerTagHandler( 'SET',        \&_SET );
    TWiki::Func::registerTagHandler( 'SETGETDUMP', \&_DUMP );
    TWiki::Func::registerRESTHandler( 'get',       \&_restGet );
    TWiki::Func::registerRESTHandler( 'set',       \&_restSet );

    # check if core exists from a previous topic view (possible in mod_perl)
    if( $core ) {
        $core->initVariables();
    }

    # Plugin correctly initialized
    TWiki::Func::writeDebug( "- TWiki::Plugins::SetGetPlugin::initPlugin( $web.$topic ) is OK" ) if $debug;

    return 1;
}

# =========================
sub _DUMP {
    my ( $session, $params ) = @_;

    # Lazy loading, e.g. compile core module only when required
    unless( $core ) {
        require TWiki::Plugins::SetGetPlugin::Core;
        $core = new TWiki::Plugins::SetGetPlugin::Core();
    }
    return $core->VarDUMP( $params );
}

# =========================
sub _GET {
    my ( $session, $params ) = @_;

    # Lazy loading, e.g. compile core module only when required
    unless( $core ) {
        require TWiki::Plugins::SetGetPlugin::Core;
        $core = new TWiki::Plugins::SetGetPlugin::Core();
    }
    return $core->VarGET( $params );
}

# =========================
sub _SET {
    my ( $session, $params ) = @_;

    # Lazy loading, e.g. compile core module only when required
    unless( $core ) {
        require TWiki::Plugins::SetGetPlugin::Core;
        $core = new TWiki::Plugins::SetGetPlugin::Core();
    }
    return $core->VarSET( $params );
}

# =========================
sub _restGet {
#   my ($session) = @_;
    my $query = TWiki::Func::getCgiQuery();
    my $params;
    $params->{_DEFAULT} = $query->param('name')    if( defined $query->param('name') );
    $params->{default}  = $query->param('default') if( defined $query->param('default') );
    $params->{store}    = $query->param('store')   if( defined $query->param('store') );
    unless( $core ) {
        require TWiki::Plugins::SetGetPlugin::Core;
        $core = new TWiki::Plugins::SetGetPlugin::Core();
    }
    return $core->VarGET( $params );
}

# =========================
sub _restSet {
#   my ($session) = @_;
    my $query = TWiki::Func::getCgiQuery();
    my $params;
    $params->{_DEFAULT}  = $query->param('name')     if( defined $query->param('name') );
    $params->{value}     = $query->param('value')    if( defined $query->param('value') );
    $params->{remember}  = $query->param('remember') if( defined $query->param('remember') );
    $params->{store}     = $query->param('store')    if( defined $query->param('store') );
    unless( $core ) {
        require TWiki::Plugins::SetGetPlugin::Core;
        $core = new TWiki::Plugins::SetGetPlugin::Core();
    }
    return $core->VarSET( $params );
}

# =========================
1;
