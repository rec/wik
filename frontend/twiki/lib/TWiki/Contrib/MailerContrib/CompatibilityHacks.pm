# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2004-2018 Peter Thoeny, peter[at]thoeny.org and
# TWiki Contributors. All Rights Reserved. TWiki Contributors are
# listed in the AUTHORS file in the root of this distribution.
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
#
# Hack for older TWiki versions

package CompatibilityHacks;

package IteratorHack;

sub new {
    my ($class, $list) = @_;
    my $this = bless({list => $list, index => 0, next => undef }, $class);
    return $this;
}

sub hasNext {
    my( $this ) = @_;
    return 1 if $this->{next};
    if( $this->{index} < scalar(@{$this->{list}}) ) {
        $this->{next} = $this->{list}->[$this->{index}++];
        return 1;
    }
    return 0;
}

sub next {
    my $this = shift;
    $this->hasNext();
    my $n = $this->{next};
    $this->{next} = undef;
    return $n;
}

package TWiki::Func;

sub eachChangeSince {
    my ($web, $since) = @_;

    my $changes;
    if( open(F, "<$TWiki::cfg{DataDir}/$web/.changes")) {
        local $/ = undef;
        $changes = <F>;
        close(F);
    }

    $changes ||= '';

    my @changes =
      map {
          # Create a hash for this line
          { topic => $_->[0], user => $_->[1], time => $_->[2],
              revision => $_->[3], more => $_->[4] };
      }
        grep {
            # Filter on time
            $_->[2] && $_->[2] >= $since
        }
          map {
              # Split line into an array
              my @row = split(/\t/, $_, 5);
              \@row;
          }
            reverse split( /[\r\n]+/, $changes);

    return new IteratorHack( \@changes );
}

1;
