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

package TWiki::Configure::Types::OCTAL;

use strict;

use TWiki::Configure::Types::NUMBER;

use base 'TWiki::Configure::Types::NUMBER';

sub prompt {
    my( $this, $id, $opts, $value ) = @_;
    return CGI::textfield( -name => $id, -size => 20,
                           -default => sprintf('0%o', $value) );
}

sub string2value {
    my ($this, $val) = @_;
    $val ||= 0;
    $val = '0'.$val unless $val =~ /^0/;
    $val =~ /(\d+)/; $val = $1; # protect the eval, just in case
    # Use eval to force octal-decimal conversion (Item3529)
    eval "\$val = $val";
    return $val;
}

1;
