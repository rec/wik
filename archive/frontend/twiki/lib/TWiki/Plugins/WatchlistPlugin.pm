# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2013-2015 Wave Systems Corp.
# Copyright (C) 2013-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2013-2018 TWiki Contributors
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

package TWiki::Plugins::WatchlistPlugin;

use warnings;
use strict;

use TWiki::Func;

# =========================
our $VERSION = '$Rev: 30536 (2018-07-16) $';
our $RELEASE = '2018-07-10';
our $SHORTDESCRIPTION =
  'Watch topics of interest and get notified of changes by e-mail';
our $NO_PREFS_IN_TOPIC = 1;

# =========================
my $debug = $TWiki::cfg{Plugins}{WatchlistPlugin}{Debug} || 0;
my $core;
my $baseWeb;
my $baseTopic;
our $AUTOLOAD;

# Handlers defined in Core:: that are registered with TWiki for this plugin.
# Do not list un-registered functions (e.g. Tag or REST handlers); they are
# autoloaded on demand.
my @handlers = qw/beforeSaveHandler afterSaveHandler afterRenameHandler/;

# =========================
sub initPlugin {
    ( $baseTopic, $baseWeb ) = @_;

    # check for Plugins.pm versions
    if ( $TWiki::Plugins::VERSION < 1.2 ) {
        TWiki::Func::writeWarning(
            "Version mismatch between WatchlistPlugin and Plugins.pm");
        return 0;
    }

    $core = undef;
    TWiki::Func::registerTagHandler( 'WATCHLIST', \&VarWATCHLIST );

    # Register plugin handlers (must be defined to be called)
    # When called, the corresponding Core:: method will be invoked.

    foreach my $handler (@handlers) {
        no strict 'refs';
        *{ __PACKAGE__ . "::$handler" } = sub {
            unless ($core) {
                require TWiki::Plugins::WatchlistPlugin::Core;
                $core = TWiki::Plugins::WatchlistPlugin::Core->new( $baseWeb,
                    $baseTopic );
                $core->processAction;
            }
            unshift @_, $core;
            goto &{ __PACKAGE__ . "::Core::$handler" };
          }
          unless ( defined &{ __PACKAGE__ . "::$handler" } );
    }

    # Plugin correctly initialized
    TWiki::Func::writeDebug(
        "- WatchlistPlugin: initPlugin( " . "$baseWeb.$baseTopic ) is OK" )
      if $debug;

    return 1;
}

# Non-handler functions aren't predefined.
# Instead, autoload on demand.

# =========================
sub AUTOLOAD {
    our $AUTOLOAD;

    unless ($core) {
        require TWiki::Plugins::WatchlistPlugin::Core;
        $core =
          TWiki::Plugins::WatchlistPlugin::Core->new( $baseWeb, $baseTopic );
        $core->processAction;
    }

    my $method = $AUTOLOAD;
    $method =~ s/^.*:://;
    $method = $core->can($method);

    confess("WatchlistPlugin: $AUTOLOAD is not implemented") unless ($method);

    unshift @_, $core;
    goto &$method;
}

1;
