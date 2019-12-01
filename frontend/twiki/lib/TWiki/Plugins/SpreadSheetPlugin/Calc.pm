# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2001-2018 Peter Thoeny, peter[at]thoeny.org and
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
#
# =========================
#
# This is part of TWiki's Spreadsheet Plugin.
#
# The code below is kept out of the main plugin module for
# performance reasons, so it doesn't get compiled until it
# is actually used.

package TWiki::Plugins::SpreadSheetPlugin::Calc;

use strict;
use Time::Local;
use Time::Local qw( timegm_nocheck timelocal_nocheck );  # Necessary for DOY

# =========================
my $web;
my $topic;
my $debug;
my $renderingWeb;
my @tableMatrix;
my $insideTABLE = 0;
my $cPos = -1;
my $rPos = -1;
my $escToken  = "\0";
my $escComma  = "\1"; # Single char escapes so that size functions work as expected
my $escOpenP  = "\2";
my $escCloseP = "\3";
my $escNewLn  = "\4";
my %varStore  = ();
my %listStore = ();
my $hashStore = {};
my $dontSpaceRE = '';
my $currencySymbol = '';
my @monArr = ( "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" );
my @wdayArr = ( "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" );
my %mon2num;
{
  my $count = 0;
  %mon2num = map { $_ => $count++ } @monArr;
}
my $funcRef;
my $recurseFunc = \&_recurseFunc;

# =========================
sub init
{
    ( $web, $topic, $debug ) = @_;

    # initialize variables, once per page view
    @tableMatrix = ();
    $insideTABLE = 0;
    $cPos = -1;
    $rPos = -1;
    %varStore = ();
    %listStore = ();
    $hashStore = {};
    $dontSpaceRE = '';
    $currencySymbol = '';

    # Module initialized
    TWiki::Func::writeDebug( "- TWiki::Plugins::SpreadSheetPlugin::Calc::init( $web.$topic )" ) if $debug;
    return 1;
}

# =========================
sub handleVarCALC
{
### my ( $text, $topic, $web ) = @_;   # do not uncomment, use $_[0], $_[1]... instead

    TWiki::Func::writeDebug( "- SpreadSheetPlugin::Calc::CALC( $_[2].$_[1] )" ) if $debug;

    @tableMatrix = ();
    $insideTABLE = 0;
    $cPos = -1;
    $rPos = -1;
    $web = $_[2];

    my @result = ();
    my $insidePRE = 0;
    my $line = "";
    my $before = "";
    my $cell = "";
    my @row = ();

    $_[0] =~ s/\r//go;
    $_[0] =~ s/\\\n//go;  # Join lines ending in "\"
    foreach( split( /\n/, $_[0] ) ) {

        # change state:
        m|<pre>|i       && ( $insidePRE = 1 );
        m|<verbatim>|i  && ( $insidePRE = 1 );
        m|</pre>|i      && ( $insidePRE = 0 );
        m|</verbatim>|i && ( $insidePRE = 0 );

        if( ! ( $insidePRE ) ) {

            if( /^\s*\|.*\|\s*$/ ) {
                # inside | table |
                if( ! $insideTABLE ) {
                    $insideTABLE = 1;
                    @tableMatrix = ();  # reset table matrix
                    $cPos = -1;
                    $rPos = -1;
                }
                $line = $_;
                $line =~ s/^(\s*\|)(.*)\|\s*$/$2/o;
                $before = $1;
                @row  = split( /\|/o, $line, -1 );
                $row[0] = '' unless( @row );
                push( @tableMatrix, [ @row ] );
                $rPos++;
                $line = "$before";
                for( $cPos = 0; $cPos < @row; $cPos++ ) {
                    $cell = $row[$cPos];
                    $cell =~ s/%CALC\{(.*?)\}%/doCalc($1)/geo;
                    $line .= "$cell|";
                }
                $cPos--; # Decrement to indicate proper last column number
                s/.*/$line/o;

            } else {
                # outside | table |
                if( $insideTABLE ) {
                    $insideTABLE = 0;
                }
                s/%CALC\{(.*?)\}%/doCalc($1)/geo;
            }
        }
        push( @result, $_ );
    }
    $_[0] = join( "\n", @result );
}

# =========================
sub doCalc
{
    my( $theAttributes ) = @_;
    my $text = &TWiki::Func::extractNameValuePair( $theAttributes );

    # Escape commas, parenthesis and newlines in tripple quoted strings
    $text =~ s/'''(.*?)'''/_escapeString($1)/geos;

    # For better performance, use a function reference when calling the recurse
    # functions, instead of an "if" statement within the _recurseFunc function
    if ( $text =~ /\n/ ) {
        # recursively evaluate functions, and remove white space around functions and parameters
        $recurseFunc = \&_recurseFuncCutWhitespace;
    } else {
        # recursively evaluate functions without removing white space (compatible with old spec)
        $recurseFunc = \&_recurseFunc;
    }

    # Add nesting level to parenthesis,
    # e.g. "A(B())" gets "A-esc-1(B-esc-2(-esc-2)-esc-1)"
    my $level = 0;
    $text =~ s/([\(\)])/_addNestingLevel($1, \$level)/geo;
    $text = _doFunc( "MAIN", $text );

    if( $insideTABLE && ( $rPos >= 0 ) && ( $cPos >= 0 ) ) {
        # update cell in table matrix
        $tableMatrix[$rPos][$cPos] = $text;
    }

    # Restore escaped strings
    $text =~ s/$escComma/,/go;
    $text =~ s/$escOpenP/\(/go;
    $text =~ s/$escCloseP/\)/go;
    $text =~ s/$escNewLn/\n/go;

    return $text;
}

# =========================
sub _escapeString
{
    my( $text ) = @_;
    $text =~ s/,/$escComma/go;
    $text =~ s/\(/$escOpenP/go;
    $text =~ s/\)/$escCloseP/go;
    $text =~ s/\n/$escNewLn/go;
    return $text;
}

# =========================
sub _addNestingLevel
{
    my( $theParen, $theLevelRef ) = @_;

    my $result = "";
    if( $theParen eq "(" ) {
        $$theLevelRef++;
        $result = "$escToken$$theLevelRef$theParen";
    } else {
        $result = "$escToken$$theLevelRef$theParen";
        $$theLevelRef-- if( $$theLevelRef > 0 );
    }
    return $result;
}

# =========================
sub _recurseFunc
{
    # Handle functions recursively
    $_[0] =~ s/\$([A-Z]+[A-Z0-9]*)$escToken([0-9]+)\((.*?)$escToken\2\)/_doFunc($1,$3)/geos;
    # Clean up unbalanced mess
    $_[0] =~ s/$escToken\-*[0-9]+([\(\)])/$1/go;
}

# =========================
sub _recurseFuncCutWhitespace
{
    # Handle functions recursively
    $_[0] =~ s/\s*\$([A-Z]+[A-Z0-9]*)$escToken([0-9]+)\(\s*(.*?)\s*$escToken\2\)\s*/_doFunc($1,$3)/geos;
    # Clean up unbalanced mess
    $_[0] =~ s/$escToken\-*[0-9]+([\(\)])/$1/go;
}

# =========================
sub _doFunc
{
    my( $theFunc, $theAttr ) = @_;

    $theAttr = "" unless( defined $theAttr );
    TWiki::Func::writeDebug( "- SpreadSheetPlugin::Calc::_doFunc: $theFunc( $theAttr ) start" ) if $debug;

    unless( $theFunc =~ /^(HASHEACH|IF|LISTEACH|LISTIF|LISTMAP|NOEXEC|WHILE)$/ ) {
        &$recurseFunc( $theAttr );
    }
    # else: delay the function handler to after parsing the parameters,
    # in which case handling functions and cleaning up needs to be done later

    my $result = "";
    my $f = $funcRef->{$theFunc};
    if( $f ) {
        $result = &$f( $theAttr );
    }
    else {
        $result = "func $theFunc not found. ";
    }

    TWiki::Func::writeDebug( "- SpreadSheetPlugin::Calc::_doFunc: $theFunc( $theAttr ) returns: $result" ) if $debug;
    return $result;
}

# =========================
$funcRef->{ABOVE} = \&_funcABOVE;
sub _funcABOVE
{
    my( $theAttr ) = @_;
    my $i = $cPos + 1;
    return "R0:C$i..R$rPos:C$i";
}

# =========================
$funcRef->{ABS} = \&_funcABS;
sub _funcABS
{
    my( $theAttr ) = @_;
    return abs( _getNumber( $theAttr ) );
}

# =========================
$funcRef->{ADDLIST} = \&_funcADDLIST;
sub _funcADDLIST
{
    my( $theAttr ) = @_;
    my( $name, $value ) = split( /,\s*/, $theAttr, 2 );
    $name = '' unless( defined $name );
    $value = '' unless( defined $value );
    $value = _listToDelimitedString( _getList( $value ) );
    $name =~ s/[^a-zA-Z0-9\_]//go;
    if( $name ) {
        my $old = $listStore{ $name };
        if( defined( $old ) && $old ne '' ) {
            $listStore{ $name } = "$old, $value";
        } else {
            $listStore{ $name } = $value;
        }
    }
    return '';
}

# =========================
$funcRef->{AND} = \&_funcAND;
sub _funcAND
{
    my( $theAttr ) = @_;
    my $result = 0;
    my @arr = _getListAsInteger( $theAttr );
    foreach my $i( @arr ) {
        unless( $i ) {
            $result = 0;
            last;
        }
        $result = 1;
    }
    return $result;
}

# =========================
$funcRef->{AVERAGE} = \&_funcAVERAGE;
$funcRef->{MEAN} = \&_funcAVERAGE;    #  undocumented - do not remove
sub _funcAVERAGE
{
    my( $theAttr ) = @_;
    my $result = 0;
    my $items = 0;
    my @arr = grep { /./ }
              grep { defined $_ }
              _getListAsFloat( $theAttr );
    foreach my $i ( @arr ) {
        $result += $i;
        $items++;
    }
    if( $items > 0 ) {
        $result = $result / $items;
    }
    return $result;
}

# =========================
$funcRef->{BIN2DEC} = \&_funcBIN2DEC;
sub _funcBIN2DEC
{
    my( $theAttr ) = @_;
    $theAttr =~ s/[^0-1]//g; # only binary digits
    $theAttr ||= 0;
    my $result = oct( '0b' . $theAttr );
    return $result;
}

# =========================
$funcRef->{BITXOR} = \&_funcBITXOR;
sub _funcBITXOR
{
    my( $theAttr ) = @_;
    my $ff = chr(255) x length( $theAttr );
    return $theAttr ^ $ff;
}

# =========================
$funcRef->{CEILING} = \&_funcCEILING;
sub _funcCEILING
{
    my( $theAttr ) = @_;
    my $i = _getNumber( $theAttr );
    my $result = int( $i );
    if( $i > 0 && $i != $result ) {
        $result += 1;
    }
    return $result;
}

# =========================
$funcRef->{CHAR} = \&_funcCHAR;
sub _funcCHAR
{
    my( $theAttr ) = @_;
    my $result = '';
    my $i = 0;
    if( $theAttr =~ /([0-9]+)/ ) {
        $i = $1;
    }
    $i = 255 if $i > 255;
    $i = 0 if $i < 0;
    return chr( $i );
}

# =========================
$funcRef->{CODE} = \&_funcCODE;
sub _funcCODE
{
    my( $theAttr ) = @_;
    return ord( $theAttr );
}

