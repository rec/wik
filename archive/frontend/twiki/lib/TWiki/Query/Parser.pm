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
#
# Author: Crawford Currie http://c-dot.co.uk

=pod

---+ package TWiki::Query::Parser

Parser for queries

=cut

package TWiki::Query::Parser;
use base 'TWiki::Infix::Parser';

use TWiki::Query::Node;

use strict;
use Assert;

# Operators
#
# In the following, the standard InfixParser node structure is extended by
# one field, 'exec'.
#
# exec is the name of a member function of the 'Query' class that evaluates
# the node. It is called on the node and is passed a $domain. The $domain
# is a reference to a hash that contains the data being operated on, and a
# reference to the meta-data of the topic being worked on (this is
# effectively the "topic object"). The data being operated on can be a
# Meta object, a reference to an array (such as attachments), a reference 
# to a hash (such as TOPICINFO) or a scalar. Arrays can contain other arrays
# and hashes.

sub new {
    my( $class, $options ) = @_;

    $options->{words} ||= qr/[A-Z][A-Z0-9_:]*/i;
    $options->{nodeClass} ||= 'TWiki::Query::Node';
    my $this = $class->SUPER::new($options);
    die "{Operators}{Query} is undefined; re-run configure"
      unless defined( $TWiki::cfg{Operators}{Query} );
    foreach my $op (@{$TWiki::cfg{Operators}{Query}}) {
        eval "require $op";
        ASSERT(!$@) if DEBUG;
        $this->addOperator($op->new());
    }
    return $this;
}

1;
