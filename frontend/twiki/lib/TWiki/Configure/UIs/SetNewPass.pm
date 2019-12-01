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

package TWiki::Configure::UIs::SetNewPass;

use strict;

use TWiki::Configure::UI;

use base 'TWiki::Configure::UI';

my %nonos = (
    cfgAccess=>1,
    newCfgP=>1,
    confCfgP=>1,
   );

sub ui {
    my ($this, $canChangePW, $actionMess) = @_;
    my $output = '';

    my @script = File::Spec->splitdir($ENV{SCRIPT_NAME});
    my $scriptName = pop(@script);
    $scriptName =~ s/.*[\/\\]//;  # Fix for Item3511, on Win XP

    $output .= CGI::start_form({ action=>$scriptName, method=>'post' });


        my $submitStr = $actionMess;
        $output .= CGI::div( { class=>'twikiFormStep' },
                             CGI::h3( { class=>'twikiFormStep' },
                                      'You may set a new password here:') );
        $output .= CGI::div( { class=>'twikiFormStep' },
                             CGI::strong('New Password:') .
								 CGI::p( CGI::password_field(
                                     'newCfgP', '', 20, 80 )
                                  ));
        $output .= CGI::div( { class=>'twikiFormStep' },
                             CGI::strong('Confirm Password:') .
								 CGI::p( CGI::password_field( 
                                     'confCfgP', '', 20, 80 )
                                  ));
        $submitStr = $submitStr;
        $output .= CGI::div( { class=>'twikiFormStep twikiLast' },
                             CGI::submit( 
                                  -name=>'action',
                                  -class=>'twikiSubmit',
                                  -value=>$submitStr ));
        $output .= "</div><!--/twikiFormSteps--></div><!--/twikiPasswordChange-->";

    return $output.CGI::end_form();
}

1;
