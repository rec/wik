# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2011-2018 Peter Thoeny, peter[at]thoeny.org
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
# For licensing info read LICENSE file in the TWiki root.

package TWiki::Plugins::BackupRestorePlugin;

use strict;

require TWiki::Func;    # The plugins API
require TWiki::Plugins; # For the API version

#==================================================================
our $VERSION = '$Rev: 30551 (2018-07-16) $';
our $RELEASE = '2018-07-10';
our $SHORTDESCRIPTION = 'Administrator utility to backup, restore and upgrade a TWiki site';
our $NO_PREFS_IN_TOPIC = 1;

my $baseTopic;
my $baseWeb;
my $core;
my $useRegisterTagHandler;

#==================================================================
sub initPlugin {
    ( $baseTopic, $baseWeb ) = @_;

    $core = undef;
    $useRegisterTagHandler = exists( &TWiki::Func::registerTagHandler );
    if( $useRegisterTagHandler ) {
        TWiki::Func::registerTagHandler( 'BACKUPRESTORE', \&_BACKUPRESTORE );
    }
    # Plugin correctly initialized
    return 1;
}

#==================================================================
sub commonTagsHandler
{
### my ( $text, $topic, $web ) = @_;   # do not uncomment, use $_[0], $_[1]... instead

    return if( $useRegisterTagHandler );

    $_[0] =~ s/\%BACKUPRESTORE\{(.*?)\}\%/_handleBACKUPRESTORE( $1 )/ges;
}

#==================================================================
sub _handleBACKUPRESTORE {
    my( $text ) = @_;

    my $session;
    my $action = TWiki::Func::extractNameValuePair( $text, 'action' );
    my $file   = TWiki::Func::extractNameValuePair( $text, 'file' );

    my $params = {
        action => $action,
        file   => $file,
    };
    return _BACKUPRESTORE( $session, $params );
}

#==================================================================
sub _BACKUPRESTORE {
    my( $session, $params ) = @_;

    # delay loading core module until run-time
    unless( $core ) {
        my $type = 'cgi';
        if( $session && $session->can( 'inContext' ) ) {
            $type = 'cli' if( $session->inContext( 'command_line' ) );
        } elsif( ! $ENV{GATEWAY_INTERFACE} && ! $ENV{MOD_PERL} ) {
            $type = 'cli';
        }
        require TWiki::Plugins::BackupRestorePlugin::Core;
        my $cfg = {
          BaseTopic  => $baseTopic,
          BaseWeb    => $baseWeb,
          ScriptType => $type,
        };
        $core = new TWiki::Plugins::BackupRestorePlugin::Core( $cfg );
    }
    my $query = TWiki::Func::getCgiQuery();
    foreach my $key ( $query->param ) {
        next if( defined $params->{$key} );
        $params->{$key} = $query->param( $key );
    }
    return $core->BACKUPRESTORE( $params );
}

#==================================================================
1;
