# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
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

package TWiki::Configure::Checkers::DispScriptUrlPath;

use strict;

use TWiki::Configure::Checker;

use base 'TWiki::Configure::Checker';

sub check {
    my $this = shift;

    # Check Script URL Path against REQUEST_URI
    my $n;
    my $val = $TWiki::cfg{DispScriptUrlPath};
    my $guess = $ENV{REQUEST_URI} || $ENV{SCRIPT_NAME} || '';
    $guess =~ s(/+configure[^/]*$)();

    if( !defined($val) || $val eq 'NOT SET' ) {
        $TWiki::cfg{DispScriptUrlPath} = $TWiki::cfg{ScriptUrlPath};
        return $this->guessed(0);
    }
    return '';
}

1;
