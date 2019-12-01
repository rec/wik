# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2002-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2005-2018 TWiki Contributors
# Copyright (C) 2005-2006 Michael Daum <micha@nats.informatik.uni-hamburg.de>
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
# =========================
#
# This is the HeadlinesPlugin used to show RSS news feeds.
# Plugin home: http://TWiki.org/cgi-bin/view/Plugins/HeadlinesPlugin
#

# =========================
package TWiki::Plugins::HeadlinesPlugin;
use strict;

# =========================
our $VERSION = '$Rev: 30560 (2018-07-16) $';
our $RELEASE = '2018-07-13';
our $NO_PREFS_IN_TOPIC = 1;
our $SHORTDESCRIPTION = 'Show headline news in TWiki pages based on RSS and ATOM news feeds from external sites';
our $core;

# =========================
sub initPlugin {

  $core = undef;
  TWiki::Func::registerTagHandler( 'HEADLINES', \&_HEADLINES );
  return 1;
}

# =========================
sub _HEADLINES {
  my( $session, $params, $theTopic, $theWeb ) = @_;

  # Lazy loading, e.g. compile core module only when required
  unless( $core ) {
      require TWiki::Plugins::HeadlinesPlugin::Core;
      $core = new TWiki::Plugins::HeadlinesPlugin::Core();
  }
  return $core->handleHEADLINES( @_ );
}

1;
