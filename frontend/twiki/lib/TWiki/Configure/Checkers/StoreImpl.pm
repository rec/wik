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

package TWiki::Configure::Checkers::StoreImpl;

use strict;

use TWiki::Configure::Checker;

use base 'TWiki::Configure::Checker';

sub check {
    my $this = shift;

    my $mess = '';
    if( $TWiki::cfg{StoreImpl} eq 'RcsWrap') {
        # Check that GNU diff is found in PATH; used by rcsdiff
        $mess .= $this->checkGnuProgram('diff');
        # Check all the RCS programs
        $mess .= $this->checkRCSProgram('initBinaryCmd');
        $mess .= $this->checkRCSProgram('initTextCmd');
        $mess .= $this->checkRCSProgram('tmpBinaryCmd');
        $mess .= $this->checkRCSProgram('ciCmd');
        $mess .= $this->checkRCSProgram('ciDateCmd');
        $mess .= $this->checkRCSProgram('coCmd');
        $mess .= $this->checkRCSProgram('histCmd');
        $mess .= $this->checkRCSProgram('infoCmd');
        $mess .= $this->checkRCSProgram('histCmd');
        $mess .= $this->checkRCSProgram('diffCmd');
        $mess .= $this->checkRCSProgram('lockCmd');
        $mess .= $this->checkRCSProgram('unlockCmd');
        $mess .= $this->checkRCSProgram('delRevCmd');
    }

    return $mess;
};

1;
