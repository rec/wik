# Plugin for TWiki Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2005-2018 TWiki Contributor.
# Copyright (C) 2005 ILOG http://www.ilog.fr
# Copyright (C) 2008-2010 Foswiki Contributors. 
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

=pod

---+ package WC

Constants

=cut

package WC;

=pod

---++ Generator flags
| $NO_TML | Flag that gets passed _down_ into generator functions. Constrains output to HTML only. |
| $NO_BLOCK_TML | Flag that gets passed _down_ into generator functions. Don't generate block TML e.g. tables, lists |
| $NOP_ALL | Flag that gets passed _down_ into generator functions. NOP all variables and WikiWords. |
| $BLOCK_TML | Flag passed up from generator functions; set if expansion includes block TML |
| $VERY_CLEAN | Flag passed to indicate that HTML must be aggressively cleaned (unrecognised or unuseful tags stripped out) |
| $BR2NL | Flag set to force BR tags to be converted to newlines. |
| $KEEP_WS | Set to force the generator to keep all whitespace. Otherwise whitespace gets collapsed (as it is when HTML is rendered) |
| $PROTECTED | In a block marked as PROTECTED |
| $KEEP_ENTITIES | Don't decode HTML entities |

=cut

use strict;
use warnings;

our $NO_HTML       = 1 << 0;
our $NO_TML        = 1 << 1;
our $NO_BLOCK_TML  = 1 << 2;
our $NOP_ALL       = 1 << 3;
our $VERY_CLEAN    = 1 << 4;
our $BR2NL         = 1 << 5;
our $KEEP_WS       = 1 << 6;
our $PROTECTED     = 1 << 7;
our $KEEP_ENTITIES = 1 << 8;
our $IN_TABLE      = 1 << 9;

our $BLOCK_TML = $NO_BLOCK_TML;

my %cc = (
    'NBSP'   => 14,    # unbreakable space
    'NBBR'   => 15,    # para break required
    'CHECKn' => 16,    # require adjacent newline (\n or $NBBR)
    'CHECKs' => 17,    # require adjacent space character (' ' or $NBSP)
    'CHECKw' => 18,    # require adjacent whitespace (\s|$NBBR|$NBSP)
    'CHECK1' => 19,    # start of wiki-word
    'CHECK2' => 20,    # end of wiki-word
    'TAB'    => 21,    # list indent
    'PON'    => 22,    # protect on
    'POFF'   => 23,    # protect off
);

=pod

---++ Forced whitespace
These single-character shortcuts are used to assert the presence of
non-breaking whitespace.

| $NBSP | Non-breaking space |
| $NBBR | Non-breaking linebreak |

=cut

our $NBSP = chr( $cc{NBSP} );
our $NBBR = chr( $cc{NBBR} );

=pod

---++ Inline Assertions
The generator works by expanding to "decorated" text, where the decorators
are characters below ' '. These characters act to express format
requirements - for example, the need to have a newline before some text,
or the need for a space. The generator sticks this format requirements into
the text stream, and they are then optimised down to the minimum in a post-
process.

| $CHECKn | there must be an adjacent newline (\n or $NBBR) |
| $CHECKs | there must be an adjacent space (' ' or $NBSP) |
| $CHECKw | There must be adjacent whitespace (\s or $NBBR or $NBSP) |
| $CHECK1 | Marks the start of an inline wikiword. |
| $CHECK2 | Marks the end of an inline wikiword. |
| $TAB    | Shorthand for an indent level in a list |

=cut

our $CHECKn   = chr( $cc{CHECKn} );
our $CHECKs   = chr( $cc{CHECKs} );
our $CHECKw   = chr( $cc{CHECKw} );
our $CHECK1   = chr( $cc{CHECK1} );
our $CHECK2   = chr( $cc{CHECK2} );
our $TAB      = chr( $cc{TAB} );
our $PON      = chr( $cc{PON} );
our $POFF     = chr( $cc{POFF} );
our $WS_NOTAB = qr/[$NBSP$NBBR$CHECKn$CHECKs$CHECKw$CHECK1$CHECK2\s]*/;
our $WS       = qr/[$NBSP$NBBR$CHECKn$CHECKs$CHECKw$CHECK1$CHECK2$TAB\s]*/;

=pod

---++ REs
REs for matching delimiters of wikiwords, must be consistent with TML2HTML.pm

| $STARTWW | Zero-width match for the start of a wikiword |
| $ENDWW | Zero-width match for the end of a wikiword |
| $PROTOCOL | match for a valid URL protocol e.g. http, mailto etc |

=cut

sub debugEncode {
    my $string = shift;
    while ( my ( $k, $v ) = each %cc ) {
        my $c = chr($v);
        $string =~ s/$c/\%$k/g;
    }
    return $string;
}

# Maps of tag types
our ( %SELFCLOSING, %EMPHTAG );

%SELFCLOSING = ( img => 1, br => 1 );

# Map that specifies tags to be renamed to a canonical name
%EMPHTAG = (
    b      => 'strong',
    i      => 'em',
    tt     => 'code',
    strong => 'strong',
    em     => 'em',
    code   => 'code',
);

1;
