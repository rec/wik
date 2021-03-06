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

=pod

---+ package TWiki::Form::Select

=cut

package TWiki::Form::Select;
use base 'TWiki::Form::ListFieldDefinition';

use strict;

my @allowedAttributes = (
    'form', 'onblur', 'onfocus', 'onchange', 'onselect', 'onmouseover', 'onmouseout',
    'spellcheck', 'style', 'tabindex', 'title', 'translate'
  );

sub new {
    my $class = shift;
    my $this = $class->SUPER::new( @_ );

    # Parse the size to get min and max
    $this->{size} ||= 1;
    if( $this->{size} =~ /^\s*(\d+)\.\.(\d+)\s*$/ ) {
        $this->{minSize} = $1;
        $this->{maxSize} = $2;
    } else {
        $this->{minSize} = $this->{size};
        $this->{minSize} =~ s/[^\d]//g;
        $this->{minSize} ||= 1;
        $this->{maxSize} = $this->{minSize};
    }

    return $this;
}


=pod

---++ getDefaultValue() -> $value
The default for a select is always the empty string, as there is no way in
TWiki form definitions to indicate selected values. This defers the decision
on a value to the browser.

=cut

sub getDefaultValue {
    return '';
}

sub getOptions {
    my $this = shift;

    return $this->{_options} if $this->{_options};

    my $vals = $this->SUPER::getOptions(@_);
    if ($this->{type} =~ /\+values/) {
        # create a values map

        $this->{valueMap} = ();
        $this->{_options} = ();
        my $str;
        foreach my $val (@$vals) {
            if ($val =~ /^(.*?[^\\])=(.+)$/) {
                # "label=value" syntax
                $str = $1;
                $val = $2;
                $str =~ s/\\=/=/g;
            } elsif ($val =~ /^(.*?): ?(.+)$/) {
                # Item7563: More intuitive "value: label" syntax
                $val = $1;
                $str = $2;
            } else {
                $str = $val;
            }
            $this->{valueMap}{$val} = TWiki::urlDecode($str);
            push @{$this->{_options}}, $val;
        }
    }

    return $vals;
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
    undef $this->{minSize};
    undef $this->{maxSize};
    undef $this->{valueMap}
}

sub isMultiValued { return shift->{type} =~ /\+multi/; }

sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    my $choices = '';

    my %isSelected = map { $_ => 1 } split(/\s*,\s*/, $value);
    foreach my $option ( @{$this->getOptions()} ) {
        my %params = (
            class => 'twikiEditFormOption',
           );
        $params{selected} = 'selected' if $isSelected{$option};
        if (defined($this->{valueMap}{$option})) {
            $params{value} = $option;
            $option = $this->{valueMap}{$option};
        }
        $option =~ s/<nop/&lt\;nop/go;
        $choices .= CGI::option( \%params, $option );
    }
    my $size = scalar( @{$this->getOptions()} );
    if( $size > $this->{maxSize} ) {
        $size = $this->{maxSize};
    } elsif( $size < $this->{minSize} ) {
        $size = $this->{minSize};
    }
    my $classes = $this->cssClasses('twikiSelect', 'twikiEditFormSelect');
    my $val = $this->{parameters}{class};
    $classes .= ' ' . $val if( defined $val );
    my $params = {
        class => $classes,
        name  => $this->{name},
        size  => $this->{size},
    };
    foreach my $attr ( @allowedAttributes ) {
        $val = $this->{parameters}{$attr};
        $params->{$attr} = $val if( defined $val );
    }
    if( $this->isMultiValued() ) {
        $params->{'multiple'}='on';
        $value  = CGI::Select( $params, $choices );
        # Item2410: We need a dummy control to detect the case where
        #           all checkboxes have been deliberately unchecked
        # Item3061:
        # Don't use CGI, it will insert the value from the query
        # once again and we need an empt field here.
        $value .= '<input type="hidden" name="'.$this->{name}.'" value="" />';
    }
    else {
        $value  = CGI::Select( $params, $choices );
    }
    return ( '', $value );
}

1;
