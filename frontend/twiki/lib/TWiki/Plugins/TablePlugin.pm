# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2001-2003 John Talintyre, jet@cheerful.com
# Copyright (C) 2001-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2005-2018 TWiki Contributors
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# As per the GPL, removal of this notice is prohibited.
#
# Allow sorting of tables, plus setting of background colour for
# headings and data cells. See TWiki.TablePlugin for details of use

use strict;

package TWiki::Plugins::TablePlugin;

require TWiki::Func;    # The plugins API
require TWiki::Plugins; # For the API version

# =========================
our $VERSION = '$Rev: 30480 (2018-07-16) $';
our $RELEASE = '2018-07-05';

our $topic;
our $installWeb;
our $initialised;

# =========================
sub initPlugin {
    my( $web, $user );
    ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1.026 ) {
        TWiki::Func::writeWarning( 'Version mismatch between TablePlugin and Plugins.pm' );
        return 0;
    }

    my $cgi = TWiki::Func::getCgiQuery();
    return 0 unless $cgi;

    $initialised = 0;

    return 1;
}

# =========================
sub preRenderingHandler {
    ### my ( $text, $removed ) = @_;

    my $sort = TWiki::Func::getPreferencesValue( 'TABLEPLUGIN_SORT' );
    return unless ($sort && $sort =~ /^(all|attachments)$/) ||
      $_[0] =~ /%TABLE\{.*?}%/;

    # on-demand inclusion
    require TWiki::Plugins::TablePlugin::Core;
    TWiki::Plugins::TablePlugin::Core::handler( @_ );
}

1;
