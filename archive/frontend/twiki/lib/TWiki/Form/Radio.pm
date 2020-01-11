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

package TWiki::Form::Radio;
use base 'TWiki::Form::ListFieldDefinition';

use strict;

my @allowedAttributes = (
    'form', 'onblur', 'onfocus', 'onchange', 'onselect', 'onmouseover', 'onmouseout',
    'spellcheck', 'style', 'tabindex', 'title', 'translate'
  );

sub new {
    my $class = shift;
    my $this = $class->SUPER::new( @_ );
    $this->{size} ||= 0;
    $this->{size} =~ s/\D//g;
    $this->{size} ||= 0;
    $this->{size} = 4 if ( $this->{size} < 1 );

    return $this;
}

sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    my $selected = '';
    my $session = $this->{session};
    my %attrs;
    my $classes = $this->cssClasses('twikiRadioButton', 'twikiEditFormRadioField');
    my $val = $this->{parameters}{class};
    $classes .= ' ' . $val if( defined $val );
    foreach my $item ( @{$this->getOptions()} ) {
        $attrs{$item} =
          {
            class => $classes,
            label => $session->handleCommonTags( $item, $web, $topic )
          };
        foreach my $attr ( @allowedAttributes ) {
            $val = $this->{parameters}{$attr};
            $attrs{$item}{$attr} = $val if( defined $val );
        }
        $selected = $item if( $item eq $value );
    }

    $value = CGI::radio_group(
        -name => $this->{name},
        -values => $this->getOptions(),
        -default => $selected,
        -columns => $this->{size},
        -attributes => \%attrs,
      );
    $value = CGI::div( { class => 'twikiCheckboxGroup' }, $value );
    return ( '', $value );
}

1;