# =========================
$funcRef->{COLUMN} = \&_funcCOLUMN;
sub _funcCOLUMN
{
    my( $theAttr ) = @_;
    my $i = $theAttr || 0;
    return $cPos + $i + 1;
}

# =========================
$funcRef->{COUNTITEMS} = \&_funcCOUNTITEMS;
sub _funcCOUNTITEMS
{
    my( $theAttr ) = @_;
    my $result = '';
    my @arr = _getList( $theAttr );
    my %items = ();
    my $key = "";
    foreach $key ( @arr ) {
        $key =~ s/^\s*(.*?)\s*$/$1/o if( $key );
        if( $key ) {
            if( exists( $items{ $key } ) ) {
                $items{ $key }++;
            } else {
                $items{ $key } = 1;
            }
        }
    }
    foreach $key ( sort keys %items ) {
        $result .= "$key: $items{ $key }<br /> ";
    }
    $result =~ s|<br /> $||o;
    return $result;
}

# =========================
$funcRef->{COUNTSTR} = \&_funcCOUNTSTR;
sub _funcCOUNTSTR
{
    my( $theAttr ) = @_;
    my $result = 0;  # count any string
    my $i = 0;       # count string equal second attr
    my $list = $theAttr;
    my $str = "";
    if( $theAttr =~ /^(.*),\s*(.*?)$/ ) {  # greedy match for last comma
        $list = $1;
        $str = $2;
    }
    $str =~ s/\s*$//o;
    my @arr = _getList( $list );
    foreach my $cell ( @arr ) {
        if( defined $cell ) {
            $cell =~ s/^\s*(.*?)\s*$/$1/o;
            $result++ if( $cell );
            $i++ if( $cell eq $str );
        }
    }
    $result = $i if( $str );
    return $result;
}

# =========================
$funcRef->{DEC2BIN} = \&_funcDEC2BIN;
sub _funcDEC2BIN
{
    my( $theAttr ) = @_;
    my ( $num, $size ) = _getListAsInteger( $theAttr );
    $num ||= 0;
    my $format = '%';
    $format .= '0' . $size if( $size );
    $format .= 'b';
    my $result = sprintf( $format, $num );
    return $result;
}

# =========================
$funcRef->{DEC2HEX} = \&_funcDEC2HEX;
sub _funcDEC2HEX
{
    my( $theAttr ) = @_;
    my ( $num, $size ) = _getListAsInteger( $theAttr );
    $num ||= 0;
    my $format = '%';
    $format .= '0' . $size if( $size );
    $format .= 'X';
    my $result = sprintf( $format, $num );
    return $result;
}

# =========================
$funcRef->{DEC2OCT} = \&_funcDEC2OCT;
sub _funcDEC2OCT
{
    my( $theAttr ) = @_;
    my ( $num, $size ) = _getListAsInteger( $theAttr );
    $num ||= 0;
    my $format = '%';
    $format .= '0' . $size if( $size );
    $format .= 'o';
    my $result = sprintf( $format, $num );
    return $result;
}

# =========================
$funcRef->{DEF} = \&_funcDEF;
sub _funcDEF
{
    my( $theAttr ) = @_;
    # Format DEF(list) returns first defined cell
    # Added by MF 26/3/2002, fixed by PeterThoeny
    my @arr = _getList( $theAttr );
    my $result = '';
    foreach my $cell ( @arr ) {
        if( $cell ) {
            $cell =~ s/^\s*(.*?)\s*$/$1/o;
            if( $cell ) {
                $result = $cell;
                last;
            }
        }
    }
    return $result;
}

# =========================
$funcRef->{EMPTY} = \&_funcEMPTY;
sub _funcEMPTY
{
    my( $theAttr ) = @_;
    my $result = 1;
    $result = 0 if( length( $theAttr ) > 0 );
    return $result;
}

# =========================
$funcRef->{EQUAL} = \&_funcEQUAL;
sub _funcEQUAL
{
    my( $theAttr ) = @_;
    my $result = 0;
    my( $str1, $str2 ) = split( /,\s*/, $theAttr, 2 );
    $str1 = '' unless( $str1 );
    $str2 = '' unless( $str2 );
    $str1 =~ s/^\s+//os; # cut leading and trailing spaces
    $str1 =~ s/\s+$//os;
    $str2 =~ s/^\s+//os;
    $str2 =~ s/\s+$//os;
    $result = 1 if( lc( $str1 ) eq lc( $str2 ) );
    return $result;
}

# =========================
$funcRef->{EVAL} = \&_funcEVAL;
sub _funcEVAL
{
    my( $theAttr ) = @_;
    return _safeEvalPerl( $theAttr );
}

# =========================
$funcRef->{EVEN} = \&_funcEVEN;
sub _funcEVEN
{
    my( $theAttr ) = @_;
    return ( _getNumber( $theAttr ) + 1 ) % 2;
}

# =========================
$funcRef->{EXACT} = \&_funcEXACT;
sub _funcEXACT
{
    my( $theAttr ) = @_;
    my $result = 0;
    my( $str1, $str2 ) = split( /,\s*/, $theAttr, 2 );
    $str1 = '' unless( $str1 );
    $str2 = '' unless( $str2 );
    $str1 =~ s/^\s+//os; # cut leading and trailing spaces
    $str1 =~ s/\s+$//os;
    $str2 =~ s/^\s+//os;
    $str2 =~ s/\s+$//os;
    $result = 1 if( $str1 eq $str2 );
    return $result;
}

# =========================
$funcRef->{EXEC} = \&_funcEXEC;
sub _funcEXEC
{
    my( $theAttr ) = @_;
    # add nesting level escapes
    my $level = 0;
    my $result = $theAttr;
    $result =~ s/([\(\)])/_addNestingLevel($1, \$level)/geo;
    # execute functions in attribute recursively and clean up unbalanced parenthesis
    &$recurseFunc( $result );
    return $result;
}

# =========================
$funcRef->{EXISTS} = \&_funcEXISTS;
sub _funcEXISTS
{
    my( $theAttr ) = @_;
    my $result = TWiki::Func::topicExists( $web, $theAttr );
    $result = 0 unless( $result );
    return $result;
}

# =========================
$funcRef->{EXP} = \&_funcEXP;
sub _funcEXP
{
    my( $theAttr ) = @_;
    return exp( _getNumber( $theAttr ) );
}

# =========================
$funcRef->{FILTER} = \&_funcFILTER;
sub _funcFILTER
{
    my( $theAttr ) = @_;
    my $result = '';
    my( $filter, $string ) = split ( /,\s*/, $theAttr, 2 );
    if( defined $string ) {
      $filter =~ s/\$comma/,/g;
      $filter =~ s/\$sp/ /g;
      eval '$string =~ s/$filter//go';
      $result = $string;
    }
    return $result;
}

# =========================
$funcRef->{FIND} = \&_funcFIND;
sub _funcFIND
{
    my( $theAttr ) = @_;
    my( $searchString, $string, $pos ) = split( /,\s*/, $theAttr, 3 );
    my $result = 0;
    $searchString = '' unless( defined $searchString );
    $string = '' unless( defined $string );
    $pos--;
    $pos = 0 if( $pos < 0 );
    pos( $string ) = $pos if( $pos );
    $searchString = quotemeta( $searchString );
    # using zero width lookahead '(?=...)' to keep pos at the beginning of match
    if( eval '$string =~ m/(?=$searchString)/g' && $string ) {
        $result = pos( $string ) + 1;
    }
    return $result;
}

# =========================
$funcRef->{FLOOR} = \&_funcFLOOR;
sub _funcFLOOR
{
    my( $theAttr ) = @_;
    my $i = _getNumber( $theAttr );
    my $result = int( $i );
    if( $i < 0 && $i != $result ) {
        $result -= 1;
    }
    return $result;
}

# =========================
$funcRef->{FORMAT} = \&_funcFORMAT;
sub _funcFORMAT
{
    my( $theAttr ) = @_;

    # Format FORMAT(TYPE, precision, value) returns formatted value -- JimStraus - 05 Jan 2003
    my( $format, $res, $value )  = split( /,\s*/, $theAttr );
    $format =~ s/^\s*(.*?)\s*$/$1/os; #Strip leading and trailing spaces
    $res =~ s/^\s*(.*?)\s*$/$1/os;
    $value =~ s/^\s*(.*?)\s*$/$1/os;
    my $result = '';
    if( $format =~ /^(DOLLAR|CURRENCY)$/ ) {
        unless( $currencySymbol ) {
            $currencySymbol = TWiki::Func::getPreferencesValue( "CURRENCYSYMBOL" )
              || TWiki::Func::getPreferencesValue( "SPREADSHEETPLUGIN_CURRENCYSYMBOL" )
              || '$';
        }
        my $symbol = '$';
        $symbol = $currencySymbol if( $format eq "CURRENCY" );
        my $neg = 1 if $value < 0;
        $value = abs($value);
        $result = sprintf("%0.${res}f", $value);
        my $temp = reverse $result;
        $temp =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
        $result = $symbol . (scalar reverse $temp);
        $result = "(".$result.")" if $neg;
    } elsif( $format eq "COMMA" ) {
        $result = sprintf("%0.${res}f", $value);
        my $temp = reverse $result;
        $temp =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
        $result = scalar reverse $temp;
    } elsif( $format eq "PERCENT" ) {
        $result = sprintf("%0.${res}f%%", $value * 100);
    } elsif( $format eq "NUMBER" ) {
        $result = sprintf("%0.${res}f", $value);
    } elsif( $format eq "K" ) {
        $result = sprintf("%0.${res}f K", $value / 1024);
    } elsif( $format eq "KB" ) {
        $result = sprintf("%0.${res}f KB", $value / 1024);
    } elsif ($format eq "MB") {
        $result = sprintf("%0.${res}f MB", $value / (1024 * 1024));
    } elsif( $format =~ /^KBMB/ ) {
        $value /= 1024;
        my @lbls = ( "MB", "GB", "TB", "PB", "EB", "ZB" );
        my $lbl = "KB";
        while( $value >= 1024 && @lbls ) {
            $value /= 1024;
            $lbl = shift @lbls;
        }
        $result = sprintf("%0.${res}f", $value) . " $lbl";
    } else {
        # FORMAT not recognized, just return value
        $result = $value;
    }
    return $result;
}

# =========================
$funcRef->{FORMATGMTIME} = \&_funcFORMATGMTIME;
sub _funcFORMATGMTIME
{
    my( $theAttr ) = @_;
    my $result = '';
    my( $time, $str ) = split( /,\s*/, $theAttr, 2 );
    if( $time =~ /([0-9]+)/ ) {
        $time = $1;
    } else {
        $time = time();
    }
    return _serial2date( $time, $str, 1 );
}

# =========================
$funcRef->{FORMATTIME} = \&_funcFORMATTIME;
sub _funcFORMATTIME
{
    my( $theAttr ) = @_;
    my( $time, $str ) = split( /,\s*/, $theAttr, 2 );
    if( $time =~ /([0-9]+)/ ) {
        $time = $1;
    } else {
        $time = time();
    }
    my $isGmt = 0;
    $isGmt = 1 if( $str =~ m/ gmt/i );
    return _serial2date( $time, $str, $isGmt );
}

