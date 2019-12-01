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

package TWiki::Form::Checkbox;
use base 'TWiki::Form::ListFieldDefinition';

use strict;

my @allowedAttributes = (
    'form', 'onblur', 'onfocus', 'onchange', 'onselect', 'onmouseover', 'onmouseout',
    'spellcheck', 'tabindex', 'title', 'translate'
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

# Checkboxes can't provide a default from the form spec
sub getDefaultValue { undef }

# Checkbox store multiple values
sub isMultiValued { 1 }

sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    my $session = $this->{session};
    my $extra = '';
    if( $this->{type} =~ m/\+buttons/ ) {
        $extra = CGI::br();
        $extra .= CGI::button
          ( -class   => 'twikiCheckBox twikiEditFormCheckboxButton',
            -value   => $session->i18n->maketext('Set all'),
            -onclick => 'jQuery(this).parents("form").find("input[name=' . $this->{name}
                      . ']").prop("checked", true);',
            -class   => 'twikiButton',
            -style   => 'font-size: 90%',
          );
        $extra .= '&nbsp;';
        $extra .= CGI::button
          ( -class   => 'twikiCheckBox twikiEditFormCheckboxButton',
            -value   => $session->i18n->maketext('Clear all'),
            -onclick => 'jQuery(this).parents("form").find("input[name=' . $this->{name}
                      . ']").prop("checked", false);',
            -class   => 'twikiButton',
            -style   => 'font-size: 90%',
          );
    }
    $value = '' unless defined( $value ) && length( $value );
    my %isSelected = map { $_ => 1 } split(/\s*,\s*/, $value);
    my %attrs;
    my $classes = $this->cssClasses('twikiEditFormCheckboxField');
    my $val = $this->{parameters}{class};
    $classes .= ' ' . $val if( defined $val );
    my $style = "margin-right: 0.3em";
    $val = $this->{parameters}{style};
    $style .= '; ' . $val if( defined $val );
    $style .= ';' if( $style !~ /;$/ );

    my @defaults;
    foreach my $item ( @{$this->getOptions()} ) {
        # NOTE: Does not expand $item in label
        $attrs{$item} =
          {
              class => $classes,
              label => $session->handleCommonTags( $item, $web, $topic ),
              style => $style,
          };
        foreach my $attr ( @allowedAttributes ) {
            $val = $this->{parameters}{$attr};
            $attrs{$item}{$attr} = $val if( defined $val );
        }
        if( $isSelected{$item} ) {
            push( @defaults, $item );
        }
    }
    $value = CGI::checkbox_group( -name => $this->{name},
                                  -values => $this->getOptions(),
                                  -defaults => \@defaults,
                                  -columns => $this->{size},
                                  -attributes => \%attrs,
                                );
    # Item2410: We need a dummy control to detect the case where
    #           all checkboxes have been deliberately unchecked
    # Item3061:
    # Don't use CGI, it will insert the sticky value from the query
    # once again and we need an empty field here.
    $value .= '<input type="hidden" name="'.$this->{name}.'" value="" />';
    $value = CGI::div( { class => 'twikiCheckboxGroup' }, $value );
    return ( $extra, $value );
}

1;
