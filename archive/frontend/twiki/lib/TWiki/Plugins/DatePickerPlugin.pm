# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2004-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2004-2018 TWiki Contributors. All Rights Reserved.
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
# This plugin is based on the work of TWiki:Plugins.JSCalendarContrib.

=begin twiki

Read [[%ATTACHURL%/doc/html/reference.html][the Mishoo documentation]] or
[[%ATTACHURL%/index.html][visit the demo page]] for detailed information 
on using the calendar widget.

This plugin includes the following function to make using the calendar
easier from other TWiki plugins:

=cut

package TWiki::Plugins::DatePickerPlugin;

use strict;

require TWiki::Func;    # The plugins API

# ========================================================
our $VERSION = '$Rev: 30446 (2018-07-16) $';
our $RELEASE = '2018-07-05';
our $SHORTDESCRIPTION = "Pop-up calendar with date picker, for use in TWiki forms, HTML forms and TWiki plugins";
our $NO_PREFS_IN_TOPIC = 1;

# Max width of different mishoo format components
my %w = (
    a => 3,     # abbreviated weekday name
    A => 9,     # full weekday name
    b => 3,     # abbreviated month name
    B => 9,     # full month name
    C => 2,     # century number
    d => 2,     # the day of the month ( 00 .. 31 )
    e => 2,     # the day of the month ( 0 .. 31 )
    H => 2,     # hour ( 00 .. 23 )
    I => 2,     # hour ( 01 .. 12 )
    j => 3,     # day of the year ( 000 .. 366 )
    k => 2,     # hour ( 0 .. 23 )
    l => 2,     # hour ( 1 .. 12 )
    m => 2,     # month ( 01 .. 12 )
    M => 2,     # minute ( 00 .. 59 )
    n => 1,     # a newline character
    p => 2,     # ``PM'' or ``AM''
    P => 2,     # ``pm'' or ``am''
    S => 2,     # second ( 00 .. 59 )
    s => 12,    # number of seconds since Epoch
    t => 1,     # a tab character
    U => 2,     # the week number
    u => 1,     # the day of the week ( 1 .. 7, 1 = MON )
    W => 2,     # the week number
    w => 1,     # the day of the week ( 0 .. 6, 0 = SUN )
    V => 2,     # the week number
    y => 2,     # year without the century ( 00 .. 99 )
    Y => 4,     # year including the century ( ex. 1979 )
);

my @inputFieldAttributes = ( 'accesskey', 'alt', 'autocomplete', 'autofocus',
     'contenteditable', 'contextmenu', 'disabled', 'form', 'maxlength',
     'onblur', 'oninput', 'oninvalid', 'onchange', 'onfocus', 'onkeydown', 'onkeypress',
     'onkeyup', 'onload', 'onmousedown', 'onmouseout', 'onmouseover', 'onmouseup',
     'onmouse', 'pattern', 'placeholder', 'readonly', 'required', 'size', 'spellcheck',
     'style', 'tabindex', 'title', 'translate'
   );

my $headerDone;

# ========================================================
sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    TWiki::Func::registerTagHandler('DATEPICKER', \&handleDATEPICKER );
    $headerDone = 0;

    return 1;
}

# ========================================================
sub handleDATEPICKER  {
    my ( $session, $params ) = @_;

    my $name   = $params->{name};
    my $value  = $params->{value};
    my $format = $params->{format};
    return renderForEdit( $name, $value, $format, $params );
}

=begin twiki

---+++ renderForEdit

=TWiki::Plugins::DatePickerPlugin::renderForEdit( $name, $value, $format [, \%options] ) -> $html=

This is the simplest way to use calendars from a plugin.
   * =$name= is the name of the CGI parameter for the calendar
     (it should be unique),
   * =$value= is the current value of the parameter (may be undef)
   * =$format= is the format to use (optional; the default is set
     in =configure=). The HTML returned will display a date field
     and a drop-down calendar.
   * =\%options= is an optional hash containing base options for
     the textfield.

__Notes:__
   * The CSS and Javascript are added if needed, e.g. the =addToHEAD()=
     function does not need to be called.
   * No output is shown if =$name= is empty or undef, but the CSS and
     Javascript are loaded if needed. This can be used to preload the
     CSS and Javascript with a parameterless =%<nop>DATEPICKER{}%=
     variable.

Example:
<verbatim>
use TWiki::Plugins::DatePickerPlugin;
...
my $fromDate = TWiki::Plugins::DatePickerPlugin::renderForEdit(
   'from', '2012-12-31');
my $toDate = TWiki::Plugins::DatePickerPlugin::renderForEdit(
   'to', undef, '%Y');
</verbatim>