# =========================
$funcRef->{FORMATTIMEDIFF} = \&_funcFORMATTIMEDIFF;
sub _funcFORMATTIMEDIFF
{
    my( $theAttr ) = @_;
    my( $scale, $prec, $time, $option ) = split( /,\s*/, $theAttr, 4 );
    $scale |= '';
    $prec = int( _getNumber( $prec ) - 1 );
    $prec = 0 if( $prec < 0 );
    $time = _getNumber( $time );
    $time = 0 if( $time < 0 );
    $option |= '';
    my @unit  = ( 0, 0, 0, 0, 0, 0 ); # sec, min, hours, days, month, years
    my @factor = ( 1, 60, 60, 24, 30.4166, 12 ); # sec, min, hours, days, month, years
    my @singular = ( 'second',  'minute',  'hour',  'day',  'month', 'year' );
    my @plural =   ( 'seconds', 'minutes', 'hours', 'days', 'months', 'years' );
    my $min = 0;
    my $max = $prec;
    if( $scale =~ /^min/i ) {
        $min = 1;
        $unit[1] = $time;
    } elsif( $scale =~ /^hou/i ) {
        $min = 2;
        $unit[2] = $time;
    } elsif( $scale =~ /^day/i ) {
        $min = 3;
        $unit[3] = $time;
    } elsif( $scale =~ /^mon/i ) {
        $min = 4;
        $unit[4] = $time;
    } elsif( $scale =~ /^yea/i ) {
        $min = 5;
        $unit[5] = $time;
    } else {
        $unit[0] = $time;
    }
    my @arr = ();
    my $i = 0;
    my $val1 = 0;
    my $val2 = 0;
    for( $i = $min; $i < 5; $i++ ) {
        $val1 = int($unit[$i]);
        $val2 = $unit[$i+1] = int($val1 / $factor[$i+1]);
        $val1 = $unit[$i] = $val1 - int($val2 * $factor[$i+1]);

        push( @arr, "$val1 $singular[$i]" ) if( $val1 == 1 );
        push( @arr, "$val1 $plural[$i]" )   if( $val1 > 1 );
    }
    push( @arr, "$val2 $singular[$i]" ) if( $val2 == 1 );
    push( @arr, "$val2 $plural[$i]" )   if( $val2 > 1 );
    push( @arr, "0 $plural[$min]" )   unless( @arr );
    my @reverse = reverse( @arr );
    $#reverse = $prec if( @reverse > $prec );
    my $result = join( ', ', @reverse );
    if( $option eq 's' ) {
        # short format: 1 y, 2 mon, 3 d, 4 h, 5 min, 6 sec
        $result =~ s/([0-9]) (sec|min|mon)[a-z]*/$1~$2/g;
        $result =~ s/([0-9]) ([a-z])[a-z]*/$1 $2/g;
        $result =~ s/~/ /g;
    } elsif( $option eq 'c' ) {
        # compact format: 1y 2mon 3d 4h 5m 6s
        $result =~ s/([0-9]) (mon)[a-z]*/$1$2/g;
        $result =~ s/([0-9]) ([a-z])[a-z]*/$1$2/g;
        $result =~ s/,//g;
    } else {
        $result =~ s/(.+)\, /$1 and /;
    }
    return $result;
}

# =========================
$funcRef->{GET} = \&_funcGET;
sub _funcGET
{
    my( $theAttr ) = @_;
    my $name = $theAttr;
    $name =~ s/[^a-zA-Z0-9\_]//go;
    my $result = $varStore{ $name } if( $name );
    $result = "" unless( defined( $result ) );
    return $result;
}

# =========================
$funcRef->{GETHASH} = \&_funcGETHASH;
sub _funcGETHASH
{
    my( $theAttr ) = @_;
    my( $name, $key ) = split( /,\s*/, $theAttr, 2 );
    $name  = '' unless( defined $name );
    $name  =~ s/[^\w\.\/]//go;
    $key   = '' unless( defined $key );
    my $result = '';
    if( $name ne '' && $key ne '' ) {
        if( exists $hashStore->{$name} && exists $hashStore->{$name}{$key} ) {
            $result = $hashStore->{$name}{$key};
        }
    } elsif( $name ne '' ) {
        if( exists $hashStore->{$name} ) {
            $result = join( ', ', sort keys %{ $hashStore->{$name} } );
        }
    } else {
        $result = join( ', ', sort keys %$hashStore );
    }
    return $result;
}

# =========================
$funcRef->{GETLIST} = \&_funcGETLIST;
sub _funcGETLIST
{
    my( $theAttr ) = @_;
    my $name = $theAttr;
    $name =~ s/[^a-zA-Z0-9\_]//go;
    my $result = $listStore{ $name } if( $name );
    $result = "" unless( defined( $result ) );
    return $result;
}

# =========================
$funcRef->{HASH2LIST} = \&_funcHASH2LIST;
sub _funcHASH2LIST
{
    my( $theAttr ) = @_;
    my( $name, $format ) = split( /,\s*/, $theAttr, 2 );
    $name  = '' unless( defined $name );
    $name  =~ s/[^\w\.\/]//go;
    return '' if( $name eq '' || ! exists $hashStore->{$name} );
    $format   = '$key, $value' unless( defined $format );
    my $result = join( ', ',
        map {
            my $item = $format;
            $item =~ s/\$key/$_/g;
            $item =~ s/\$value/$hashStore->{$name}{$_}/g;
            $item =~ s/\$comma/, /g;
            $item;
        }
        sort
        keys %{ $hashStore->{$name} }
      );
    return $result;
}

# =========================
$funcRef->{HASHCOPY} = \&_funcHASHCOPY;
sub _funcHASHCOPY
{
    my( $theAttr ) = @_;
    my( $from, $to ) = split( /,\s*/, $theAttr, 2 );
    $from  = '' unless( defined $from );
    $from  =~ s/[^\w\.\/]//go;
    return '' if( $from eq '' || ! exists $hashStore->{$from} );
    $to  = '' unless( defined $to );
    $to  =~ s/[^\w\.\/]//go;
    return '' if( $to eq '' );
    %{ $hashStore->{$to} } = %{ $hashStore->{$from} };
    return '';
}

# =========================
$funcRef->{HASHEACH} = \&_funcHASHEACH;
sub _funcHASHEACH
{
    my( $theAttr ) = @_;
    my( $action, $name ) = _properSplit( $theAttr, 2 );
    $action = '' unless( defined $action );
    $name   = '' unless( defined $name );
    $name   =~ s/[^\w\.\/]//go;
    &$recurseFunc( $name );
    return '' if( $name eq '' || ! exists $hashStore->{$name} );
    # with delay, handle functions recursively and clean up unbalanced parenthesis
    my $i = 0;
    for my $key ( sort keys %{ $hashStore->{$name} } ) {
        $i++;
        my $value  = $hashStore->{$name}{$key};
        my $item = $action;
        $item =~ s/\$index/$i/go;
        $item =~ s/\$key/$key/go;
        $item .= $value unless( $item =~ s/\$(item|value)/$value/go );
        &$recurseFunc( $item );
        $hashStore->{$name}{$key} = $item;
    }
    return '';
}

# =========================
$funcRef->{HASHEXISTS} = \&_funcHASHEXISTS;
sub _funcHASHEXISTS
{
    my( $theAttr ) = @_;
    my( $name, $key ) = split( /,\s*/, $theAttr, 2 );
    $name  = '' unless( defined $name );
    $name  =~ s/[^\w\.\/]//go;
    $key   = '' unless( defined $key );
    my $result = 0;
    if( $name ne '' && $key ne '' ) {
        $result = 1 if( exists $hashStore->{$name} && exists $hashStore->{$name}{$key} );
    } elsif( $name ne '' ) {
        $result = 1 if( exists $hashStore->{$name} );
    }
    return $result;
}

# =========================
$funcRef->{HASHREVERSE} = \&_funcHASHREVERSE;
sub _funcHASHREVERSE
{
    my( $theAttr ) = @_;
    my( $name, $key ) = split( /,\s*/, $theAttr, 2 );
    $name  = '' unless( defined $name );
    $name  =~ s/[^\w\.\/]//go;
    return '' if( $name eq '' || ! exists $hashStore->{$name} );
    %{ $hashStore->{$name} } = reverse %{ $hashStore->{$name} };
    return '';
}

# =========================
$funcRef->{HEX2DEC} = \&_funcHEX2DEC;
sub _funcHEX2DEC
{
    my( $theAttr ) = @_;
    $theAttr =~ s/[^0-9A-Fa-f]//g; # only hex numbers
    $theAttr ||= 0;
    my $result = hex( $theAttr );
    return $result;
}

# =========================
$funcRef->{HEXDECODE} = \&_funcHEXDECODE;
sub _funcHEXDECODE
{
    my( $theAttr ) = @_;
    $theAttr =~ s/[^0-9A-Fa-f]//g; # only hex numbers
    $theAttr =~ s/.$// if( length( $theAttr ) % 2 ); # must be set of two
    return pack( "H*", $theAttr );
}

# =========================
$funcRef->{HEXENCODE} = \&_funcHEXENCODE;
sub _funcHEXENCODE
{
    my( $theAttr ) = @_;
    return uc( unpack( "H*", $theAttr ) );
}

# =========================
$funcRef->{IF} = \&_funcIF;
sub _funcIF
{
    my( $theAttr ) = @_;

    # IF(condition, value if true, value if false)
    my( $condition, $str1, $str2 ) = _properSplit( $theAttr, 3 );
    # with delay, handle functions in condition recursively and clean up unbalanced parenthesis
    &$recurseFunc( $condition );
    $condition =~ s/^\s*(.*?)\s*$/$1/os;
    my $result = _safeEvalPerl( $condition );
    unless( $result =~ /^ERROR/ ) {
        if( $result ) {
            $result = $str1;
        } else {
            $result = $str2;
        }
        $result = "" unless( defined( $result ) );
        # with delay, handle functions in result recursively and clean up unbalanced parenthesis
        &$recurseFunc( $result );

    } # else return error message

    return $result;
}

# =========================
$funcRef->{INSERTSTRING} = \&_funcINSERTSTRING;
sub _funcINSERTSTRING
{
    my( $theAttr ) = @_;
    my( $string, $start, $new ) = split ( /,\s*/, $theAttr, 3 );
    $start = _getNumber( $start );
    eval 'substr( $string, $start, 0, $new )';
    return $string;
}

# =========================
$funcRef->{INT} = \&_funcINT;
sub _funcINT
{
    my( $theAttr ) = @_;
    my $result = _safeEvalPerl( $theAttr );
    unless( $result =~ /^ERROR/ ) {
        $result = int( _getNumber( $result ) );
    }
    return $result;
}

# =========================
$funcRef->{ISDIGIT} = \&_funcISDIGIT;
sub _funcISDIGIT
{
    my( $theAttr ) = @_;
    my $regex = ($TWiki::regex{numeric}) ? qr/[$TWiki::regex{numeric}]+/o : '[[:digit:]]+';
    return ( $theAttr =~ m/^$regex$/o ) ? 1 : 0;
}

# =========================
$funcRef->{ISLOWER} = \&_funcISLOWER;
sub _funcISLOWER
{
    my( $theAttr ) = @_;
    my $regex = ($TWiki::regex{lowerAlpha}) ? qr/[$TWiki::regex{lowerAlpha}]+/o : '[[:lower:]]+';
    return ( $theAttr =~ m/^$regex$/o ) ? 1 : 0;
}


# =========================
$funcRef->{ISUPPER} = \&_funcISUPPER;
sub _funcISUPPER
{
    my( $theAttr ) = @_;
    my $regex = ($TWiki::regex{upperAlpha}) ? qr/[$TWiki::regex{upperAlpha}]+/o : '[[:upper:]]+';
    return ( $theAttr =~ m/^$regex$/o ) ? 1 : 0;
}

