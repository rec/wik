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

package TWiki::Configure::UIs::AUTH;

use strict;

use TWiki::Configure::UI;

use base 'TWiki::Configure::UI';

my %nonos = (
#    cfgAccess=>1, 
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

    # Pass URL params through, except those below
    foreach my $param ( $TWiki::query->param ) {
        next if ($nonos{$param});
        $output .= $this->hidden( $param, $TWiki::query->param( $param ));
        $output .= "\n";
    }

    $output .= CGI::hidden('newCfgP', $this->{newCfgP});
    $output .= CGI::hidden('confCfgP', $this->{ConfCfgP});
    # and add a few more
    $output .= "<div id ='twikiPassword'><div class='twikiFormSteps'>\n";

    $output .= CGI::div({ class=>'twikiFormStep' },
                       CGI::p(
                             CGI::submit(-class=>'twikiSubmit',
                                          -name=>'confirm',
                                         -value=>$actionMess)));

    if ($TWiki::cfg{Password} ne '') {
        $output .= CGI::div( { class=>'twikiFormStep' },
        	CGI::p( CGI::strong('Please click on above Save button to Save the Changes' )) .
        	CGI::p(<<'HERE'));
If you are not happy with the changes, please click on "Return to configuration" link below and start again.

HERE
    }



    return $output.CGI::end_form();
}

1;
