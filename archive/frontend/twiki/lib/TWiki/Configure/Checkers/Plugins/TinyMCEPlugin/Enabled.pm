# Plugin for TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2008-2018 TWiki Contributors.
# Copyright (C) 2008-2010 Foswiki Contributors.
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

package TWiki::Configure::Checkers::Plugins::TinyMCEPlugin::Enabled;

use warnings;
use strict;

use TWiki::Configure::Checker ();
our @ISA = qw( TWiki::Configure::Checker );

sub check {
    my $this = shift;
    my $warnings;

    if ( $TWiki::cfg{Plugins}{TinyMCEPlugin}{Enabled} ) {
        if ( !$TWiki::cfg{Plugins}{JQueryPlugin}{Enabled} ) {
            $warnings .= $this->ERROR(<<'HERE');
TinyMCEPlugin depends on JQueryPlugin, which is not enabled.
HERE
        }
    }

    return $warnings;
}

1;