# =========================
$funcRef->{ISWIKIWORD} = \&_funcISWIKIWORD;
sub _funcISWIKIWORD
{
    my( $theAttr ) = @_;
    my $regex = ($TWiki::regex{wikiWordRegex}) ? $TWiki::regex{wikiWordRegex} :
                '[[:upper:]]+[[:lower:][:digit:]]+[[:upper:]]+[[:alpha:][:digit:]]*';
    return ( $theAttr =~ m/^$regex$/o ) ? 1 : 0;
}

# =========================
$funcRef->{LEFT} = \&_funcLEFT;
sub _funcLEFT
{
    my( $theAttr ) = @_;
    my $i = $rPos + 1;
    return "R$i:C0..R$i:C$cPos";
}

# =========================
$funcRef->{LEFTSTRING} = \&_funcLEFTSTRING;
sub _funcLEFTSTRING
{
    my( $theAttr ) = @_;
    my $result = '';
    my( $string, $num ) = split ( /,\s*/, $theAttr, 2 );
    $string = '' unless( defined $string );
    $num = 1 unless( $num );
    my $start = 0;
    eval '$result = substr( $string, $start, $num )';
    return $result;
}

# =========================
$funcRef->{LENGTH} = \&_funcLENGTH;
sub _funcLENGTH
{
    my( $theAttr ) = @_;
    return length( $theAttr );
}

# =========================
$funcRef->{LIST} = \&_funcLIST;
sub _funcLIST
{
    my( $theAttr ) = @_;
    my @arr = _getList( $theAttr );
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LIST2HASH} = \&_funcLIST2HASH;
sub _funcLIST2HASH
{
    my( $theAttr ) = @_;
    my( $name, $str ) = _properSplit( $theAttr, 2 );
    $name  = '' unless( defined $name );
    $name  =~ s/[^\w\.\/]//go;
    return '' if( $name eq '' );
    $str = "" unless( defined $str );
    my @arr = _getList( $str );
    while( my $key = shift @arr ) {
        my $value = shift @arr;
        last unless( defined $value );
        $key = '' unless( defined $key );
        unless( $key eq '' ) {
            $hashStore->{$name}{$key} = $value;
        }
    }
    return '';
}

# =========================
$funcRef->{LISTIF} = \&_funcLISTIF;
sub _funcLISTIF
{
    my( $theAttr ) = @_;
    # LISTIF(cmd, item 1, item 2, ...)
    my( $cmd, $str ) = _properSplit( $theAttr, 2 );
    $cmd = "" unless( defined( $cmd ) );
    $cmd =~ s/^\s*(.*?)\s*$/$1/os;
    $str = "" unless( defined( $str ) );
    # with delay, handle functions in result recursively and clean up unbalanced parenthesis
    &$recurseFunc( $str );
    my $item = "";
    my $eval = "";
    my $i = 0;
    my @arr =
        grep { ! /^TWIKI_GREP_REMOVE$/ }
        map {
            $item = $_;
            $_ = $cmd;
            $i++;
            s/\$index/$i/go;
            s/\$item/$item/go;
            &$recurseFunc( $_ );
            $eval = _safeEvalPerl( $_ );
            if( $eval =~ /^ERROR/ ) {
                $_ = $eval;
            } elsif( $eval ) {
                $_ = $item;
            } else {
                $_ = "TWIKI_GREP_REMOVE";
            }
        } _getList( $str );
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LISTITEM} = \&_funcLISTITEM;
sub _funcLISTITEM
{
    my( $theAttr ) = @_;
    my $result = '';
    my( $index, $str ) = _properSplit( $theAttr, 2 );
    $index = _getNumber( $index );
    $str = "" unless( defined( $str ) );
    my @arr = _getList( $str );
    my $size = scalar @arr;
    if( $index && $size ) {
        $index-- if( $index > 0 );                 # documented index starts at 1
        $index = $size + $index if( $index < 0 );  # start from back if negative
        $result = $arr[$index] if( ( $index >= 0 ) && ( $index < $size ) );
    }
    return $result;
}

# =========================
$funcRef->{LISTJOIN} = \&_funcLISTJOIN;
sub _funcLISTJOIN
{
    my( $theAttr ) = @_;
    my( $sep, $str ) = _properSplit( $theAttr, 2 );
    $str = "" unless( defined( $str ) );
    my $result = _listToDelimitedString( _getList( $str ) );
    $sep = ", " if( !defined $sep || $sep eq '' );
    $sep =~ s/\$comma/,/go;
    $sep =~ s/\$sp/ /go;
    $sep =~ s/\$(nop|empty)//go;
    $sep =~ s/\$n/\n/go;
    $result =~ s/, */$sep/go;
    return $result;
}

# =========================
$funcRef->{LISTEACH} = \&_funcLISTEACH;
$funcRef->{LISTMAP} = \&_funcLISTEACH;
sub _funcLISTEACH
{
    my( $theAttr ) = @_;
    # LISTEACH(action, item 1, item 2, ...)
    my( $action, $str ) = _properSplit( $theAttr, 2 );
    $action = "" unless( defined( $action ) );
    $str = "" unless( defined( $str ) );
    # with delay, handle functions in result recursively and clean up unbalanced parenthesis
    &$recurseFunc( $str );
    my $item = "";
    my $i = 0;
    my @arr =
        map {
            $item = $_;
            $_ = $action;
            $i++;
            s/\$index/$i/go;
            $_ .= $item unless( s/\$item/$item/go );
            &$recurseFunc( $_ );
            $_
        } _getList( $str );
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LISTNONEMPTY} = \&_funcLISTNONEMPTY;
sub _funcLISTNONEMPTY
{
    my( $theAttr ) = @_;
    my @arr = grep { /./ } _getList( $theAttr );
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LISTRAND} = \&_funcLISTRAND;
sub _funcLISTRAND
{
    my( $theAttr ) = @_;
    my $result = '';
    my @arr = _getList( $theAttr );
    my $size = scalar @arr;
    if( $size > 0 ) {
        my $i = int( rand( $size ) );
        $result = $arr[$i];
    }
    return $result;
}

# =========================
$funcRef->{LISTREVERSE} = \&_funcLISTREVERSE;
sub _funcLISTREVERSE
{
    my( $theAttr ) = @_;
    my @arr = reverse _getList( $theAttr );
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LISTSHUFFLE} = \&_funcLISTSHUFFLE;
sub _funcLISTSHUFFLE
{
    my( $theAttr ) = @_;
    my @arr = _getList( $theAttr );
    my $size = scalar @arr;
    if( $size > 1 ) {
        for( my $i = $size; $i--; ) {
            my $j = int( rand( $i + 1 ) );
            next if( $i == $j );
            @arr[$i, $j] = @arr[$j, $i];
        }
    }
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LISTSIZE} = \&_funcLISTSIZE;
sub _funcLISTSIZE
{
    my( $theAttr ) = @_;
    my @arr = _getList( $theAttr );
    return scalar @arr;
}

# =========================
$funcRef->{LISTSORT} = \&_funcLISTSORT;
sub _funcLISTSORT
{
    my( $theAttr ) = @_;
    my $isNumeric = 1;
    my @arr = map {
        s/^\s*//o;
        s/\s*$//o;
        $isNumeric = 0 unless( $_ =~ /^[\+\-]?[0-9\.]+$/ );
        $_
    } _getList( $theAttr );
    if( $isNumeric ) {
        @arr = sort { $a <=> $b } @arr;
    } else {
        @arr = sort @arr;
    }
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LISTTRUNCATE} = \&_funcLISTTRUNCATE;
sub _funcLISTTRUNCATE
{
    my( $theAttr ) = @_;
    my $result = '';
    my( $index, $str ) = _properSplit( $theAttr, 2 );
    $index = int( _getNumber( $index ) );
    $str = "" unless( defined( $str ) );
    my @arr = _getList( $str );
    my $size = scalar @arr;
    if( $index > 0 ) {
        $index = $size if( $index > $size );
        $#arr = $index - 1;
        $result = _listToDelimitedString( @arr );
    } elsif( $index < 0 ) {
        $index = - $size if( $index < - $size );
        splice( @arr, 0, $size + $index );
        $result = _listToDelimitedString( @arr );
    } #else result = '';
    return $result;
}

# =========================
$funcRef->{LISTUNIQUE} = \&_funcLISTUNIQUE;
sub _funcLISTUNIQUE
{
    my( $theAttr ) = @_;
    my %seen = ();
    my @arr = grep { ! $seen{$_} ++ } _getList( $theAttr );
    return _listToDelimitedString( @arr );
}

# =========================
$funcRef->{LN} = \&_funcLN;
sub _funcLN
{
    my( $theAttr ) = @_;
    return log(_getNumber( $theAttr ) );
}

# =========================
$funcRef->{LOG} = \&_funcLOG;
sub _funcLOG
{
    my( $theAttr ) = @_;
    my( $num, $base ) = split( /,\s*/, $theAttr, 2 );
    $num = _getNumber( $num );
    $base = _getNumber( $base );
    $base = 10 if( $base <= 0 );
    return log( $num ) / log( $base );
}

# =========================
$funcRef->{LOWER} = \&_funcLOWER;
sub _funcLOWER
{
    my( $theAttr ) = @_;
    return lc( $theAttr );
}

# =========================
$funcRef->{MAIN} = \&_funcMAIN;
sub _funcMAIN
{
    my( $theAttr ) = @_;
    return $theAttr;
}

