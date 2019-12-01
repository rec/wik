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

package TWiki::Configure::Types::REGEX;

use strict;

use TWiki::Configure::Types::STRING;

use base 'TWiki::Configure::Types::STRING';

# TWikibug:Item7067: Configure adds extra (?^:) to regex variables
# on save under Perl 5.14. This needs to be cleaned up.
# SMELL: Regex cleanup needs to be done on 3 places:
#    * Here in sub string2value,
#    * Here in sub equals,
#    * TWiki::Configure::Valuer in sub _getValue.

sub prompt {
    my( $this, $id, $opts, $value ) = @_;
    $value = '' unless defined($value);
    $value = "$value";

    # Disabling this because the value should not appears changed in the authorise screen
    # while ( $value =~ s/^\(\?-xism:(.*)\)$/$1/ ) { }
    # while ( $value =~ s/^\(\?\^:(.*)\)/$1/ )     { }
    # $value =~ s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|])/'&#'.ord($1).';'/ge;

    $value =~ s/(['"&<>])/'&#'.ord($1).';'/ge; # escape basic chars for input field

    my $res = '<input name="'.$id.'" type="text" size="55%" value="'.$value.'" />';
    return $res;
}

sub string2value {
    my ($this, $value) = @_;
    while ( $value =~ s/^\(\?-xism:(.*)\)$/$1/ ) { }
    while ( $value =~ s/^\(\?\^:(.*)\)/$1/ )     { }
    return qr/$value/;
}

sub equals {
    my ($this, $val, $def) = @_;
    if (!defined $val) {
        return 0 if defined $def;
        return 1;
    } elsif (!defined $def) {
        return 0;
    }
    while ( $val =~ s/^\(\?-xism:(.*)\)$/$1/ ) { }
    while ( $def =~ s/^\(\?-xism:(.*)\)$/$1/ ) { }
    while ( $val =~ s/^\(\?\^:(.*)\)/$1/ ) { }
    while ( $def =~ s/^\(\?\^:(.*)\)/$1/ ) { }
    return $val eq $def;
}

1;
