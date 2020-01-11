# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2002-2018 Peter Thoeny, peter[at]thoeny.org, and
# TWiki Contributors.
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

package TWiki::Plugins::SlideShowPlugin;

# =========================
our $VERSION = '$Rev: 30474 (2018-07-16) $';
our $RELEASE = '2018-07-05';

our $web;
our $topic;
our $user;
our $installWeb;
our $debug;

# =========================
sub initPlugin
{
    ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1 ) {
        TWiki::Func::writeWarning( "Version mismatch between SlideShowPlugin and Plugins.pm" );
        return 0;
    }

    return 1;
}

# =========================
sub commonTagsHandler
{
### my ( $text, $topic, $web ) = @_;   # do not uncomment, use $_[0], $_[1]... instead
    if( $_[0] =~ /%SLIDESHOWSTART/ ) {
        require TWiki::Plugins::SlideShowPlugin::SlideShow;
        TWiki::Plugins::SlideShowPlugin::SlideShow::init( $installWeb );
        $_[0] = TWiki::Plugins::SlideShowPlugin::SlideShow::handler( @_ );
    }
}

1;