# =========================
$funcRef->{MAX} = \&_funcMAX;
sub _funcMAX
{
    my( $theAttr ) = @_;
    my @arr = sort { $a <=> $b }
              grep { /./ }
              grep { defined $_ }
              _getListAsFloat( $theAttr );
    return $arr[$#arr] if( scalar @arr );
    return '';
}

# =========================
$funcRef->{MEDIAN} = \&_funcMEDIAN;
sub _funcMEDIAN
{
    my( $theAttr ) = @_;
    my $result = '';
    my @arr = sort { $a <=> $b } grep { defined $_ } _getListAsFloat( $theAttr );
    my $i = @arr;
    if( ( $i % 2 ) > 0 ) {
        $result = $arr[$i/2];
    } elsif( $i ) {
        $i /= 2;
        $result = ( $arr[$i] + $arr[$i-1] ) / 2;
    }
    return $result;
}

# =========================
$funcRef->{MIN} = \&_funcMIN;
sub _funcMIN
{
    my( $theAttr ) = @_;
    my @arr = sort { $a <=> $b }
              grep { /./ }
              grep { defined $_ }
              _getListAsFloat( $theAttr );
    return $arr[0] if( scalar @arr );
    return '';
}

# =========================
$funcRef->{MOD} = \&_funcMOD;
sub _funcMOD
{
    my( $theAttr ) = @_;
    my $result = 0;
    my( $num1, $num2 ) = split( /,\s*/, $theAttr, 2 );
    $num1 = _getNumber( $num1 );
    $num2 = _getNumber( $num2 );
    if( $num1 && $num2 ) {
        $result = $num1 % $num2;
    }
    return $result;
}

# =========================
$funcRef->{NOEXEC} = \&_funcNOEXEC;
sub _funcNOEXEC
{
    my( $theAttr ) = @_;
    return $theAttr;
}

# =========================
$funcRef->{NOP} = \&_funcNOP;
sub _funcNOP
{
    my( $theAttr ) = @_;
    # pass everything through, this will allow plugins to defy plugin order
    # for example the %SEARCH{}% variable
    $theAttr =~ s/\$per(cnt)?/%/g;
    $theAttr =~ s/\$quot/"/g;
    return $theAttr;
}

# =========================
$funcRef->{NOT} = \&_funcNOT;
sub _funcNOT
{
    my( $theAttr ) = @_;
    my $result = 1;
    $result = 0 if( _getNumber( $theAttr ) );
    return $result;
}

# =========================
$funcRef->{NOTE} = \&_funcNOTE;
sub _funcNOTE
{
    return '';
}

# =========================
$funcRef->{OCT2DEC} = \&_funcOCT2DEC;
sub _funcOCT2DEC
{
    my( $theAttr ) = @_;
    $theAttr =~ s/[^0-7]//g; # only octal digits
    $theAttr ||= 0;
    my $result = oct( $theAttr );
    return $result;
}

# =========================
$funcRef->{ODD} = \&_funcODD;
sub _funcODD
{
    my( $theAttr ) = @_;
    return _getNumber( $theAttr ) % 2;
}

# =========================
$funcRef->{OR} = \&_funcOR;
sub _funcOR
{
    my( $theAttr ) = @_;
    my $result = 0;
    my @arr = _getListAsInteger( $theAttr );
    foreach my $i( @arr ) {
        if( $i ) {
            $result = 1;
            last;
        }
    }
    return $result;
}

# =========================
$funcRef->{PERCENTILE} = \&_funcPERCENTILE;
sub _funcPERCENTILE
{
    my( $theAttr ) = @_;
    my( $percentile, $set ) = split( /,\s*/, $theAttr, 2 );
    $set = '' unless( defined $set );
    my @arr = sort { $a <=> $b } grep { defined $_ } _getListAsFloat( $set );
    my $result = 0;
    my $size = scalar( @arr );
    if( $size > 0 ) {
        my $i = $percentile / 100 * ( $size + 1 );
        my $iInt = int( $i );
        if( $i <= 1 ) {
            $result = $arr[0];
        } elsif( $i >= $size ) {
            $result = $arr[$size-1];
        } elsif( $i == $iInt ) {
            $result = $arr[$i-1];
        } else {
            # interpolate beween neighbors # Example: $i = 7.25
            my $r1 = $iInt + 1 - $i;       # 0.75 = 7 + 1 - 7.25
            my $r2 = 1 - $r1;              # 0.25 = 1 - 0.75
            my $x1 = $arr[$iInt-1];
            my $x2 = $arr[$iInt];
            $result = ($r1 * $x1) + ($r2 * $x2);
        }
    }
    return $result;
}

# =========================
$funcRef->{PI} = \&_funcPI;
sub _funcPI
{
    return 3.1415926535897932384;
}

# =========================
$funcRef->{MULT} = \&_funcPRODUCT;   # MULT is deprecated (no not remove)
$funcRef->{PRODUCT} = \&_funcPRODUCT;
sub _funcPRODUCT
{
    my( $theAttr ) = @_;
    my @arr = _getListAsFloat( $theAttr );
    my $result = 1;
    foreach my $i ( @arr ) {
        $result *= $i  if defined $i;
    }
    return $result;
}

# =========================
$funcRef->{PROPER} = \&_funcPROPER;
sub _funcPROPER
{
    my( $theAttr ) = @_;
    # FIXME: I18N
    my $result = lc( $theAttr );
    $result =~ s/(^|[^a-z])([a-z])/$1 . uc($2)/geo;
    return $result;
}

# =========================
$funcRef->{PROPERSPACE} = \&_funcPROPERSPACE;
sub _funcPROPERSPACE
{
    my( $theAttr ) = @_;
    return _properSpace( $theAttr );
}

# =========================
$funcRef->{RAND} = \&_funcRAND;
sub _funcRAND
{
    my( $theAttr ) = @_;
    my $max = _getNumber( $theAttr );
    $max = 1 if( $max <= 0 );
    return rand( $max );
}

# =========================
$funcRef->{RANDSTRING} = \&_funcRANDSTRING;
sub _funcRANDSTRING
{
    my( $theAttr ) = @_;
    my( $chars, $format ) = split( /,\s*/, $theAttr, 2 );
    $chars = '' unless defined( $chars );
    $chars =~ s/(.)\.\.(.)/_expandRange($1, $2)/ge;
    my @pool = split( //, $chars );
    @pool = ( 'a'..'z', 'A'..'Z', '0'..'9', '_' ) unless( scalar @pool );
    $format = 'xxxxxxxx' unless( $format );
    if( $format =~ m/^([0-9]*)$/ ) {
        my $num = _getNumber( $format );
        $num = 8 if( $num < 1 );
        $num = 1024 if( $num > 1024 );
        $format = 'x' x $num;
    }
    my $result = '';
    foreach my $ch ( split( //, $format ) ) {
        if( $ch eq 'x' ) {
            $result .= $pool[rand @pool];
        } else {
            $result .= $ch;
        }
    }
    return $result;
}

# =========================
sub _expandRange
{
    my( $lowCh, $highCh ) = @_;
    my $text = "$1$2"; # in case out of range, return just low char and high char
    if( ord $highCh > ord $lowCh ) {
        $text = join( '', ( $lowCh..$highCh ) );
    }
    return $text;
}

# =========================
$funcRef->{REPEAT} = \&_funcREPEAT;
sub _funcREPEAT
{
    my( $theAttr ) = @_;
    my( $str, $num ) = split( /,\s*/, $theAttr, 2 );
    $str = "" unless( defined( $str ) );
    $num = _getNumber( $num );
    return "$str" x $num;
}

# =========================
$funcRef->{REPLACE} = \&_funcREPLACE;
sub _funcREPLACE
{
    my( $theAttr ) = @_;
    my( $string, $start, $num, $replace ) = split ( /,\s*/, $theAttr, 4 );
    $string = '' unless( defined $string );
    $start = 0 unless( $start );
    $start-- if( $start > 0 );
    $num = 0 unless( $num );
    $replace = "" unless( defined $replace );
    eval 'substr( $string, $start, $num, $replace )';
    return $string;
}

# =========================
$funcRef->{RIGHT} = \&_funcRIGHT;
sub _funcRIGHT
{
    my( $theAttr ) = @_;
    my $i = $rPos + 1;
    my $cStart = $cPos + 2;
    return "R$i:C$cStart..R$i:C32000";
}

# =========================
$funcRef->{RIGHTSTRING} = \&_funcRIGHTSTRING;
sub _funcRIGHTSTRING
{
    my( $theAttr ) = @_;
    my $result = '';
    my( $string, $num ) = split ( /,\s*/, $theAttr, 2 );
    $string = '' unless( defined $string );
    $num = 1 unless( $num );
    my $start = 0;
    $start = length( $string ) - $num;
    eval '$result = substr( $string, $start, $num )';
    return $result;
}

# =========================
$funcRef->{ROUND} = \&_funcROUND;
sub _funcROUND
{
    my( $theAttr ) = @_;

    # ROUND(num, digits)
    my( $num, $digits ) = split( /,\s*/, $theAttr, 2 );
    my $result = _safeEvalPerl( $num );
    unless( $result =~ /^ERROR/ ) {
        $result = _getNumber( $result );
        if( ( $digits ) && ( $digits =~ s/^.*?(\-?[0-9]+).*$/$1/os ) && ( $digits ) ) {
            my $factor = 10**$digits;
            $result *= $factor;
            ( $result >= 0 ) ? ( $result += 0.5 ) : ( $result -= 0.5 );
            $result = int( $result );
            $result /= $factor;
        } else {
            ( $result >= 0 ) ? ( $result += 0.5 ) : ( $result -= 0.5 );
            $result = int( $result );
        }
    }
    return $result;
}

# =========================
$funcRef->{ROW} = \&_funcROW;
sub _funcROW
{
    my( $theAttr ) = @_;
    my $i = $theAttr || 0;
    return $rPos + $i + 1;
}

# =========================
$funcRef->{SEARCH} = \&_funcSEARCH;
sub _funcSEARCH
{
    my( $theAttr ) = @_;
    my( $searchString, $string, $pos ) = split( /,\s*/, $theAttr, 3 );
    my $result = 0;
    $searchString = '' unless( defined $searchString );
    $string = '' unless( defined $string );
    $pos--;
    $pos = 0 if( $pos < 0 );
    pos( $string ) = $pos if( $pos );
    # using zero width lookahead '(?=...)' to keep pos at the beginning of match
    if( eval '$string =~ m/(?=$searchString)/g' && $string ) {
        $result = pos( $string ) + 1;
    }
    return $result;
}

# =========================
$funcRef->{SET} = \&_funcSET;
sub _funcSET
{
    my( $theAttr ) = @_;
    my( $name, $value ) = split( /,\s*/, $theAttr, 2 );
    $name = '' unless( defined $name );
    $name =~ s/[^a-zA-Z0-9\_]//go;
    if( $name ) {
        if( defined( $value ) ) {
            $varStore{ $name } = $value;
        } else {
            delete $varStore{ $name };
        }
    }
    return '';
}

# =========================
$funcRef->{SETHASH} = \&_funcSETHASH;
sub _funcSETHASH
{
    my( $theAttr ) = @_;
    my( $name, $key, $value ) = split( /,\s*/, $theAttr, 3 );
    $name  = '' unless( defined $name );
    $name  =~ s/[^\w\.\/]//go;
    $key   = '' unless( defined $key );
    if( $name ne '' && $key ne '' ) {
        if( defined $value ) {
            $hashStore->{$name}{$key} = $value;
        } else {
            delete $hashStore->{$name}{$key};
        }
    } elsif( $name ne '' ) {
        delete $hashStore->{$name};
    } else {
        $hashStore = {};
    }
    return '';
}

# =========================
$funcRef->{SETIFEMPTY} = \&_funcSETIFEMPTY;
sub _funcSETIFEMPTY
{
    my( $theAttr ) = @_;
    my( $name, $value ) = split( /,\s*/, $theAttr, 2 );
    $name = '' unless( defined $name );
    $value = '' unless( defined $value );
    $name =~ s/[^a-zA-Z0-9\_]//go;
    if( $name && defined( $value ) && ! $varStore{ $name } ) {
        $varStore{ $name } = $value;
    }
    return '';
}

# =========================
$funcRef->{SETLIST} = \&_funcSETLIST;
sub _funcSETLIST
{
    my( $theAttr ) = @_;
    my( $name, $value ) = split( /,\s*/, $theAttr, 2 );
    $name = '' unless( defined $name );
    $name =~ s/[^a-zA-Z0-9\_]//go;
    if( $name ) {
        if( defined( $value ) ) {
            $listStore{ $name } = _listToDelimitedString( _getList( $value ) );
        } else {
            delete $listStore{ $name };
        }
    }
    return '';
}

# =========================
$funcRef->{SETM} = \&_funcSETM;
sub _funcSETM
{
    my( $theAttr ) = @_;
    my( $name, $value ) = split( /,\s*/, $theAttr, 2 );
    $name = '' unless( defined $name );
    $value = '' unless( defined $value );
    $name =~ s/[^a-zA-Z0-9\_]//go;
    if( $name ) {
        my $old = $varStore{ $name };
        $old = '' unless( defined( $old ) );
        $value = _safeEvalPerl( "$old $value" );
        $varStore{ $name } = $value;
    }
    return '';
}

# =========================
$funcRef->{SETMHASH} = \&_funcSETMHASH;
sub _funcSETMHASH
{
    my( $theAttr ) = @_;
    my( $name, $key, $value ) = split( /,\s*/, $theAttr, 3 );
    $name  = '' unless( defined $name );
    $name  =~ s/[^\w\.\/]//go;
    $key   = '' unless( defined $key );
    $value = '' unless( defined $value );
    if( $name ne '' && $key ne '' ) {
        my $old = $hashStore->{$name}{$key};
        $old = '' unless( defined( $old ) );
        $value = _safeEvalPerl( "$old $value" );
        $hashStore->{$name}{$key} = $value;
    }
    return '';
}

# =========================
$funcRef->{SIGN} = \&_funcSIGN;
sub _funcSIGN
{
    my( $theAttr ) = @_;
    my $i = _getNumber( $theAttr );
    my $result =  0;
    $result =  1 if( $i > 0 );
    $result = -1 if( $i < 0 );
    return $result;
}

# =========================
$funcRef->{SPLIT} = \&_funcSPLIT;
sub _funcSPLIT
{
    my( $theAttr ) = @_;
    my( $sep, $str ) = _properSplit( $theAttr, 2 );
    $str = '' unless( defined $str );
    $sep = "  *" if( !defined $sep || $sep eq '' );
    $sep =~ s/\$comma/,/g;
    $sep =~ s/\$sp/ /g;
    $sep =~ s/\$(nop|empty)//g;
    return _listToDelimitedString( split( $sep, $str ) );
}

# =========================
$funcRef->{SQRT} = \&_funcSQRT;
sub _funcSQRT
{
    my( $theAttr ) = @_;
    return sqrt( _getNumber( $theAttr ) );
}

# =========================
$funcRef->{STDEV} = \&_funcSTDEV;
sub _funcSTDEV
{
    my( $theAttr ) = @_;
    my @arr = grep { /./ }
              grep { defined $_ }
              _getListAsFloat( $theAttr );
    my $result = 0;
    my $mean = 0;
    my $size = scalar @arr;
    return $result unless( $size > 1 );
    # calculate mean
    foreach my $i ( @arr ) {
        $mean += $i;
    }
    $mean = $mean / $size;
    foreach my $i ( @arr ) {
        $result += ($i - $mean) ** 2;
    }
    return sqrt( $result / ($size - 1) );
}

# =========================
$funcRef->{STDEVP} = \&_funcSTDEVP;
sub _funcSTDEVP
{
    my( $theAttr ) = @_;
    my @arr = grep { /./ }
              grep { defined $_ }
              _getListAsFloat( $theAttr );
    my $result = 0;
    my $mean = 0;
    my $size = scalar @arr;
    return $result unless( $size > 1 );
    # calculate mean
    foreach my $i ( @arr ) {
        $mean += $i;
    }
    $mean = $mean / $size;
    foreach my $i ( @arr ) {
        $result += ($i - $mean) ** 2;
    }
    return sqrt( $result / $size );
}

# =========================
$funcRef->{SUBSTITUTE} = \&_funcSUBSTITUTE;
sub _funcSUBSTITUTE
{
    my( $theAttr ) = @_;
    my( $string, $from, $to, $inst, $options ) = split( /,\s*/, $theAttr );
    $string = '' unless( defined $string );
    $from   = '' unless( defined $from );
    $to     = '' unless( defined $to );
    my $result = $string;
    $from = quotemeta( $from ) unless( $options && $options =~ /r/i);
    if( $inst ) {
        # replace Nth instance
        my $count = 0;
        if( eval '$string =~ s/($from)/if( ++$count == $inst ) { $to; } else { $1; }/gex;' && $string ) {
            $result = $string;
        }
    } else {
        # global replace
        if( eval '$string =~ s/$from/$to/g' ) {
            $result = $string;
        }
    }
    return $result;
}

# =========================
$funcRef->{SUBSTRING} = \&_funcSUBSTRING;
$funcRef->{MIDSTRING} = \&_funcSUBSTRING;  # undocumented - do not remove
sub _funcSUBSTRING
{
    my( $theAttr ) = @_;
    my $result = '';
    # greedy match for comma separated parameters (in case first parameter has embedded commas)
    if( $theAttr =~ /^(.*)\,\s*(.+)\,\s*(.+)$/os ) {
        my( $string, $start, $num ) = ( $1, _getNumber( $2 ), _getNumber( $3 ) );
        if( $start && abs( $start ) <= length( $string ) && $num ) {
            $start-- unless ($start < 1);
            eval '$result = substr( $string, $start, $num )';
        }
    }
    return $result;
}

# =========================
$funcRef->{SUM} = \&_funcSUM;
sub _funcSUM
{
    my( $theAttr ) = @_;
    my $result = 0;
    my @arr = _getListAsFloat( $theAttr );
    foreach my $i ( @arr ) {
        $result += $i  if defined $i;
    }
    return $result;
}

# =========================
$funcRef->{SUMDAYS} = \&_funcSUMDAYS;
$funcRef->{DURATION} = \&_funcSUMDAYS;  # undocumented - do not remove
sub _funcSUMDAYS
{
    my( $theAttr ) = @_;
    # contributed by SvenDowideit - 07 Mar 2003; modified by PTh
    my $result = 0;
    my @arr = _getListAsDays( $theAttr );
    foreach my $i ( @arr ) {
        $result += $i  if defined $i;
    }
    return $result;
}

# =========================
$funcRef->{SUMPRODUCT} = \&_funcSUMPRODUCT;
sub _funcSUMPRODUCT
{
    my( $theAttr ) = @_;
    my $result = 0;
    my @arr;
    my @lol = split( /,\s*/, $theAttr );
    my $size = 32000;
    my $i;
    for $i (0 .. $#lol ) {
        @arr = _getListAsFloat( $lol[$i] );
        $lol[$i] = [ @arr ];                # store reference to array
        $size = @arr if( @arr < $size );    # remember smallest array
    }
    if( ( $size > 0 ) && ( $size < 32000 ) ) {
        my $y; my $prod; my $val;
        $size--;
        for $y (0 .. $size ) {
            $prod = 1;
            for $i (0 .. $#lol ) {
                $val = $lol[$i][$y];
                if( defined $val ) {
                    $prod *= $val;
                } else {
                    $prod = 0;   # don't count empty cells
                }
            }
            $result += $prod;
        }
    }
    return $result;
}

# =========================
$funcRef->{T} = \&_funcT;
sub _funcT
{
    my( $theAttr ) = @_;
    my $result = '';
    my @arr = _getTableRange( "$theAttr..$theAttr" );
    if( @arr ) {
        $result = $arr[0];
    }
    return $result;
}

# =========================
$funcRef->{TIME} = \&_funcTIME;
sub _funcTIME
{
    my( $result ) = @_;
    $result =~ s/^\s+//o;
    $result =~ s/\s+$//o;
    if( $result ) {
        $result = _date2serial( $result );
    } else {
        $result = time();
    }
    return $result;
}

# =========================
$funcRef->{TIMEADD} = \&_funcTIMEADD;
sub _funcTIMEADD
{
    my( $theAttr ) = @_;
    my( $time, $value, $scale ) = split( /,\s*/, $theAttr, 3 );
    $time = 0 unless( $time );
    $value = 0 unless( $value );
    $scale = "" unless( $scale );
    $time =~ s/.*?([0-9]+).*/$1/o || 0;
    $value =~ s/.*?(\-?[0-9\.]+).*/$1/o || 0;
    $value *= 60            if( $scale =~ /^min/i );
    $value *= 3600          if( $scale =~ /^hou/i );
    $value *= 3600*24       if( $scale =~ /^day/i );
    $value *= 3600*24*7     if( $scale =~ /^week/i );
    $value *= 3600*24*30.42 if( $scale =~ /^mon/i );  # FIXME: exact calc
    $value *= 3600*24*365   if( $scale =~ /^year/i ); # FIXME: exact calc
    return int( $time + $value );
}

# =========================
$funcRef->{TIMEDIFF} = \&_funcTIMEDIFF;
sub _funcTIMEDIFF
{
    my( $theAttr ) = @_;
    my( $time1, $time2, $scale ) = split( /,\s*/, $theAttr, 3 );
    $scale ||= '';
    $time1 = 0 unless( $time1 );
    $time2 = 0 unless( $time2 );
    $time1 =~ s/.*?([0-9]+).*/$1/o || 0;
    $time2 =~ s/.*?([0-9]+).*/$1/o || 0;
    my $result = $time2 - $time1;
    $result /= 60            if( $scale =~ /^min/i );
    $result /= 3600          if( $scale =~ /^hou/i );
    $result /= 3600*24       if( $scale =~ /^day/i );
    $result /= 3600*24*7     if( $scale =~ /^week/i );
    $result /= 3600*24*30.42 if( $scale =~ /^mon/i );  # FIXME: exact calc
    $result /= 3600*24*365   if( $scale =~ /^year/i ); # FIXME: exact calc
    return $result;
}

# =========================
$funcRef->{TODAY} = \&_funcTODAY;
sub _funcTODAY
{
    return _date2serial( _serial2date( time(), '$year/$month/$day GMT', 1 ) );
}

# =========================
$funcRef->{TRANSLATE} = \&_funcTRANSLATE;
sub _funcTRANSLATE
{
    my( $theAttr ) = @_;
    my $result = $theAttr;
    # greedy match for comma separated parameters (in case first parameter has embedded commas)
    if( $theAttr =~ /^(.*)\,\s*(.+)\,\s*(.+)$/os ) {
        my $string = $1;
        my $from = $2;
        my $to   = $3;
        $from =~ s/\$comma/,/g;      $to =~ s/\$comma/,/g;
        $from =~ s/\$sp/ /g;         $to =~ s/\$sp/ /g;
        $from =~ s/\$n/\n/g;         $to =~ s/\$n/\n/g; # the $from is silly, CALC can't be multi-line, yet
        $from =~ s/\$quot/"/g;       $to =~ s/\$quot/"/g;
        $from =~ s/\$aquot/'/g;      $to =~ s/\$aquot/'/g;
        $from = quotemeta( $from );  $to = quotemeta( $to );
        $from =~ s/([a-zA-Z0-9])\\\-([a-zA-Z0-9])/$1\-$2/g; # fix quotemeta (allow only ranges)
        $to   =~ s/([a-zA-Z0-9])\\\-([a-zA-Z0-9])/$1\-$2/g;
        $result = $string;
        if( $string && eval "\$string =~ tr/$from/$to/" ) {
            $result = $string;
        }
    }
    return $result;
}

# =========================
$funcRef->{TRIM} = \&_funcTRIM;
sub _funcTRIM
{
    my( $theAttr ) = @_;
    my $result = $theAttr || '';
    $result =~ s/^\s*//o;
    $result =~ s/\s*$//o;
    $result =~ s/\s+/ /go;
    return $result;
}

# =========================
$funcRef->{UPPER} = \&_funcUPPER;
sub _funcUPPER
{
    my( $theAttr ) = @_;
    return uc( $theAttr );
}

# =========================
$funcRef->{VALUE} = \&_funcVALUE;
sub _funcVALUE
{
    my( $theAttr ) = @_;
    return _getNumber( $theAttr );
}

# =========================
$funcRef->{VAR} = \&_funcVAR;
sub _funcVAR
{
    my( $theAttr ) = @_;
    my @arr = grep { /./ }
              grep { defined $_ }
              _getListAsFloat( $theAttr );
    my $result = 0;
    my $mean = 0;
    my $size = scalar @arr;
    return $result unless( $size > 1 );
    # calculate mean
    foreach my $i ( @arr ) {
        $mean += $i;
    }
    $mean = $mean / $size;
    foreach my $i ( @arr ) {
        $result += ( abs($i - $mean) ) ** 2;
    }
    return $result / ($size - 1);
}

# =========================
$funcRef->{VARP} = \&_funcVARP;
sub _funcVARP
{
    my( $theAttr ) = @_;
    my @arr = grep { /./ }
              grep { defined $_ }
              _getListAsFloat( $theAttr );
    my $result = 0; 
    my $mean = 0;
    my $size = scalar @arr;
    return $result unless( $size > 1 );
    # calculate mean
    foreach my $i ( @arr ) {
        $mean += $i;
    }
    $mean = $mean / $size;
    foreach my $i ( @arr ) {
        $result += ( abs($i - $mean) ) ** 2;
    }
    return $result / $size;
}

# =========================
$funcRef->{WHILE} = \&_funcWHILE;
sub _funcWHILE
{
    my( $theAttr ) = @_;

    # WHILE(condition, do something)
    my( $condition, $str ) = _properSplit( $theAttr, 2 );
    $condition = '' unless( defined $condition );
    $str = '' unless( defined $str );
    my $i = 0;
    my $result = '';
    while( 1 ) {
        if( $i++ >= 32767 ) {
            $result .= 'ERROR: Infinite loop (32767 cycles)';
            last; # prevent infinite loop
        }
        # with delay, handle functions in condition recursively and clean up unbalanced parenthesis
        my $cond = $condition;
        $cond =~ s/\$counter/$i/go;
        &$recurseFunc( $cond );
        $cond =~ s/^\s*(.*?)\s*$/$1/os;
        my $res = _safeEvalPerl( $cond );
        if( $res =~ /^ERROR/ ) {
            $result .= $res;
            last; # exit loop and return error
        }
        last unless( $res ); # proper loop exit
        $res = $str;
        $res = "" unless( defined( $res ) );
        # with delay, handle functions in result recursively and clean up unbalanced parenthesis
        $res =~ s/\$counter/$i/go;
        &$recurseFunc( $res );
        $result .= $res;
    }

    return $result;
}

# =========================
$funcRef->{WORKINGDAYS} = \&_funcWORKINGDAYS;
sub _funcWORKINGDAYS
{
    my( $theAttr ) = @_;
    my( $num1, $num2 ) = split( /,\s*/, $theAttr, 2 );
    return _workingDays( _getNumber( $num1 ), _getNumber( $num2 ) );
}

# =========================
$funcRef->{XOR} = \&_funcXOR;
sub _funcXOR
{
    my( $theAttr ) = @_;
    my @arr = _getListAsInteger( $theAttr );
    my $result = shift( @arr );
    if( scalar( @arr ) > 0 ) {
        foreach my $i ( @arr ) {
            $result = ( $result xor $i );
        }
    } else {
        $result = 0;
    }
    $result = $result ? 1 : 0;
    return $result;
}

# =========================
sub _listToDelimitedString
{
    my @arr = map { s/^\s*//o; s/\s*$//o; $_ } @_;
    my $text = join( ", ", @arr );
    return $text;
}

# =========================
sub _properSplit
{
    my( $theAttr, $theLevel ) = @_;

    # escape commas inside functions
    $theAttr =~ s/(\$[A-Z]+[A-Z0-9]*$escToken([0-9]+)\(.*?$escToken\2\))/_escapeCommas($1)/geos;
    # split at commas and restore commas inside functions
    my @arr = map{ s/<$escToken>/\,/go; $_ } split( /,\s*/, $theAttr, $theLevel );
    return @arr;
}

# =========================
sub _escapeCommas
{
    my( $theText ) = @_;
    $theText =~ s/\,/<$escToken>/go;
    return $theText;
}

# =========================
sub _getNumber
{
    my( $theText ) = @_;
    return 0 unless( $theText );
    $theText =~ s/([0-9])\,(?=[0-9]{3})/$1/go;                    # "1,234,567" ==> "1234567"
    if( $theText =~ s/^.*?(\-?[0-9\.]+e[\-\+]?[0-9]+).*$/$1/is ) { # "1.5e-3"    ==> "0.0015"
        $theText = sprintf "%.20f", $theText;
        $theText =~ s/0+$//;
    }
    unless( $theText =~ s/^.*?(\-?[0-9\.]+).*$/$1/os ) { # "xy-1.23zz" ==> "-1.23"
        $theText = 0;
    }
    $theText =~ s/^(\-?)0+([0-9])/$1$2/o;               # "-0009.12"  ==> "-9.12"
    $theText =~ s/^(\-?)\./${1}0\./o;                   # "-.25"      ==> "-0.25"
    $theText =~ s/^\-0$/0/o;                            # "-0"        ==> "0"
    $theText =~ s/\.$//o;                               # "123."      ==> "123"
    return $theText;
}

# =========================
sub _safeEvalPerl
{
    my( $theText ) = @_;
    $theText = '' unless( defined $theText );
    # Allow only simple math with operators - + * / % ( )
    $theText =~ s/\%\s*[^\-\+\*\/0-9\.\(\)]+//gos; # defuse %hash but keep modulus
    # keep only numbers and operators (shh... don't tell anyone, we support comparison operators)
    $theText =~ s/[^\!\<\=\>\-\+\*\/\%0-9e\.\(\)]*//go;
    $theText =~ s/(^|[^\.])\b0+(?=[0-9])/$1/go;  # remove leading 0s to defuse interpretation of numbers as octals
    $theText =~ s/(^|[^0-9])e/$1/go;  # remove "e"-s unless in expression such as "123e-4"
    $theText =~ /(.*)/s;
    $theText = $1;  # untainted variable
    return "" unless( $theText );
    local $SIG{__DIE__} = sub { TWiki::Func::writeDebug($_[0]); warn $_[0] };
    my $result = eval $theText;
    if( $@ ) {
        $result = $@;
        $result =~ s/[\n\r]//go;
        $result =~ s/\[[^\]]+.*view.*?\:\s?//o;                   # Cut "[Mon Mar 15 23:31:39 2004] view: "
        $result =~ s/\s?at \(eval.*?\)\sline\s?[0-9]*\.?\s?//go;  # Cut "at (eval 51) line 2."
        $result =~ s/at end of line\.?//go;                       # Cut "at end of line"
        $result =~ s/,?\s*$//o;
        $result = "ERROR: $result";

    } else {
        $result = 0 unless( $result );  # logical false is "0"
    }
    return $result;
}

# =========================
sub _getListAsInteger
{
    my( $theAttr ) = @_;

    my $val = 0;
    my @list = _getList( $theAttr );
    (my $baz = "foo") =~ s/foo//;  # reset search vars. defensive coding
    for my $i (0 .. $#list ) {
        $val = $list[$i];
        # search first integer pattern, skip over HTML tags
        if( $val =~ /^\s*(?:<[^>]*>)*([\-\+]*[0-9]+).*/os ) {
            $list[$i] = $1;  # untainted variable, possibly undef
        } else {
            $list[$i] = undef;
        }
    }
    return @list;
}

# =========================
sub _getListAsFloat
{
    my( $theAttr ) = @_;

    my $val = 0;
    my @list = _getList( $theAttr );
    (my $baz = "foo") =~ s/foo//;  # reset search vars. defensive coding
    for my $i (0 .. $#list ) {
        $val = $list[$i];
        # search first float pattern, skip over HTML tags
        if( $val =~ /^\s*(?:<[^>]*>)*\$?([\-\+]*[0-9\.]+).*/os ) {
            $list[$i] = $1;  # untainted variable, possibly undef
        } else {
            $list[$i] = undef;
        }
    }
    return @list;
}

# =========================
sub _getListAsDays
{
    my( $theAttr ) = @_;

    # contributed by by SvenDowideit - 07 Mar 2003; modified by PTh
    my $val = 0;
    my @arr = _getList( $theAttr );
    (my $baz = "foo") =~ s/foo//;  # reset search vars. defensive coding
    for my $i (0 .. $#arr ) {
        $val = $arr[$i];
        # search first float pattern
        if( $val =~ /^\s*([\-\+]*[0-9\.]+)\s*d/oi ) {
            $arr[$i] = $1;      # untainted variable, possibly undef
        } elsif( $val =~ /^\s*([\-\+]*[0-9\.]+)\s*w/oi ) {
            $arr[$i] = 5 * $1;  # untainted variable, possibly undef
        } elsif( $val =~ /^\s*([\-\+]*[0-9\.]+)\s*h/oi ) {
            $arr[$i] = $1 / 8;  # untainted variable, possibly undef
        } elsif( $val =~ /^\s*([\-\+]*[0-9\.]+)/o ) {
            $arr[$i] = $1;      # untainted variable, possibly undef
        } else {
            $arr[$i] = undef;
        }
    }
    return @arr;
}

# =========================
sub _getList
{
    my( $theAttr ) = @_;

    my @list = ();
    foreach( split( /,\s*/, $theAttr ) ) {
        if( m/\s*R([0-9]+)\:C([0-9]+)\s*\.\.+\s*R([0-9]+)\:C([0-9]+)/ ) {
            # table range
            push( @list, _getTableRange( $_ ) );
        } else {
            # list item
            push( @list, $_ ); 
        }
    }
    return @list;
}

# =========================
sub _getTableRange
{
    my( $theAttr ) = @_;

    my @arr = ();
    if( $rPos < 0 ) {
        return @arr;
    }

    TWiki::Func::writeDebug( "- SpreadSheetPlugin::Calc::_getTableRange( $theAttr )" ) if $debug;
    unless( $theAttr =~ /\s*R([0-9]+)\:C([0-9]+)\s*\.\.+\s*R([0-9]+)\:C([0-9]+)/ ) {
        return @arr;
    }
    my $r1 = $1 - 1;
    my $c1 = $2 - 1;
    my $r2 = $3 - 1;
    my $c2 = $4 - 1;
    my $r = 0;
    my $c = 0;
    if( $c1 < 0     ) { $c1 = 0; }
    if( $c2 < 0     ) { $c2 = 0; }
    if( $c2 < $c1   ) { $c = $c1; $c1 = $c2; $c2 = $c; }
    if( $r1 > $rPos ) { $r1 = $rPos; }
    if( $r1 < 0     ) { $r1 = 0; }
    if( $r2 > $rPos ) { $r2 = $rPos; }
    if( $r2 < 0     ) { $r2 = 0; }
    if( $r2 < $r1   ) { $r = $r1; $r1 = $r2; $r2 = $r; }

    my $pRow = ();
    for $r ( $r1 .. $r2 ) {
        $pRow = $tableMatrix[$r];
        for $c ( $c1 .. $c2 ) {
            if( $c < @$pRow ) {
                push( @arr, $$pRow[$c] );
            }
        }
    }
    TWiki::Func::writeDebug( "- SpreadSheetPlugin::Calc::_getTableRange() returns @arr" ) if $debug;
    return @arr;
}

# =========================
sub _date2serial
{
    my ( $theText ) = @_;

    my $sec = 0; my $min = 0; my $hour = 0; my $day = 1; my $mon = 0; my $year = 0;

    # Handle DOY (Day of Year)
    if( $theText =~ m|([Dd][Oo][Yy])\s*([0-9]{4})[\.]([0-9]{1,3})[\.]([0-9]{1,2})[\.]([0-9]{1,2})[\.]([0-9]{1,2})| ) {
        # "DOY2003.122.23.15.59", "DOY2003.2.9.3.5.9" i.e. year.ddd.hh.mm.ss
        $year = $2 - 1900; $day = $3; $hour = $4; $min = $5; $sec = $6;	 # Note: $day is in fact doy
    } elsif( $theText =~ m|([Dd][Oo][Yy])\s*([0-9]{4})[\.]([0-9]{1,3})[\.]([0-9]{1,2})[\.]([0-9]{1,2})| ) {
        # "DOY2003.122.23.15", "DOY2003.2.9.3" i.e. year.ddd.hh.mm
        $year = $2 - 1900; $day = $3; $hour = $4; $min = $5;
    } elsif( $theText =~ m|([Dd][Oo][Yy])\s*([0-9]{4})[\.]([0-9]{1,3})[\.]([0-9]{1,2})| ) {
        # "DOY2003.122.23", "DOY2003.2.9" i.e. year.ddd.hh
        $year = $2 - 1900; $day = $3; $hour = $4;
    } elsif( $theText =~ m|([Dd][Oo][Yy])\s*([0-9]{4})[\.]([0-9]{1,3})| ) {
        # "DOY2003.122", "DOY2003.2" i.e. year.ddd
        $year = $2 - 1900; $day = $3;
    } elsif ($theText =~ m|([0-9]{1,2})[-\s/]+([A-Z][a-z][a-z])[-\s/]+([0-9]{4})[-\s/]+([0-9]{1,2}):([0-9]{1,2}):([0-9]{1,2})| ) {
        # "31 Dec 2003 - 23:59:59", "31-Dec-2003 - 23:59:59", "31 Dec 2003 - 23:59:59 - any suffix"
        $day = $1; $mon = $mon2num{$2} || 0; $year = $3 - 1900; $hour = $4; $min = $5; $sec = $6;
    } elsif ($theText =~ m|([0-9]{1,2})[-\s/]+([A-Z][a-z][a-z])[-\s/]+([0-9]{4})[-\s/]+([0-9]{1,2}):([0-9]{1,2})| ) {
        # "31 Dec 2003 - 23:59", "31-Dec-2003 - 23:59", "31 Dec 2003 - 23:59 - any suffix"
        $day = $1; $mon = $mon2num{$2} || 0; $year = $3 - 1900; $hour = $4; $min = $5;
    } elsif( $theText =~ m|([0-9]{1,2})[-\s/]+([A-Z][a-z][a-z])[-\s/]+([0-9]{2,4})| ) {
        # "31 Dec 2003", "31 Dec 03", "31-Dec-2003", "31/Dec/2003"
        $day = $1; $mon = $mon2num{$2} || 0; $year = $3;
        $year += 100 if( $year < 80 );      # "05"   --> "105" (leave "99" as is)
        $year -= 1900 if( $year >= 1900 );  # "2005" --> "105"
    } elsif( $theText =~ m|([0-9]{4})[-/\.]([0-9]{1,2})[-/\.]([0-9]{1,2})[-/\.\,\s]+([0-9]{1,2})[-\:/\.]([0-9]{1,2})[-\:/\.]([0-9]{1,2})| ) {
        # "2003/12/31 23:59:59", "2003-12-31-23-59-59", "2003.12.31.23.59.59"
        $year = $1 - 1900; $mon = $2 - 1; $day = $3; $hour = $4; $min = $5; $sec = $6;
    } elsif( $theText =~ m|([0-9]{4})[-/\.]([0-9]{1,2})[-/\.]([0-9]{1,2})[-/\.\,\s]+([0-9]{1,2})[-\:/\.]([0-9]{1,2})| ) {
        # "2003/12/31 23:59", "2003-12-31-23-59", "2003.12.31.23.59"
        $year = $1 - 1900; $mon = $2 - 1; $day = $3; $hour = $4; $min = $5;
    } elsif( $theText =~ m|([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})| ) {
        # "2003/12/31", "2003-12-31"
        $year = $1 - 1900; $mon = $2 - 1; $day = $3;
    } elsif( $theText =~ m|([0-9]{1,2})[-/]([0-9]{1,2})[-/]([0-9]{2,4})| ) {
        # "12/31/2003", "12/31/03", "12-31-2003"
        # (shh, don't tell anyone that we support ambiguous American dates, my boss asked me to)
        $year = $3; $mon = $1 - 1; $day = $2;
        $year += 100 if( $year < 80 );      # "05"   --> "105" (leave "99" as is)
        $year -= 1900 if( $year >= 1900 );  # "2005" --> "105"
    } else {
        # unsupported format
        return 0;
    }
    if( ( $sec > 60 ) || ( $min > 59 ) || ( $hour > 23 ) || ( $day < 1 ) || ( $day > 365 ) || ( $mon > 11 )) {
        # unsupported, out of range
        return 0;
    }

    # To handle DOY, use timegm_nocheck or timelocal_nocheck that won't check input data range.
    # This is necessary because with DOY, $day must be able to be greater than 31 and timegm
    # and timelocal won't allow it. Keep using timegm or timelocal for non-DOY stuff.
    if( $theText =~ /gmt/i ) {
        if( $theText =~ /DOY/i ) {
            return timegm_nocheck( $sec, $min, $hour, $day, $mon, $year);
        } else {
            return timegm( $sec, $min, $hour, $day, $mon, $year );
        }
    } else {
        if( $theText =~ /DOY/i ) {
            return timelocal_nocheck( $sec, $min, $hour, $day, $mon, $year);
        } else {
            return timelocal( $sec, $min, $hour, $day, $mon, $year );
        }
    }
}

# =========================
sub _serial2date
{
    my ( $theTime, $theStr, $isGmt ) = @_;

    my( $sec, $min, $hour, $day, $mon, $year, $wday, $yday ) = ( $isGmt ? gmtime( $theTime ) : localtime( $theTime ) );

    $theStr =~ s/\$isoweek\(([^\)]*)\)/_isoWeek( $1, $day, $mon, $year, $wday, $theTime )/geoi;
    $theStr =~ s/\$isoweek/_isoWeek( '$week', $day, $mon, $year, $wday, $theTime )/geoi;
    $theStr =~ s/\$sec[o]?[n]?[d]?[s]?/sprintf("%.2u",$sec)/geoi;
    $theStr =~ s/\$min[u]?[t]?[e]?[s]?/sprintf("%.2u",$min)/geoi;
    $theStr =~ s/\$hou[r]?[s]?/sprintf("%.2u",$hour)/geoi;
    $theStr =~ s/\$day/sprintf("%.2u",$day)/geoi;
    $theStr =~ s/\$mon(?!t)/$monArr[$mon]/goi;
    $theStr =~ s/\$mo[n]?[t]?[h]?/sprintf("%.2u",$mon+1)/geoi;
    $theStr =~ s/\$yearday/$yday+1/geoi;
    $theStr =~ s/\$yea[r]?/sprintf("%.4u",$year+1900)/geoi;
    $theStr =~ s/\$ye/sprintf("%.2u",$year%100)/geoi;
    $theStr =~ s/\$wday/substr($wdayArr[$wday],0,3)/geoi;
    $theStr =~ s/\$wd/$wday+1/geoi;
    $theStr =~ s/\$weekday/$wdayArr[$wday]/goi;

    return $theStr;
}

# =========================
sub _isoWeek
{
    my ( $format, $day, $mon, $year, $wday, $serial ) = @_;

    # Contributed by PeterPayne - 22 Oct 2007
    # Enhanced by PeterThoeny 2010-08-27
    # Calculate the ISO8601 week number from the serial.

    my $isoyear = $year + 1900;
    my $yearserial = _year2isoweek1serial( $year + 1900, 1 );
    if ( $mon >= 11 ) { # check if date is in next year's first week
        my $yearnextserial = _year2isoweek1serial( $year + 1900 + 1, 1 );
        if ( $serial >= $yearnextserial ) {
            $yearserial = $yearnextserial;
            $isoyear += 1;
        }
    } elsif ( $serial < $yearserial ) {
        $yearserial = _year2isoweek1serial( $year + 1900 - 1, 1 );
        $isoyear -= 1;
    }

    # calculate GMT of just past midnight today
    my $today_gmt = timegm( 0, 0, 0, $day, $mon, $year );
    my $isoweek = int( ( $today_gmt - $yearserial ) / ( 7 * 24 * 3600 ) ) + 1 ;
    my $isowk = sprintf("%.2u", $isoweek );
    my $isoday = $wday;
    $isoday = 7 unless( $isoday );

    $format =~ s/\$iso/$isoyear-W$isoweek/go;
    $format =~ s/\$year/$isoyear/go;
    $format =~ s/\$week/$isoweek/go;
    $format =~ s/\$wk/$isowk/go;
    $format =~ s/\$day/$isoday/go;

    return $format;
}

# =========================
sub _year2isoweek1serial
{
    my ( $year, $isGmt ) = @_;

    # Contributed by PeterPayne - 22 Oct 2007
    # Calculate the serial of the beginning of week 1 for specified year.
    # Year is 4 digit year (e.g. "2000")

    $year -= 1900;

    # get Jan 4
    my @param = ( 0, 0, 0, 4, 0, $year );
    my $jan4epoch = ( $isGmt ? timegm( @param ) : timelocal( @param ) );

    # what day does Jan 4 fall on?
    my $jan4day = ( $isGmt ? (gmtime($jan4epoch))[6] : (localtime($jan4epoch))[6] );

    $jan4day += 7 if ( $jan4day < 1 );

    return( $jan4epoch - ( 24 * 3600 * ( $jan4day - 1 ) ) );
}

# =========================
sub _properSpace
{
    my ( $theStr ) = @_;

    # FIXME: I18N

    unless( $dontSpaceRE ) {
        $dontSpaceRE = &TWiki::Func::getPreferencesValue( "DONTSPACE" ) ||
                       &TWiki::Func::getPreferencesValue( "SPREADSHEETPLUGIN_DONTSPACE" ) ||
                       "UnlikelyGibberishWikiWord";
        $dontSpaceRE =~ s/[^a-zA-Z0-9\,\s]//go;
        $dontSpaceRE = "(" . join( "|", split( /[\,\s]+/, $dontSpaceRE ) ) . ")";
        # Example: "(RedHat|McIntosh)"
    }
    $theStr =~ s/$dontSpaceRE/_spaceWikiWord( $1, "<DONT_SPACE>" )/geo;  # e.g. "Mc<DONT_SPACE>Intosh"
    $theStr =~ s/(^|[\s\(]|\]\[)([a-zA-Z0-9]+)/$1 . _spaceWikiWord( $2, " " )/geo;
    $theStr =~ s/<DONT_SPACE>//go;  # remove "<DONT_SPACE>" marker

    return $theStr;
}

# =========================
sub _spaceWikiWord
{
    my ( $theStr, $theSpacer ) = @_;

    $theStr =~ s/([a-z])([A-Z0-9])/$1$theSpacer$2/go;
    $theStr =~ s/([0-9])([a-zA-Z])/$1$theSpacer$2/go;
    $theStr =~ s/([A-Z])([0-9])/$1$theSpacer$2/go;

    return $theStr;
}

# =========================
sub _workingDays
{
    my ( $start, $end ) = @_;

    # Rewritten by PeterThoeny - 2009-05-03 (previous implementation was buggy)
    # Calculate working days between two times. Times are standard system times (secs since 1970).
    # Working days are Monday through Friday (sorry, Israel!)
    # A day has 60 * 60 * 24 sec
    # Adding 3601 sec to account for daylight saving change in March in Northern Hemisphere
    my $days = int( ( abs( $end - $start ) + 3601 ) / 86400 );
    my $weeks = int( $days / 7 );
    my $fullWeekWorkingDays = 5 * $weeks;
    my $extra = $days % 7;
    if( $extra > 0 ) {
      $start = $end if( $start > $end );
      my @tm = gmtime( $start );
      my $wday = $tm[6]; # 0 is Sun, 6 is Sat
      if( $wday == 0 ) {
        $extra--;
      } else {
        my $sum = $wday + $extra;
        $extra-- if( $sum > 6 );
        $extra-- if( $sum > 7 );
      }
    }
    return $fullWeekWorkingDays + $extra;
}

# =========================
1;
