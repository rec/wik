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

package TWiki::Configure::Checkers::MSWin32;

use strict;

sub check {
    my $this = shift;
    # ActivePerl-only function: returns number if
    # successful, otherwise treated as a literal (bareword).
    my $isActivePerl= eval 'Win32::BuildNumber !~ /Win32/';

    # FIXME: Advice in this section should be reviewed and tested by people
    # using ActivePerl
    my $perl5shell = $ENV{PERL5SHELL} || '';
    my $n = $perl5shell.
      $this->NOTE(<<HERE);
This environment variable is used by Win32 Perls to run
commands from TWiki scripts - it determines which shell program is used to run
commands that use 'pipes'.  Examples of shell programs are cmd.exe,
command.com (aka 'DOS Prompt'), and Cygwin's 'bash'
(<strong>recommended</strong> if Cygwin is installed).
<p>
To use 'bash' with ActiveState or other Win32 Perl you should set the
PERL5SHELL environment variable to something like
<tt><strong>c:/YOURCYGWINDIR/bin/bash.exe -c</strong></tt>
This should be set in the System Environment, and ideally set directly in the
web server (e.g. using the Apache <tt>SetEnv</tt> directive).
HERE

    if( $isActivePerl ) {
        $n .= $this->WARN(<<HERE);
ActiveState Perl on IIS does not support safe pipes, which is the mechanism used by TWiki to prevent a range
of attacks aimed at arbitrary command execution on the server. You are <b>highly</b> recommended not to use this
particular configuration on a public server (one exposed to the internet)
HERE
        if( Win32::BuildNumber() < 631 ) {
            $n .= $this->WARN(<<HERE);
ActiveState Perl must be upgraded to at least build 631
if you are going to use PERL5SHELL, which was broken in earlier builds.
HERE
        }
    }
    return $n;
}

1;
