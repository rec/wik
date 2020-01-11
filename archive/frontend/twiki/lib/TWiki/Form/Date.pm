# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2004-2016 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2004-2016 TWiki Contributors. All Rights Reserved.
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
# the =date= type

package TWiki::Form::Date;
use base 'TWiki::Form::FieldDefinition';

use strict;

use TWiki::Plugins::DatePickerPlugin;

# ========================================================
sub new {
    my $class = shift;
    my $this = $class->SUPER::new( @_ );
    my $size = $this->{size} || '0';
    $size =~ s/[^\d]//g;
    $size = 11 if( !$size || $size < 1 ); # length(2012-12-31)=10
    $this->{size} = $size;
    return $this;
}

# ========================================================
sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    require TWiki::Plugins::DatePickerPlugin;
    my $text = TWiki::Plugins::DatePickerPlugin::renderForEdit( $this->{name}, $value,
        undef, $this->{parameters} );

    my $session = $this->{session};
    $text = $session->renderer->getRenderedVersion(
        $session->handleCommonTags( $text, $web, $topic ));

    return ( '', $text );
}

# ========================================================
1;