=cut

# ========================================================
sub renderForEdit {
    my ( $name, $value, $format, $params ) = @_;

    $format ||= $TWiki::cfg{Plugins}{DatePickerPlugin}{Format} || '%Y-%m-%d';

    addToHEAD( 'twiki' );

    # return after adding the css & js if no name
    return '' unless( $name );

    # Work out how wide it has to be from the format
    # SMELL: add a space because pattern skin default fonts on FF make the
    # box half a character too narrow if the exact size is used
    my $wide = $format.' ';
    $wide =~ s/(%(.))/$w{$2} ? ('_' x $w{$2}) : $1/ge;

    my $id = 'id_'.$name;
    $id = $params->{id} if( $params && $params->{id} );
    my $classes = 'twikiInputField';
    $classes .= ' twikiMandatory' if( TWiki::Func::isTrue( $params && $params->{mandatory} ) );
    $classes .= ' ' . $params->{class} if( $params && $params->{class} );

    my %textParams = (
        -name  => $name,
        -value => $value || '',
        -size  => length($wide),
        -id    => $id,
        -class => $classes,
      );

    foreach my $attr ( @inputFieldAttributes ) {
        if( $params && defined $params->{$attr} ) {
            $textParams{$attr} = $params->{$attr};
        }
    }

    my $text = CGI::textfield( \%textParams )
      . CGI::image_button(
          -name => 'img_'.$name,
          -onclick =>
            "javascript: return showCalendar('$id','$format')",
            -src=> TWiki::Func::getPubUrlPath() . '/' .
              TWiki::Func::getTwikiWebname() .
                  '/DatePickerPlugin/img.gif',
          -alt => 'Calendar',
          -title => 'Select date',
          -align => 'middle');

    return $text;
}

=begin twiki

---+++ addToHEAD

=TWiki::Plugins::DatePickerPlugin::addToHEAD( $setup )=

This function will automatically add the headers for the calendar to the page
being rendered. It's intended for use when you want more control over the
formatting of your calendars than =renderForEdit= affords. =$setup= is the name
of the calendar setup module; it can either be omitted, in which case the method
described in the Mishoo documentation can be used to create calendars, or it
can be ='twiki'=, in which case a Javascript helper function called
'showCalendar' is added that simplifies using calendars to set a value in a
text field. For example, say we wanted to display the date with the calendar
icon _before_ the text field, using the format =%Y %b %e=
<verbatim>
use TWiki::Plugins::DatePickerPlugin;
...

sub commonTagsHandler {
  ....
  # Add styles and javascript for the date picker & enable 'showCalendar'
  TWiki::Plugins::DatePickerPlugin::addToHEAD( 'twiki' );

  my $cal = CGI::image_button(
      -name => 'img_datefield',
      -onclick =>
       "return showCalendar('id_datefield','%Y %b %e')",
      -src=> TWiki::Func::getPubUrlPath() . '/' .
             TWiki::Func::getTwikiWebname() .
             '/DatePickerPlugin/img.gif',
      -alt => 'Calendar',
      -align => 'middle' )
    . CGI::textfield(
      { name => 'date', id => "id_datefield" });
  ....
}
</verbatim>

The first parameter to =showCalendar= is the id of the textfield, and the 
second parameter is the date format. Default format is ='%Y-%m-%d'=.

The =addToHEAD= function can be called from =commonTagsHandler= for adding
the header to all pages, or from =beforeEditHandler= just for edit pages etc.

=cut

# ========================================================
sub addToHEAD {
    my $setup = shift;
    $setup ||= 'calendar-setup';

    return if( $headerDone );
    $headerDone = 1;

    my $style = $TWiki::cfg{Plugins}{DatePickerPlugin}{Style} || 'twiki';
    my $lang = $TWiki::cfg{Plugins}{DatePickerPlugin}{Lang} || 'en';
    my $base = '%PUBURLPATH%/%SYSTEMWEB%/DatePickerPlugin';
    my $head = <<HERE;
<style type='text/css' media='all'>
  \@import url('$base/calendar-$style.css');
  .calendar {z-index:2000;}
</style>
<script type='text/javascript' src='$base/calendar.js'></script>
<script type='text/javascript' src='$base/lang/calendar-$lang.js'></script>
HERE
    TWiki::Func::addToHEAD( 'DATEPICKERPLUGIN', $head );

    # Add the setup separately; there might be different setups required
    # in a single HTML page.
    $head = <<HERE;
<script type='text/javascript' src='$base/$setup.js'></script>
HERE
    TWiki::Func::addToHEAD( 'DATEPICKERPLUGIN_'.$setup, $head );
}

# ========================================================
1;
