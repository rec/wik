# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2010-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2010-2018 TWiki Contributors. All Rights Reserved.
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

=begin twiki

This package includes a small Perl module to make it easier to use the 
color picker from other TWiki plugins. This module includes the functions:

=cut

package TWiki::Plugins::ColorPickerPlugin;

use strict;

require TWiki::Func;    # The plugins API

# ==========================================================================
our $VERSION = '$Rev: 30442 (2018-07-16) $';
our $RELEASE = '2018-07-05';
our $SHORTDESCRIPTION = "Color picker, packaged for use in TWiki forms and TWiki applications";
our $NO_PREFS_IN_TOPIC = 1;

our $topic;
our $web;
our $doneHeader;
our $header = <<'HERE';
<script type="text/javascript" src="%PUBURLPATH%/%SYSTEMWEB%/ColorPickerPlugin/farbtastic.js"></script>
<link rel="stylesheet" href="%PUBURLPATH%/%SYSTEMWEB%/ColorPickerPlugin/farbtastic.css" type="text/css" media="all" />
<style>
 .colorPopupBox {
  display: none;
  position: absolute;
  border: 1px solid #bbb;
  padding: 10px 10px;
  background-image: url(%PUBURLPATH%/%SYSTEMWEB%/ScrollBoxAddOn/gradient-title.png);
  background-repeat: repeat-x;
  background-color: #fcfcff;
  border: 1px solid #c0c0c0;
  -moz-border-radius: 6px;
  -webkit-border-radius: 6px;
  border-radius: 6px;
  box-shadow: 3px 3px 6px #999;
 }
 .colorPopupClose {
  display: none;
  position: absolute;
  z-index: 12345;
  margin: 3px 0 0 192px;
  width: 22px;
  height: 22px;
  text-align: right;
 }
</style>
HERE
our $closeImg = ' <img src="%ICONURLPATH{remove}%" width="12" height="12" border="0"'
              . ' alt="" title="close" /> ';

# ==========================================================================
sub initPlugin {
    ( $topic, $web ) = @_;

    $doneHeader = 0;
    TWiki::Func::registerTagHandler('COLORPICKER', \&handleColorPicker );

    return 1;
}

# ==========================================================================

=begin twiki

---+++ addHEAD

TWiki::Plugins::ColorPickerPlugin::addHEAD( )

=addHEAD= needs to be called before TWiki::Plugins::ColorPickerPlugin::renderForEdit
is called.

=cut

sub addHEAD {
    return if( $doneHeader );
    TWiki::Func::addToHEAD( 'COLORPICKERPLUGIN', $header );
    $closeImg = TWiki::Func::expandCommonVariables( $closeImg, $topic, $web );
    $doneHeader = 1;
}

# ==========================================================================
sub handleColorPicker  {
    my ( $session, $params ) = @_;

    my %options = %$params;
    my $name  = $params->{name};
    my $value = $params->{value};
    my $type  = $params->{type} || '';
    delete $options{name};
    delete $options{value};
    delete $options{type};
    delete $options{_DEFAULT};
    delete $options{_RAW};

    if( $type =~ /^view/ ) {
        return renderForDisplay( $name, '', $value, $type, \%options );
    } else {
        return renderForEdit( $name, $value, $type, \%options );
    }
}

# ==========================================================================

=begin twiki

---+++ renderForEdit

TWiki::Plugins::ColorPickerPlugin::renderForEdit($name, $value, $type, [, \%options]) -> $html

=cut

sub renderForEdit {
    my ( $name, $value, $type, $options ) = @_;

    addHEAD();

    my $head = <<HERE;
 <script type="text/javascript" charset="utf-8">
  \$(document).ready(function() {
    \$('#colorPicker_$name').farbtastic('#colorText_$name');
    \$('#colorButton_$name').click(function( event ) {
      event.preventDefault();
      \$('#colorPicker_$name').toggle();
      \$('#colorClose_$name').toggle();
    });
    \$('#colorClose_$name').click(function( event ) {
      event.preventDefault();
      \$('#colorPicker_$name').toggle();
      \$('#colorClose_$name').toggle();
    });
  });
 </script>
HERE
    TWiki::Func::addToHEAD( 'COLORPICKERPLUGIN_' . $name, $head, 'COLORPICKERPLUGIN' );

    $options ||= {};
    $options->{name} = $name;
    $options->{id} = 'colorText_'.$name;
    $options->{value} = $value || '#000000';
    $options->{size} ||= '8';

    my $text = CGI::textfield( $options );

    $options = { id => "colorPicker_$name" };
    if( $type && $type eq 'popup' ) {
        $text .= CGI::image_button(
            -name    => "colorButton_$name",
            -id      => "colorButton_$name",
            -src     => TWiki::Func::getPubUrlPath() . '/' .
                TWiki::Func::getTwikiWebname() . '/ColorPickerPlugin/color_bg.gif',
            -alt     => 'ColorPicker',
            -align   => 'middle',
            -class   => 'twikiButton'
          );
        $options->{class} = 'colorPopupBox';
        $text .= CGI::div( { id => 'colorClose_'.$name, class => 'colorPopupClose' }, $closeImg );
        $text .= CGI::div( $options, ' ' );
    }
    $text .= CGI::div( $options, ' ' );
    return $text;
}

# ==========================================================================

=begin twiki

---+++ renderForDisplay

TWiki::Plugins::ColorPickerPlugin::renderForDisplay($name, $format, $value, [, \%options]) -> $html

=cut

sub renderForDisplay {
    my ( $name, $format, $value, $type, $options ) = @_;

    my $bgcolor = $value;
    $bgcolor ||= 'transparent';
    my $color = '#000000';
    my $rgb = '';
    if( $bgcolor =~ /^ *#([0-9-a-zA-Z]{3}) *$/ ) {
        $rgb = $1;
        $rgb =~ s/(.)/$1$1/g; # duplicate ('123' becomes '112233')
    } elsif( $bgcolor =~ /^ *#([0-9-a-zA-Z]{6}) *$/ ) {
        $rgb = $1;
    }
    if( $rgb && $rgb =~ /^(..)(..)(..)$/ ) {
        my $lum = 0.213 * hex( $1 ) + 0.715 * hex( $2 ) + 0.072 * hex( $3 ); # Standard luminance
        #my $lum = 0.299 * hex( $1 ) + 0.587 * hex( $2 ) + 0.114 * hex( $3 ); # Perceived luminance
        $color = '#ffffff' if( $lum < 150 );
    }
    $value = '&nbsp;' unless( $type eq 'view-hex' );
    my $style = "color: $color; background-color: $bgcolor; width: 8ch; text-align: center; "
              . "border: solid 1px #666666; border-bottom: #aaaaaa; border-right: #aaaaaa;";
    $style .= ' ' . $options->{style} if( defined $options->{style} );
    $style .= ';' unless( $style =~ /;$/ );
    my $params = '';
    foreach my $attr ( keys %{$options} ) {
        my $v = $options->{$attr};
        $params .= " $attr=\"$v\"" if( defined $v && $attr ne 'style' );
    }
    my $text = "<div style=\"$style\"$params> $value </div>";
    $format ||= '$value';
    $format =~ s/\$value/$text/g;

    return $format;
}

1;
