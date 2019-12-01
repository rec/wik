# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2011-2016 Timothe Litt <litt at acm dot org>
# Copyright (C) 2011-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
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
# As per the GPL, removal of this notice is prohibited.
#
# This is an original work by Timothe Litt.
#
# TWiki off-line task management framework addon
# -*- mode: CPerl; -*-

use strict;
use warnings;

package TWiki::Configure::Checkers::Certificate::ClientChecker;

use base 'TWiki::Configure::Checkers::Certificate';

sub check {
    my $this = shift;

    return $this->checkUsage( shift, 'client' );
}

1;
