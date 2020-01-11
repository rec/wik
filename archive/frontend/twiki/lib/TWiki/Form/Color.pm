# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2010-2016 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2010-2016 TWiki Contributors. All Rights Reserved.
# TWiki Contributors are listed in the AUTHORS file in the root of
# this distribution. NOTE: Please extend that file, not this notice.
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
# This packages subclasses TWiki::Form::FieldDefinition to implement
# the =color= type

package TWiki::Form::Color;
use base 'TWiki::Form::FieldDefinition';

use strict;

our @allowedAttributes = (
    'form', 'onblur', 'onfocus', 'onchange', 'onselect', 'onmouseover', 'onmouseout',
    'pattern', 'placeholder', 'spellcheck', 'style', 'tabindex', 'title', 'translate'
  );

use TWiki::Plugins::ColorPickerPlugin;

# ========================================================
sub new {
    my $class = shift;
    my $this = $class->SUPER::new( @_ );
    my $size = $this->{size} || '0';
    $size =~ s/[^\d]//g;
    $size = 8 if( !$size || $size < 1 );
    $this->{size} = $size;
    return $this;
}

sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    my $classes = $this->can('cssClasses') ?
                  $this->cssClasses('twikiInputField', 'twikiEditFormColorField') :
                  'twikiInputField twikiEditFormColorField';
    my $val = $this->{parameters}{class};
    $classes .= ' ' . $val if( defined $val );
    my $params = {
        -class => $classes,
      };
    foreach my $attr ( @allowedAttributes ) {
        $val = $this->{parameters}{$attr};
        $params->{$attr} = $val if( defined $val );
    }
    $value = TWiki::Plugins::ColorPickerPlugin::renderForEdit( $this->{name},
               $value, $this->{parameters}{type}, $params );

    return ( '', $value );
}

sub renderForDisplay {
    my ( $this, $format, $value, $attrs ) = @_;

    $format = TWiki::Plugins::ColorPickerPlugin::renderForDisplay( $this->{name},
                $format, $value, 'view-hex', $attrs );

    return $this->SUPER::renderForDisplay( $format, $value, $attrs );
}

1;
