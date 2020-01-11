# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2001-2018 Peter Thoeny, peter[at]thoeny.org
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

package TWiki::Form::Textarea;
use base 'TWiki::Form::FieldDefinition';

use strict;

my @allowedAttributes = (
    'autocomplete', 'form', 'id', 'maxlength', 'minlength', 'onblur', 'onfocus',
    'onchange', 'onselect', 'onmouseover', 'onmouseout', 'pattern', 'placeholder',
    'spellcheck', 'style', 'tabindex', 'title', 'translate', 'wrap'
  );

sub new {
    my $class = shift;
    my $this = $class->SUPER::new( @_ );
    if( $this->{size} =~ /^\s*(\d+)x(\d+)\s*$/ ) {
        $this->{cols} = $1;
        $this->{rows} = $2;
    } else {
        $this->{cols} = 50;
        $this->{rows} = 4;
    }
    return $this;
}

=begin twiki

---++ ObjectMethod finish()
Break circular references.

=cut

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;
    $this->SUPER::finish();
    undef $this->{cols};
    undef $this->{rows};
}

sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    my $classes = $this->cssClasses('twikiInputField', 'twikiEditFormTextAreaField');
    my $val = $this->{parameters}{class};
    $classes .= ' ' . $val if( defined $val );

    my $params = {
        -class   => $classes,
        -name    => $this->{name},
        -cols    => $this->{cols},
        -rows    => $this->{rows},
        -default => "\n" . $value,
      };
    foreach my $attr ( @allowedAttributes ) {
        $val = $this->{parameters}{$attr};
        $params->{$attr} = $val if( defined $val );
    }

    return ( '', CGI::textarea( $params ) );
}

1;
