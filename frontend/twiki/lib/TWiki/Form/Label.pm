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

package TWiki::Form::Label;
use base 'TWiki::Form::FieldDefinition';

use strict;

my @allowedAttributes = (
    'class', 'form', 'id', 'max', 'maxlength', 'min', 'style'
  );

sub isEditable {
    return 0;
}

sub renderForEdit {
    my( $this, $web, $topic, $value ) = @_;

    # Changing labels through the URL is a feature for TWiki applications,
    # even though it's not accessible for standard edits. Some contribs
    # may want to override this to make labels editable.
    my $session = $this->{session};
    my $renderedValue = $session->renderer->getRenderedVersion
      ( $session->handleCommonTags( $value, $web, $topic ));
    my $hiddenParams = {
        -name  => $this->{name},
        -value => $value,
      };
    foreach my $attr ( @allowedAttributes ) {
        my $val = $this->{parameters}{$attr};
        $hiddenParams->{$attr} = $val if( defined $val );
    }
    my $html = CGI::hidden( $hiddenParams )
             . CGI::div( { class => 'twikiEditFormLabelField' }, $renderedValue );
    return ( '', $html );
}

1;
