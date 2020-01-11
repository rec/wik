# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2005-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
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

package TWiki::Query::UnaryOP;

sub new {
    my $class = shift;
    my $this = { @_, arity => 1 };
    return bless( $this, $class );
}

sub evalUnary {
    my $this = shift;
    my $node = shift;
    my $sub = shift;
    my $a = $node->{params}[0];
    my $val = $a->evaluate( @_ ) || '';
    if (ref($val) eq 'ARRAY') {
        my @res = map { &$sub($_) } @$val;
        return \@res;
    } else {
        return &$sub( $val );
    }
}

1;
