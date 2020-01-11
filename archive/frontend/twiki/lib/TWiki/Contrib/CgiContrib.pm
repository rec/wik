# Contrib for TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2015-2018 Peter Thoeny, peter[at]thoeny.org and
# TWiki Contributors.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package TWiki::Contrib::CgiContrib;

use strict;
use 5.008;

use CGI;

our $VERSION = $CGI::VERSION;
our $RELEASE = '2018-07-05';
our $SHORTDESCRIPTION = "CGI version $VERSION from CPAN:CGI";

=pod

This is the stub module of CgiContrib.  Its only purpose is to expose
the version number of CGI under its expected package name, so that the
TWiki dependency checking mechanism will find it.

=cut

1;
