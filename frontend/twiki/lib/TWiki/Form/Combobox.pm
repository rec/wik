# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2013 Wave Systems Corp.
# Copyright (C) 2008-2018 Peter Thoeny, peter[at]thoeny.org
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

#================================
package TWiki::Form::Combobox;
use base 'TWiki::Form::ListFieldDefinition';

use strict;

my $minSize = 2;
my $maxSize = 6;
my @allowedAttributes = (
    'form', 'max', 'maxlength', 'min', 'onblur', 'onfocus', 'onchange', 'onselect',
    'onmouseover', 'onmouseout', 'pattern', 'placeholder', 'spellcheck', 'tabindex',
    'title', 'translate'
  );

#================================
sub new {
    my $class = shift;
    my $this = $class->SUPER::new( @_ );
    $this->{size} ||= 2;
    return $this;
}

#================================
sub getDefaultValue {
    return '';
}

#================================
sub getOptions {
    my $this = shift;
    return $this->{_options} if $this->{_options};
    my $vals = $this->SUPER::getOptions(@_);
    return $vals;
}

#================================
sub finish {
    my $this = shift;
    $this->SUPER::finish();
}

#================================
sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    my %optionParams = ( class => 'twikiEditFormOption' );
    my $choices = '';
    foreach my $option ( @{$this->getOptions()} ) {
        $option =~ s/<nop/&lt\;nop/go;
        $choices .= CGI::option( \%optionParams, $option );
    }
    my $size = scalar( @{$this->getOptions()} );
    if( $size > $maxSize ) {
        $size = $maxSize;
    } elsif( $size < $minSize ) {
        $size = $minSize;
    }

    my $name  = $this->{name};
    my $width = sprintf( "%1.2fem", $this->{size} * 0.57 ); # approximate number of chars
    my $text  = "<div style='white-space: nowrap;'>";

    my $classes = $this->cssClasses('twikiInputField', 'twikiEditFormTextField');
    my $val = $this->{parameters}{class};
    $classes .= ' ' . $val if( defined $val );

    my $style = "width: $width";
    $val = $this->{parameters}{style};
    $style .= '; ' . $val if( defined $val );
    $style .= ';' if( $style !~ /;$/ );

    my $textParams = {
        -class => $classes,
        -name  => $name,
        -id    => $name . '_text',
        -size  => $this->{size},
        -value => $value,
        -style => $style,
      };
    foreach my $attr ( @allowedAttributes ) {
        $val = $this->{parameters}{$attr};
        $textParams->{$attr} = $val if( defined $val );
    }
    $text .= CGI::textfield( $textParams );
    $text .= CGI::image_button(
        -name    => $name . '_Image',
        -src     => TWiki::Func::getPubUrlPath() . '/' .
                    TWiki::Func::getTwikiWebname() . '/TWikiDocGraphics/pick.gif',
        -style   => 'vertical-align: middle; margin-left: -13px;',
        -alt     => 'Select',
        -title   => 'Select',
        -onclick => "var sel = \$('#${name}_pick'); "
                  . "if( document.getElementById('${name}_text') "
                  . "    == document.activeElement ) { "
                    # jQuery 1.5 does not have :focus selector yet
                  . "} else { "
                  . "sel.val(\$('#${name}_text').val()); "
                  . "sel.parent().css({display: 'inline'}); "
                  . "sel.focus(); "
                  . "} "
                  . "return false;",
      );
    $width = sprintf( "%1.2fem", $this->{size} * 0.575 + 0.7 );
    $text .= "</div><div style='position: absolute; width: $width; z-index: 10; display: none;'>";
    my $selectParams = {
        class   => 'twikiSelect twikiEditFormSelect',
        name    => $name . '_pick',
        id      => $name . '_pick',
        size    => $size,
        style   => "width: 99%; border: 1px solid #666; box-shadow: 1px 1px 4px #666;",
        onclick => "var txt = \$('#${name}_pick option:selected').val(); "
                 . "\$('#${name}_text').val(txt).focus(); "
                 . "\$('#${name}_pick').parent().css({display: 'none'});",
        onblur  => "\$('#${name}_text').focus(); "
                 . "\$('#${name}_pick').parent().css({display: 'none'});",
    };
    $text .= CGI::Select( $selectParams, $choices );
    $text .= '</div>';
    $text .= "<script> \$('#${name}_pick').live('keyup', function(e) { "
           . "if( e.which==13 || e.which==27 ) { if( e.which==13 ) { "
           . "\$('#${name}_text').val(\$('#${name}_pick option:selected').val()); } "
           . "\$('#${name}_text').focus(); "
           . "\$('#${name}_pick').parent().css({display: 'none'}); } "
           . "}); </script>";

    return ( '', $text );
}

#================================
1;
