# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2004-2018 Peter Thoeny, peter[at]thoeny.org and
# TWiki Contributors. All Rights Reserved. TWiki Contributors are
# listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
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

---+ package MailerConst

$ALWAYS - always send, even if there are no changes
$FULL_TOPIC - send the full topic rather than just changes

Note that this package is defined in a file with a name different to that
of the package. This is intentional (it's to keep the length of the constants
package name short).

=cut

package MailerConst;

our $ALWAYS       = 1; # Always send, even if there are no changes
our $FULL_TOPIC   = 2; # Send the full topic rather than just changes

# ? = FULL_TOPIC
# ! = FULL_TOPIC | ALWAYS

1;
