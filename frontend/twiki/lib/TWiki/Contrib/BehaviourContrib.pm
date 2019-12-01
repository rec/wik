# Package for TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2006-2018 TWiki Contributor.
# All Rights Reserved. TWiki Contributors are listed in the 
# AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of the TWiki distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# As per the GPL, removal of this notice is prohibited.

package TWiki::Contrib::BehaviourContrib;
use vars qw( $VERSION );
$VERSION = '$Rev: 30438 (2018-07-16) $';
$RELEASE = '2018-07-05';

=begin twiki

---+++ TWiki::Contrib::BehaviourContrib::addHEAD()

This function will automatically add the headers for the contrib to
the page being rendered. It is intended for use from Plugins and
other extensions. For example:

<verbatim>
sub commonTagsHandler {
  ....
  require TWiki::Contrib::BehaviourContrib;
  TWiki::Contrib::BehaviourContrib::addHEAD();
  ....
</verbatim>

=cut

sub addHEAD {
    my $base = '%PUBURLPATH%/%SYSTEMWEB%/BehaviourContrib';
    my $USE_SRC =
      TWiki::Func::getPreferencesValue('BEHAVIOURCONTRIB_DEBUG') ?
          '_src' : '';
    my $head = <<HERE;
<script type='text/javascript' src='$base/behaviour$USE_SRC.js'></script>
HERE
    TWiki::Func::addToHEAD( 'BEHAVIOURCONTRIB', $head );
}

1;
