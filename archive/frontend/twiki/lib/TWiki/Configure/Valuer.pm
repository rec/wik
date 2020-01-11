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
#
# This class is used to refer to two hashes of configuration values.
# The first is a hash of default values, and the second (which will
# have mostly the same keys) contains the *current* value (i.e. the
# value after edits have been applied).
#
# $defaults is a reference to the hash of defaults
# $values is a reference to the hash of current values

package TWiki::Configure::Valuer;

use strict;

use TWiki::Configure::Type;

sub new {
    my ($class, $defaults, $values) = @_;

    my $this = bless({}, $class);
    $this->{defaults} = $defaults;
    $this->{values} = $values;

    return $this;
}

# Get a value from one of the value sets (defaults or values)
sub _getValue {
    my ($this, $value, $set) = @_;
    my $keys = $value->getKeys();
    my $var = '$this->{'.$set.'}->'.$keys;
    my $val;
    eval '$val = '.$var.' if exists('.$var.')';
    if (defined $val) {
        # SMELL: Really shouldn't do this unless we are sure it's an RE,
        # but the probability of this string occurring elsewhere than an
        # RE is so low that we can afford to take the risk.

        # TWikibug:Item7067: Configure adds extra (?^:) to regex variables
        # on save under Perl 5.14. This needs to be cleaned up.
        # SMELL: Regex cleanup needs to be done on 3 places:
        #    * TWiki::Configure::Types::REGEX in sub string2value,
        #    * TWiki::Configure::Types::REGEX in sub equals,
        #    * Here in sub _getValue.
        while ( $val =~ s/^\(\?-xism:(.*)\)$/$1/ ) { }
        while ( $val =~ s/^\(\?\^:(.*)\)$/$1/ )    { }
    }
    return $val;
}

# get the current value
sub currentValue {
    my ($this, $value) = @_;
    return $this->_getValue($value, 'values');
}

# get the default value
sub defaultValue {
    my ($this, $value) = @_;
    return $this->_getValue($value, 'defaults');
}

# Get changed values from CGI. Each parameter is identified by a
# TYPEOF: param that specifies the keys e.g. ?TYPEOF:{Kiss}=Smooch. The
# type is used to determine if the value of {Kiss} in CGI is different to
# the value known to the Valuer (i.e. has been updated). If it is, the keys
# are added to the $updated hash.
sub loadCGIParams {
    my ($this, $query, $updated) = @_;
    my $param;
    my $changed = 0;

    # Each config param has an associated TYPEOF: param, so we only
    # pick up those things that we really want
    foreach $param ( $query->param ) {
        # the - (and therefore the ' and ") is required for languages
        # e.g. {Languages}{'zh-cn'}.
        next unless $param =~ /^TYPEOF:((?:\{[-\w'"]+})*)/;
        my $keys = $1;
        # The value of TYPEOF: is the type name
        my $typename = $query->param( $param );
        $typename =~ /(\w+)/; $typename = $1; # check and untaint
        my $type = TWiki::Configure::Type::load($typename);
	my $newval;
        if( $type->{NeedsQuery} ) {
            $newval = $type->string2value($query, $keys);
        } else {
            $newval = $type->string2value($query->param( $keys ));
        }
        my $xpr = '$this->{values}->'.$keys;
        my $curval = eval $xpr;
        if (!$type->equals($newval, $curval)) {
            #print "<br>$typename $keys '$newval' != '$curval'\n";
            eval $xpr.' = $newval';
            $changed++;
            $updated->{$keys} = 1;
        }
    }
    return $changed;
}

1;
