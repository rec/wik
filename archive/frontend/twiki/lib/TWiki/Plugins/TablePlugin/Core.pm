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

use strict;

package TWiki::Plugins::TablePlugin::Core;

use Time::Local;
use TWiki::Func;

my $insideTABLE;
my $tableCount;
my @curTable;
my $sortCol;
my $requestedTable;
my $up;
my $sortTablesInText;
my $sortAttachments;
my $sortColFromUrl;
my $tableWidth;
my @columnWidths;
my $tableBorder;
my $tableFrame;
my $tableRules;
my $cellPadding;
my $cellSpacing;
my $cellBorder;
my @headerAlign;
my @dataAlign;
my $vAlign;
my $headerVAlign;
my $dataVAlign;
my $headerBg;
my $headerBgSorted;
my $headerColor;
my $sortAllTables;
my $twoCol;
my @dataBg;
my @dataBgSorted;
my @dataColor;
my $headerRows;
my $footerRows;
my $url;
my %mon2num;
my $initSort;
my $initDirection;
my $currentSortDirection;
my @rowspan;
my $pluginAttrs;
my $prefsAttrs;
my $tableId;
my $tableSummary;
my $tableCaption;
my %cssAttrs;
my $translationToken;
my $currTablePre;
my $upchar;
my $downchar;
my $diamondchar;
my @isoMonth;
my %sortDirection;
my %columnType;
my $maxSortCols;
my $iconUrl;
my $unsortEnabled;
my $didWriteDefaultStyle;
my %defaultCssAttrs;
my $escNewline = "\x001";
my $escPipe    = "\x002";
my $escNesting = "\x003";
my $escStart   = "\x004";
my $escEnd     = "\x005";

BEGIN {
    $translationToken = "\0";
    $currTablePre     = '';
    $upchar           = '';
    $downchar         = '';
    $diamondchar      = '';
    @isoMonth         = (
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    );
    {
        my $count = 0;
        %mon2num = map { $_ => $count++ } @isoMonth;
    }
    %sortDirection = ( 'ASCENDING', 0, 'DESCENDING', 1, 'NONE', 2 );
    %columnType = (
        'TEXT',   'text',   'DATE',      'date',
        'NUMBER', 'number', 'UNDEFINED', 'undefined'
    );

    # the maximum number of columns we will handle
    $maxSortCols = 10000;
    $iconUrl =
        TWiki::Func::getPubUrlPath() . '/'
      . TWiki::Func::getTwikiWebname()
      . '/TWikiDocGraphics/';
    $unsortEnabled        = 1;    # if true, table columns can be unsorted
    %defaultCssAttrs = ();
}

sub _setDefaults {
    $sortAllTables  = $sortTablesInText;
    $tableBorder    = 1;
    $tableFrame     = '';
    $tableRules     = '';
    $cellSpacing    = '';
    $cellPadding    = '';
    $cellBorder     = '';
    $tableWidth     = '';
    $headerRows     = 0;
    $footerRows     = 0;
    $vAlign         = '';
    $headerVAlign   = '';
    $dataVAlign     = '';
    $headerBg       = '#6b7f93';
    $headerBgSorted = '';
    $headerColor    = '#ffffff';
    $tableId        = '';
    $tableSummary   = '';
    $tableCaption   = '';
    @columnWidths   = ();
    @headerAlign    = ();
    @dataAlign      = ();
    @dataBg         = ( '#ecf2f8', '#ffffff' );
    @dataBgSorted   = ();
    @dataColor      = ();

    undef $initSort;

    # Preferences setting
    # It seems overkill to redo this every time!
    my %pluginParams   = TWiki::Func::extractParameters($pluginAttrs);
    my %prefsParams    = TWiki::Func::extractParameters($prefsAttrs);
    my %combinedParams = ( %pluginParams, %prefsParams );
    _parseParameters( 1, 'default', %combinedParams );
}

# Table attributes defined as a Plugin setting, a preferences setting
# e.g. in WebPreferences or as a %TABLE{...}% setting
sub _parseParameters {
    my ( $useCss, $writeDefaults, %params ) = @_;

    return '' if !keys %params;

    %cssAttrs = ();

    my $tmp;

    $tmp = $params{id};
    if ( defined $tmp && $tmp ne '' && $tmp ne $tableId ) {
        $tableId = $tmp;
    }
    else {
        $tableId = 'table' . ( $tableCount + 1 );
    }
    $cssAttrs{tableId} = $tableId;

    # Defines which column to initially sort : ShawnBradford 20020221
    $tmp = $params{initsort};
    $initSort = $tmp if ($tmp);

    # Defines which direction to sort the column set by initsort :
    # ShawnBradford 20020221
    $tmp           = $params{initdirection};
    $initDirection = $sortDirection{'ASCENDING'}
      if ( defined $tmp && $tmp =~ /^down$/i );
    $initDirection = $sortDirection{'DESCENDING'}
      if ( defined $tmp && $tmp =~ /^up$/i );

    $tmp           = $params{sort};
    $tmp           = '0' if ( defined $tmp && $tmp =~ /^off$/oi );
    $sortAllTables = $tmp if ( defined $tmp && $tmp ne '' );
    
    # If EditTablePlugin is installed and we are editing a table, the CGI
    # parameter 'sort' is defined as "off" to disable all header sorting ((Item5135)
    my $cgi = TWiki::Func::getCgiQuery();
    $tmp = $cgi->param('sort');
    if ( defined $tmp && $tmp =~ /^off$/oi ) {
        undef $sortAllTables;
    }

    # If EditTablePlugin is installed and we are editing a table, the 
    # 'disableallsort' TABLE parameter is added to disable initsort and header
    # sorting in the table that is being edited. (Item5135)
    $tmp = $params{disableallsort};
    if ( defined $tmp && $tmp =~ /^on$/oi ) {
        undef $sortAllTables;
        undef $initSort;        
    }

    $tmp = $params{tableborder};
    if ( defined $tmp && $tmp ne '' ) {
        $tableBorder = $tmp if $tmp ne $tableBorder;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'tableBorder'}
                || $tmp ne $defaultCssAttrs{'tableBorder'} )
          )
        {
            $cssAttrs{tableBorder} = $tableBorder;
            $defaultCssAttrs{tableBorder} = $tableBorder if $writeDefaults;
        }
    }

    $tmp = $params{tableframe};
    if ( defined $tmp && $tmp ne '' && $tmp ne $tableFrame ) {
        $tableFrame = $tmp;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'tableFrame'}
                || $tmp ne $defaultCssAttrs{'tableFrame'} )
          )
        {
            $cssAttrs{tableFrame} = $tableFrame;
            $defaultCssAttrs{tableFrame} = $tableFrame if $writeDefaults;
        }
    }

    $tmp = $params{tablerules};
    if ( defined $tmp && $tmp ne '' && $tmp ne $tableRules ) {
        $tableRules = $tmp;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'tableRules'}
                || $tmp ne $defaultCssAttrs{'tableRules'} )
          )
        {
            $cssAttrs{tableRules} = $tableRules;
            $defaultCssAttrs{tableRules} = $tableRules if $writeDefaults;
        }
    }

    $tmp = $params{cellpadding};
    if ( defined $tmp && $tmp ne '' && $tmp ne $cellPadding ) {
        $cellPadding = $tmp;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'cellPadding'}
                || $tmp ne $defaultCssAttrs{'cellPadding'} )
          )
        {
            $cssAttrs{cellPadding} = $cellPadding;
            $defaultCssAttrs{cellPadding} = $cellPadding if $writeDefaults;
        }
    }

    $tmp = $params{cellspacing};

    # not used in CSS
    if ( defined $tmp && $tmp ne '' && $tmp ne $cellSpacing ) {
        $cellSpacing = $tmp;
    }

    $tmp = $params{cellborder};
    if ( defined $tmp && $tmp ne '' && $tmp ne $cellBorder ) {
        $cellBorder = $tmp;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'cellBorder'}
                || $tmp ne $defaultCssAttrs{'cellBorder'} )
          )
        {
            $cssAttrs{cellBorder} = $cellBorder;
            $defaultCssAttrs{cellBorder} = $cellBorder if $writeDefaults;
        }
    }

    $tmp = $params{headeralign};
    if ( defined $tmp && $tmp ne '' ) {
        $tmp =~ s/ //go;    # remove spaces
        if ( $tmp ne join( ',', @headerAlign ) ) {
            @headerAlign = split( /,/, $tmp );
            if (
                $useCss
                && ( !defined $defaultCssAttrs{'headerAlign'}
                    || $tmp ne $defaultCssAttrs{'headerAlign'} )
              )
            {
                $cssAttrs{headerAlign}        = $tmp;    # store string
                $defaultCssAttrs{headerAlign} = $tmp
                  if $writeDefaults;                     # store string
            }
        }
    }

    $tmp = $params{dataalign};
    if ( defined $tmp && $tmp ne '' ) {
        $tmp =~ s/ //go;                                 # remove spaces
        if ( $tmp ne join( ',', @dataAlign ) ) {
            @dataAlign = split( /,/, $tmp );
            if (
                $useCss
                && ( !defined $defaultCssAttrs{'dataAlign'}
                    || $tmp ne $defaultCssAttrs{'dataAlign'} )
              )
            {
                $cssAttrs{dataAlign}        = $tmp;      # store string
                $defaultCssAttrs{dataAlign} = $tmp
                  if $writeDefaults;                     # store string
            }
        }
    }

    $tmp = $params{tablewidth};
    if ( defined $tmp && $tmp ne '' && $tmp ne $tableWidth ) {
        $tableWidth = $tmp;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'tableWidth'}
                || $tmp ne $defaultCssAttrs{'tableWidth'} )
          )
        {
            $cssAttrs{tableWidth} = $tableWidth;
            $defaultCssAttrs{tableWidth} = $tableWidth if $writeDefaults;
        }
    }

    $tmp = $params{columnwidths};
    if ( defined $tmp && $tmp ne '' ) {
        $tmp =~ s/ //go;    # remove spaces
        if ( $tmp ne join( ',', @columnWidths ) ) {
            @columnWidths = split( /,/, $tmp );
            if (
                $useCss
                && ( !defined $defaultCssAttrs{'columnWidths'}
                    || $tmp ne $defaultCssAttrs{'columnWidths'} )
              )
            {
                $cssAttrs{columnWidths}        = $tmp;    # store string
                $defaultCssAttrs{columnWidths} = $tmp
                  if $writeDefaults;                      # store string
            }
        }
    }

    $tmp = $params{headerrows};
    if ( defined $tmp && $tmp ne '' && $tmp ne $headerRows ) {

        # not used in CSS
        $headerRows = $tmp;
    }

    $tmp = $params{footerrows};
    if ( defined $tmp && $tmp ne '' && $tmp ne $footerRows ) {

        # not used in CSS
        $footerRows = $tmp;
    }

    $tmp = $params{valign};
    if ( defined $tmp && $tmp ne '' && $tmp ne $vAlign ) {
        $vAlign = $tmp if ( defined $tmp );
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'vAlign'}
                || $tmp ne $defaultCssAttrs{'vAlign'} )
          )
        {
            $cssAttrs{vAlign} = $vAlign;
            $defaultCssAttrs{vAlign} = $vAlign if $writeDefaults;
        }
    }

    $tmp = $params{datavalign};
    if ( defined $tmp && $tmp ne '' && $tmp ne $dataVAlign ) {
        $dataVAlign = $tmp if ( defined $tmp );
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'dataVAlign'}
                || $tmp ne $defaultCssAttrs{'dataVAlign'} )
          )
        {
            $cssAttrs{dataVAlign} = $dataVAlign;
            $defaultCssAttrs{dataVAlign} = $dataVAlign if $writeDefaults;
        }
    }

    $tmp = $params{headervalign};
    if ( defined $tmp && $tmp ne '' && $tmp ne $headerVAlign ) {
        $headerVAlign = $tmp if ( defined $tmp );
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'headerVAlign'}
                || $tmp ne $defaultCssAttrs{'headerVAlign'} )
          )
        {
            $cssAttrs{headerVAlign} = $headerVAlign;
            $defaultCssAttrs{headerVAlign} = $headerVAlign if $writeDefaults;
        }
    }

    my $tmpheaderbg = $params{headerbg};
    if (   defined $tmpheaderbg
        && $tmpheaderbg ne ''
        && $tmpheaderbg ne $headerBg )
    {
        $headerBg = $tmpheaderbg;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'headerBg'}
                || $tmpheaderbg ne $defaultCssAttrs{'headerBg'} )
          )
        {
            $cssAttrs{headerBg} = $headerBg;
            $defaultCssAttrs{headerBg} = $headerBg if $writeDefaults;
        }
    }

    # only set headerbgsorted color if it is defined
    # otherwise use headerbg
    my $tmphbgsorted = $tmpheaderbg;
    $tmp = $params{headerbgsorted};
    if ( defined $tmp && $tmp ne '' ) {
        $tmphbgsorted = $tmp;
    }

    if (   defined $tmphbgsorted
        && $tmphbgsorted ne ''
        && $tmphbgsorted ne $headerBgSorted )
    {
        $headerBgSorted = $tmphbgsorted;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'headerBgSorted'}
                || $tmphbgsorted ne $defaultCssAttrs{'headerBgSorted'} )
          )
        {
            $cssAttrs{headerBgSorted} = $tmphbgsorted;
            $defaultCssAttrs{headerBgSorted} = $tmphbgsorted if $writeDefaults;
        }
    }

    $tmp = $params{headercolor};
    if ( defined $tmp && $tmp ne '' && $tmp ne $headerColor ) {
        $headerColor = $tmp;
        if (
            $useCss
            && ( !defined $defaultCssAttrs{'headerColor'}
                || $tmp ne $defaultCssAttrs{'headerColor'} )
          )
        {
            $cssAttrs{headerColor} = $headerColor;
            $defaultCssAttrs{headerColor} = $headerColor if $writeDefaults;
        }
    }

    my $tmpdatabg = $params{databg};
    if ( defined $tmpdatabg && $tmpdatabg ne '' ) {
        $tmpdatabg =~ s/ //go;    # remove spaces
        if ( $tmpdatabg ne join( ',', @dataBg ) ) {
            @dataBg = split( /,/, $tmpdatabg );
            if (
                $useCss
                && ( !defined $defaultCssAttrs{'dataBg'}
                    || $tmpdatabg ne $defaultCssAttrs{'dataBg'} )
              )
            {
                $cssAttrs{dataBg}        = $tmpdatabg;    # store string
                $defaultCssAttrs{dataBg} = $tmpdatabg
                  if $writeDefaults;                      # store string
            }
        }
    }

    # only set databgsorted color if it is defined
    # otherwise use databg
    my $tmpdatabgsorted = $tmpdatabg;
    $tmp = $params{databgsorted};
    if ( defined $tmp && $tmp ne '' ) {
        $tmpdatabgsorted = $tmp;
    }
    if ( defined $tmpdatabgsorted && $tmpdatabgsorted ne '' ) {
        $tmpdatabgsorted =~ s/ //go;    # remove spaces
        if ( $tmpdatabgsorted ne join( ',', @dataBgSorted ) ) {
            @dataBgSorted = split( /,/, $tmpdatabgsorted );
            if (
                $useCss
                && ( !defined $defaultCssAttrs{'dataBgSorted'}
                    || $tmpdatabgsorted ne $defaultCssAttrs{'dataBgSorted'} )
              )
            {
                $cssAttrs{dataBgSorted} = $tmpdatabgsorted;    # store string
                $defaultCssAttrs{dataBgSorted} = $tmpdatabgsorted
                  if $writeDefaults;                           # store string
            }
        }
    }

    $tmp = $params{datacolor};
    if ( defined $tmp && $tmp ne '' ) {
        $tmp =~ s/ //go;                                       # remove spaces
        if ( $tmp ne join( ',', @dataColor ) ) {
            @dataColor = split( /,/, $tmp );
            if (
                $useCss
                && ( !defined $defaultCssAttrs{'dataColor'}
                    || $tmp ne $defaultCssAttrs{'dataColor'} )
              )
            {
                $cssAttrs{dataColor}        = $tmp;            # store string
                $defaultCssAttrs{dataColor} = $tmp
                  if $writeDefaults;                           # store string
            }
        }
    }

    $tmp = $params{summary};
    if ( defined $tmp && $tmp ne '' && $tmp ne $tableSummary ) {
        $tableSummary = $tmp;
    }

    $tmp = $params{caption};
    if ( defined $tmp && $tmp ne '' && $tmp ne $tableCaption ) {
        $tableCaption = $tmp;
    }

    if ($writeDefaults) {

  # just uncomment to write plugin settings as css styles ( .twikiTable{ ... } )
  #_addStylesToHead( $useCss, $writeDefaults, %defaultCssAttrs );
    }
    else {
        _addStylesToHead( $useCss, $writeDefaults, %cssAttrs );
    }

    return $currTablePre . '<nop>';
}

# Convert text to number and date if syntactically possible
sub _convertToNumberAndDate {
    my ($text) = @_;

    $text = _stripHtml($text);

    my $num  = undef;
    my $date = undef;
    if ( $text =~ /^\s*$/ ) {
        $num  = 0;
        $date = 0;
    }

    if ( $text =~ m|^\s*([0-9]{4})[-\s/]0?([0-9]{1,2})[-\s/]0?([0-9]{1,2})| ) {
        # ISO date "2010-03-31", "2010/3/31"
        $date = _timeGM( 0, 0, 0, $3, $2 - 1, $1 );

    } elsif ( $text =~ m|^\s*([0-9]{1,2})[-\s/]*([A-Z][a-z][a-z])[-\s/]*([0-9]{4})\s*-\s*([0-9][0-9]):([0-9][0-9])| ) {
        # "31 Dec 2003 - 23:59", "31-Dec-2003 - 23:59",
        # "31 Dec 2003 - 23:59 - any suffix"
        $date = _timeGM( 0, $5, $4, $1, $mon2num{$2}, $3 );

    } elsif ( $text =~ m|^\s*([0-9]{1,2})[-\s/]([A-Z][a-z][a-z])[-\s/]([0-9]{2,4})\s*$| ) {
        # "31 Dec 2003", "31 Dec 03", "31-Dec-2003", "31/Dec/2003"
        $date = _timeGM( 0, 0, 0, $1, $mon2num{$2}, $3 );

    } elsif ( $text =~ /^\s*(([\+\-]?[0-9]+)(\.([0-9]))?).*$/ ) {
        # for example for attachment sizes: 1.1 K
        # but also for other strings that start with a number
        $num = $1;
    }

    return ( $num, $date );
}

sub _timeGM {
    my ( $sec, $min, $hour, $mday, $mon, $year ) = @_;
    if( length($year) == 2 ) {
        # 2 digit date - round up or down to 4 digit date
        if( $year > 50 ) {
            $year += 1900;
        } else {
            $year += 2000;
        }
    } elsif( $] <= 5.012000 ) {
        # Perl older than 5.12 can't handle dates far out
        # http://perldoc.perl.org/Time/Local.html
        return -2143220400 if( $year < 1902 );
        return  2145848400 if( $year > 2037 );
        # else fall through with acceptable range
    }
    my $time;
    eval { $time = timegm( $sec, $min, $hour, $mday, $mon, $year ) };
    # timegm() may through an exception depending on the arguments.
    # if it does, $time remains undefined, which is fine.
    return $time;
}

sub _processTableRow {
    my ( $thePre, $theRow ) = @_;

    $currTablePre = $thePre || '';
    my $span = 0;
    my $l1   = 0;
    my $l2   = 0;

    if ( !$insideTABLE ) {
        @curTable = ();
        @rowspan  = ();

        $tableCount++;
        $currentSortDirection = $sortDirection{'NONE'};

        if (   defined $requestedTable
            && $requestedTable == $tableCount
            && defined $sortColFromUrl )
        {
            $sortCol              = $sortColFromUrl;
            $sortCol              = $maxSortCols if ( $sortCol > $maxSortCols );
            $currentSortDirection = _getCurrentSortDirection($up);
        }
        elsif ( defined $initSort ) {
            $sortCol              = $initSort - 1;
            $sortCol              = $maxSortCols if ( $sortCol > $maxSortCols );
            $currentSortDirection = _getCurrentSortDirection($initDirection);
        }

    }

    $theRow =~ s/\t/   /go;    # change tabs to space
    $theRow =~ s/\s*$//o;      # remove trailing spaces
    $theRow =~ s/(\|\|+)/'colspan'.$translationToken.length($1)."\|"/geo;   # calc COLSPAN
    my $colCount = 0;
    my @row      = ();
    $span = 0;
    my $value = '';

    foreach ( split( /\|/, $theRow ) ) {
        my $attr = {};
        $span = 1;

        #AS 25-5-01 Fix to avoid matching also single columns
        if (s/colspan$translationToken([0-9]+)//) {
            $span = $1;
            $attr->{colspan} = $span;
        }
        s/^\s+$/ &nbsp; /o;
        ( $l1, $l2 ) = ( 0, 0 );
        if (/^(\s*).*?(\s*)$/) {
            $l1 = length($1);
            $l2 = length($2);
        }
        if ( $l1 >= 2 ) {
            if ( $l2 <= 1 ) {
                $attr->{align} = 'right';
            }
            else {
                $attr->{align} = 'center';
            }
        }
        if ( $span <= 2 ) {
            $attr->{class} =
              _appendColNumberCssClass( $attr->{class}, $colCount );
        }
        if (   defined $columnWidths[$colCount]
            && $columnWidths[$colCount]
            && $span <= 2 )
        {

            # html attribute
            $attr->{width} = $columnWidths[$colCount];
        }

        if (/^(\s|<[^>]*>)*\^(\s|<[^>]*>)*$/) {    # row span above
            $rowspan[$colCount]++;
            push @row, { text => $value, type => 'Y' };
        }
        else {
            for ( my $col = $colCount ; $col < ( $colCount + $span ) ; $col++ )
            {
                if ( defined( $rowspan[$col] ) && $rowspan[$col] ) {
                    my $nRows = scalar(@curTable);
                    my $rspan = $rowspan[$col] + 1;
                    if ( $rspan > 1 ) {
                        $curTable[ $nRows - $rspan ][$col]->{attrs}->{rowspan} =
                          $rspan;
                    }
                    undef( $rowspan[$col] );
                }
            }

            if (
                (
                    (
                        defined $requestedTable
                        && $requestedTable == $tableCount
                    )
                    || defined $initSort
                )
                && defined $sortCol
                && $colCount == $sortCol
              )
            {

                # CSS class name
                if ( $currentSortDirection == $sortDirection{'ASCENDING'} ) {
                    $attr->{class} =
                      _appendSortedAscendingCssClass( $attr->{class} );
                }
                if ( $currentSortDirection == $sortDirection{'DESCENDING'} ) {
                    $attr->{class} =
                      _appendSortedDescendingCssClass( $attr->{class} );
                }
            }

            my $type = '';
            if (/^\s*\*(.*)\*\s*$/) {
                $value = $1;
                if (@headerAlign) {
                    my $align =
                      @headerAlign[ $colCount % ( $#headerAlign + 1 ) ];

                    # html attribute
                    $attr->{align} = $align;
                }
                if ($headerVAlign) {

                    # html attribute
                    $attr->{valign} = $headerVAlign if $headerVAlign;
                }
                elsif ($vAlign) {

                    # html attribute
                    $attr->{valign} = $vAlign;
                }
                $type = 'th';
            }
            else {
                if (/^\s*(.*?)\s*$/) {    # strip white spaces
                    $_ = $1;
                }
                $value = $_;
                if (@dataAlign) {
                    my $align = @dataAlign[ $colCount % ( $#dataAlign + 1 ) ];

                    # html attribute
                    $attr->{align} = $align;
                }
                if ($dataVAlign) {

                    # html attribute
                    $attr->{valign} = $dataVAlign if $dataVAlign;
                }
                elsif ($vAlign) {

                    # html attribute
                    $attr->{valign} = $vAlign;
                }
                $type = 'td';
            }

            push @row, { text => $value, attrs => $attr, type => $type };
        }
        while ( $span > 1 ) {
            push @row, { text => $value, type => 'X' };
            $colCount++;
            $span--;
        }
        $colCount++;
    }
    push @curTable, \@row;
    return $currTablePre
      . '<nop>';    # Avoid TWiki converting empty lines to new paras
}

# Guess if column is a date, number or plain text
sub _guessColumnType {
    my ($col)         = @_;
    my $isDate        = 1;
    my $isNum         = 1;
    my $num           = '';
    my $date          = '';
    my $columnIsValid = 0;
    foreach my $row (@curTable) {
        next if ( !$row->[$col]->{text} );

        # else
        $columnIsValid = 1;
        ( $num, $date ) = _convertToNumberAndDate( $row->[$col]->{text} );

        $isDate = 0 if ( !defined($date) );
        $isNum  = 0 if ( !defined($num) );
        last if ( !$isDate && !$isNum );
        $row->[$col]->{date}   = $date;
        $row->[$col]->{number} = $num;
    }
    return $columnType{'UNDEFINED'} if ( !$columnIsValid );
    my $type = $columnType{'TEXT'};
    if ($isDate) {
        $type = $columnType{'DATE'};
    }
    elsif ($isNum) {
        $type = $columnType{'NUMBER'};
    }
    return $type;
}

# Remove HTML from text so it can be sorted
sub _stripHtml {
    my ($text) = @_;

    $text =~
      s/\[\[[^\]]+\]\[([^\]]+)\]\]/$1/go; # extract label from [[...][...]] link

    my $orgtext =
      $text;    # in case we will remove all contents with stripping html
    $text =~ s/<[^>]+>//go;    # strip HTML
    $text = _getImageTextForSorting($orgtext) if ( $text eq '' );
    $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;    # remove Wiki formatting chars
    $text =~ s/^ *//go;                   # strip leading space space

    return $text;
}

=pod

Retrieve text data from an image html tag to be used for sorting.
First try the alt tag string. If not available, return the url string.
If not available, return the original string.

=cut

sub _getImageTextForSorting {
    my ($text) = @_;

    # try to see _if_ there is any img data for sorting
    my $hasImageTag = ( $text =~ m/\<\s*img([^>]+)>/ );
    return $text if ( !$hasImageTag );

    # first try to get the alt text
    my $key = 'alt';
    $text =~ m/$key=\s*[\"\']([^\"\']*)/;
    return $1 if ( $1 ne '' );

    # else

    # no alt text; use the url
    $key = 'url';
    $text =~ m/$key=\s*[\"\']([^\"\']*)/;
    return $1 if ( $1 ne '' );

    # else

    return $text;
}

=pod

Appends $className to $classList, separated by a space.  

=cut

sub _appendToClassList {
    my ( $classList, $className ) = @_;
    $classList = $classList ? $classList .= ' ' : '';
    $classList .= $className;
    return $classList;
}

sub _appendSortedCssClass {
    my ($classList) = @_;

    return _appendToClassList( $classList, 'twikiSortedCol' );
}

sub _appendRowNumberCssClass {
    my ( $classList, $colListName, $rowNum ) = @_;

    my $rowClassName = 'twikiTableRow' . $colListName . $rowNum;
    return _appendToClassList( $classList, $rowClassName );
}

sub _appendColNumberCssClass {
    my ( $classList, $colNum ) = @_;

    my $colClassName = 'twikiTableCol' . $colNum;
    return _appendToClassList( $classList, $colClassName );
}

sub _appendFirstColumnCssClass {
    my ($classList) = @_;

    return _appendToClassList( $classList, 'twikiFirstCol' );
}

sub _appendLastColumnCssClass {
    my ($classList) = @_;

    return _appendToClassList( $classList, 'twikiLastCol' );
}

sub _appendLastRowCssClass {
    my ($classList) = @_;

    return _appendToClassList( $classList, 'twikiLast' );
}

sub _appendSortedAscendingCssClass {
    my ($classList) = @_;

    return _appendToClassList( $classList, 'twikiSortedAscendingCol' );
}

sub _appendSortedDescendingCssClass {
    my ($classList) = @_;

    return _appendToClassList( $classList, 'twikiSortedDescendingCol' );
}

# The default sort direction.
sub _getDefaultSortDirection {
    return $sortDirection{'ASCENDING'};
}

# Gets the current sort direction.
sub _getCurrentSortDirection {
    my ($currentDirection) = @_;
    $currentDirection ||= _getDefaultSortDirection();
    return $currentDirection;
}

# Gets the new sort direction (needed for sort button) based on the current sort
# direction.
sub _getNewSortDirection {
    my ($currentDirection) = @_;
    if ( !defined $currentDirection ) {
        return _getDefaultSortDirection();
    }
    my $newDirection;
    if ( $currentDirection == $sortDirection{'ASCENDING'} ) {
        $newDirection = $sortDirection{'DESCENDING'};
    }
    if ( $currentDirection == $sortDirection{'DESCENDING'} ) {
        if ($unsortEnabled) {
            $newDirection = $sortDirection{'NONE'};
        }
        else {
            $newDirection = $sortDirection{'ASCENDING'};
        }
    }
    if ( $currentDirection == $sortDirection{'NONE'} ) {
        $newDirection = $sortDirection{'ASCENDING'};
    }
    return $newDirection;
}

=pod

Writes css styles to the head if $useCss is true (when custom attributes have been passed to
the TABLE{} variable.

Explicitly set styles override html styling (in this file marked with comment '# html attribute').

=cut

sub _addStylesToHead {
    my ( $useCss, $writeDefaults, %cssAttrs ) = @_;

    my @styles = ();

    if ( !$didWriteDefaultStyle ) {
        my $id       = 'default';
        my $selector = '.twikiTable';
        my $attr     = 'padding-left:.3em; vertical-align:text-bottom;';
        push( @styles, ".tableSortIcon img {$attr}" );

        if ($cellPadding) {
            my $attr = 'padding:' . $cellPadding . 'px;';
            push( @styles, "$selector td {$attr}" );
            push( @styles, "$selector th {$attr}" );
        }

        #_writeStyleToHead( $id, @styles );
        $didWriteDefaultStyle = 1;
    }

    # only write default style
    return if !$useCss;

    my $selector = '.twikiTable';
    my $id = $writeDefaults ? $writeDefaults : $cssAttrs{tableId};
    $selector .= '#' . $id if !$writeDefaults;

    # tablerules
    if ( defined $cssAttrs{tableRules} ) {
        if ( $cssAttrs{tableRules} eq 'all' ) {
            my $attr = 'border-style:solid;';
            push( @styles, "$selector td {$attr}" );
            push( @styles, "$selector th {$attr}" );
        }
        if ( $cssAttrs{tableRules} eq 'none' ) {
            my $attr = 'border-style:none;';
            push( @styles, "$selector td {$attr}" );
            push( @styles, "$selector th {$attr}" );
        }
        if ( $cssAttrs{tableRules} eq 'cols' ) {
            my $attr = 'border-style:none solid;';
            push( @styles, "$selector td {$attr}" );
            push( @styles, "$selector th {$attr}" );
        }
        if ( $cssAttrs{tableRules} eq 'rows' ) {
            my $attr = 'border-style:solid none;';
            push( @styles, "$selector td {$attr}" );
            push( @styles, "$selector th {$attr}" );
        }
        if ( $cssAttrs{tableRules} eq 'groups' ) {
            my $attr = 'border-style:solid none;';
            push( @styles, "$selector th {$attr}" );
            $attr = 'border-style:none;';
            push( @styles, "$selector td {$attr}" );
        }
    }

    # tableframe
    if ( defined $cssAttrs{tableFrame} ) {
        my $attr = '';
        if ( $cssAttrs{tableFrame} eq 'void' ) {
            $attr = 'border-style:none;';
        }
        if ( $cssAttrs{tableFrame} eq 'above' ) {
            $attr = 'border-style:solid none none none;';
        }
        if ( $cssAttrs{tableFrame} eq 'below' ) {
            $attr = 'border-style:none none solid none;';
        }
        if ( $cssAttrs{tableFrame} eq 'lhs' ) {
            $attr = 'border-style:none none none solid;';
        }
        if ( $cssAttrs{tableFrame} eq 'rhs' ) {
            $attr = 'border-style:none solid none none;';
        }
        if ( $cssAttrs{tableFrame} eq 'hsides' ) {
            $attr = 'border-style:solid none solid none;';
        }
        if ( $cssAttrs{tableFrame} eq 'vsides' ) {
            $attr = 'border-style:none solid none solid;';
        }
        if ( $cssAttrs{tableFrame} eq 'box' ) {
            $attr = 'border-style:solid;';
        }
        if ( $cssAttrs{tableFrame} eq 'border' ) {
            $attr = 'border-style:solid;';
        }
        push( @styles, "$selector {$attr}" );
    }

    # tableborder
    if ( defined $cssAttrs{tableBorder} ) {
        my $tableBorderWidth = $cssAttrs{tableBorder} || 0;
        my $attr = 'border-width:' . $tableBorderWidth . 'px;';
        push( @styles, "$selector {$attr}" );
    }

    # cellborder
    if ( defined $cssAttrs{cellBorder} ) {
        my $cellBorderWidth = $cssAttrs{cellBorder} || 0;
        my $attr = 'border-width:' . $cellBorderWidth . 'px;';
        push( @styles, "$selector td {$attr}" );
        push( @styles, "$selector th {$attr}" );
    }

    # tablewidth
    if ( defined $cssAttrs{tableWidth} ) {
        my $attr = 'width:' . $cssAttrs{tableWidth} . ';';
        push( @styles, "$selector {$attr}" );
    }

    # valign
    if ( defined $cssAttrs{vAlign} ) {
        my $attr = 'vertical-align:' . $cssAttrs{vAlign} . ';';
        push( @styles, "$selector td {$attr}" );
        push( @styles, "$selector th {$attr}" );
    }

    # headerVAlign
    if ( defined $cssAttrs{headerVAlign} ) {
        my $attr = 'vertical-align:' . $cssAttrs{headerVAlign} . ';';
        push( @styles, "$selector th {$attr}" );
    }

    # dataVAlign
    if ( defined $cssAttrs{dataVAlign} ) {
        my $attr = 'vertical-align:' . $cssAttrs{dataVAlign} . ';';
        push( @styles, "$selector td {$attr}" );
    }

    # headerbg
    if ( defined $cssAttrs{headerBg} ) {
        unless ( $cssAttrs{headerBg} =~ /none/i ) {
            my $attr = 'background-color:' . $cssAttrs{headerBg} . ';';
            push( @styles, "$selector th {$attr}" );
        }
    }

    # headerbgsorted
    if ( defined $cssAttrs{headerBgSorted} ) {
        unless ( $cssAttrs{headerBgSorted} =~ /none/i ) {
            my $attr = 'background-color:' . $cssAttrs{headerBgSorted} . ';';
            push( @styles, "$selector th.twikiSortedCol {$attr}" );
        }
    }

    # headercolor
    if ( defined $cssAttrs{headerColor} ) {
        my $attr = 'color:' . $cssAttrs{headerColor} . ';';
        push( @styles, "$selector th {$attr}" );
        push( @styles, "$selector th a:link {$attr}" );
        push( @styles, "$selector th a:visited {$attr}" );
        push( @styles, "$selector th a:link font {$attr}" );
        push( @styles, "$selector th a:visited font {$attr}" );
        my $hoverLinkColor = $cssAttrs{headerBg} || '#fff';
        my $hoverBackgroundColor = $cssAttrs{headerColor};
        $attr =
            'color:'
          . $hoverLinkColor
          . ';background-color:'
          . $hoverBackgroundColor . ';';
        push( @styles, "$selector th a:hover {$attr}" );
        push( @styles, "$selector th a:hover font {$attr}" );
    }

    # databg (array)
    if ( defined $cssAttrs{dataBg} ) {
        unless ( $cssAttrs{dataBg} =~ /none/i ) {
            my $count = 0;
            my @attrDataBg = split( /,/, $cssAttrs{dataBg} );
            foreach (@attrDataBg) {
                my $color = $_;
                next if !$color;
                my $rowSelector = 'twikiTableRow' . 'dataBg';
                $rowSelector .= $count;
                my $attr = 'background-color:' . $_ . ';';
                push( @styles, "$selector tr.$rowSelector td {$attr}" );
                $count++;
            }
        }
    }

    # databgsorted (array)
    if ( defined $cssAttrs{dataBgSorted} ) {
        unless ( $cssAttrs{dataBgSorted} =~ /none/i ) {
            my $count = 0;
            my @attrDataBgSorted = split( /,/, $cssAttrs{dataBgSorted} );
            foreach (@attrDataBgSorted) {
                my $color = $_;
                next if !$color;
                my $rowSelector = 'twikiTableRow' . 'dataBg';
                $rowSelector .= $count;
                my $attr = 'background-color:' . $_ . ';';
                push( @styles,
                    "$selector tr.$rowSelector td.twikiSortedCol {$attr}" );
                $count++;
            }
        }
    }

    # datacolor (array)
    if ( defined $cssAttrs{dataColor} ) {
        unless ( $cssAttrs{dataColor} =~ /none/i ) {
            my $count = 0;
            my @attrDataColor = split( /,/, $cssAttrs{dataColor} );
            foreach (@attrDataColor) {
                my $color = $_;
                next if !$color;
                my $rowSelector = 'twikiTableRow' . 'dataColor';
                $rowSelector .= $count;
                my $attr = 'color:' . $_ . ';';
                push( @styles, "$selector tr.$rowSelector td {$attr}" );
                push( @styles, "$selector tr.$rowSelector td font {$attr}" );
                $count++;
            }
        }
    }

    # columnwidths
    if ( defined $cssAttrs{columnWidths} ) {
        my $count = 0;
        my @attrColumnWidths = split( /,/, $cssAttrs{columnWidths} );
        foreach (@attrColumnWidths) {
            my $width = $_;
            next if !$width;
            my $colSelector = 'twikiTableCol';
            $colSelector .= $count;
            my $attr = 'width:' . $_ . ';';
            push( @styles, "$selector td.$colSelector {$attr}" );
            push( @styles, "$selector th.$colSelector {$attr}" );
            $count++;
        }
    }

    # headeralign
    if ( defined $cssAttrs{headerAlign} ) {
        my @attrHeaderAlign = split( /,/, $cssAttrs{headerAlign} );
        if ( scalar @attrHeaderAlign == 1 ) {
            my $align = $attrHeaderAlign[0];
            my $attr  = 'text-align:' . $align . ';';
            push( @styles, "$selector th {$attr}" );
        }
        else {
            my $count = 0;
            foreach (@attrHeaderAlign) {
                my $width = $_;
                next if !$width;
                my $colSelector = 'twikiTableCol';
                $colSelector .= $count;
                my $attr = 'text-align:' . $_ . ';';
                push( @styles, "$selector th.$colSelector {$attr}" );
                $count++;
            }
        }
    }

    # dataAlign
    if ( defined $cssAttrs{dataAlign} ) {
        my @attrDataAlign = split( /,/, $cssAttrs{dataAlign} );
        if ( scalar @attrDataAlign == 1 ) {
            my $align = $attrDataAlign[0];
            my $attr  = 'text-align:' . $align . ';';
            push( @styles, "$selector td {$attr}" );
        }
        else {
            my $count = 0;
            foreach (@attrDataAlign) {
                my $width = $_;
                next if !$width;
                my $colSelector = 'twikiTableCol';
                $colSelector .= $count;
                my $attr = 'text-align:' . $_ . ';';
                push( @styles, "$selector td.$colSelector {$attr}" );
                $count++;
            }
        }
    }

    # cellspacing : no good css equivalent; use table tag attribute

    # cellpadding
    if ( defined $cssAttrs{cellPadding} ) {
        my $attr = 'padding:' . $cssAttrs{cellPadding} . 'px;';
        push( @styles, "$selector td {$attr}" );
        push( @styles, "$selector th {$attr}" );
    }

    return if !scalar @styles;
    _writeStyleToHead( $id, @styles );
}

sub _writeStyleToHead {
    my ( $id, @styles ) = @_;

    my $style = join( "\n", @styles );
    my $header =
      '<style type="text/css" media="all">' . "\n" . $style . "\n" . '</style>';
    TWiki::Func::addToHEAD( 'TABLEPLUGIN_' . $id, $header );
}

sub _countHeaderRows {
    my ( $table ) = @_;

    # find the number of header rows
    my $count = 0;
    foreach my $row (@$table) {
        my $isHeader = 1;
        foreach my $cell (@$row) {
            $isHeader = 0 if ( $cell->{type} ne 'th' );
        }
        return $count unless( $isHeader );
        $count++;
    }
    return $count;
}

sub emitTable {

    #Validate headerrows/footerrows and modify if out of range
    if ( $headerRows > @curTable ) {
        $headerRows = @curTable;    # limit header to size of table!
    }
    if ( $headerRows == 0 ) {
        $headerRows = _countHeaderRows( \@curTable );
    }
    if ( $headerRows + $footerRows > @curTable ) {
        $footerRows = @curTable - $headerRows;  # and footer to whatever is left
    }

    my $sortThisTable = ( $sortAllTables && $headerRows > 0 );
    my $tattrs = { class => 'twikiTable' };
    $tattrs->{border} = $tableBorder
      if defined $tableBorder && $tableBorder ne '';
    $tattrs->{cellspacing} = $cellSpacing
      if defined $cellSpacing && $cellSpacing ne '';
    $tattrs->{cellpadding} = $cellPadding
      if defined $cellPadding && $cellPadding ne '';
    $tattrs->{id} = $tableId if defined $tableId && $tableId ne '';
    $tattrs->{summary} = $tableSummary
      if defined $tableSummary && $tableSummary ne '';
    $tattrs->{frame} = $tableFrame if defined $tableFrame && $tableFrame ne '';
    $tattrs->{rules} = $tableRules if defined $tableRules && $tableRules ne '';
    $tattrs->{width} = $tableWidth if defined $tableWidth && $tableWidth ne '';

    my $text = $currTablePre . CGI::start_table($tattrs);
    $text .= $currTablePre . CGI::caption($tableCaption) if ($tableCaption);
    my $stype = '';

    # count the number of cols to prevent looping over non-existing columns
    my $maxCols = 0;

    #Flush out any remaining rowspans
    for ( my $i = 0 ; $i < @rowspan ; $i++ ) {
        if ( defined( $rowspan[$i] ) && $rowspan[$i] ) {
            my $nRows = scalar(@curTable);
            my $rspan = $rowspan[$i] + 1;
            my $r     = $nRows - $rspan;
            $curTable[$r][$i]->{attrs} ||= {};
            if ( $rspan > 1 ) {
                $curTable[$r][$i]->{attrs}->{rowspan} = $rspan;
            }
        }
    }

    if (
        (
               defined $sortCol
            && defined $requestedTable
            && $requestedTable == $tableCount
        )
        || defined $initSort
      )
    {

        # DG 08 Aug 2002: Allow multi-line headers
        my @header = splice( @curTable, 0, $headerRows );

        # DG 08 Aug 2002: Skip sorting any trailers as well
        my @trailer = ();
        if ( $footerRows && scalar(@curTable) > $footerRows ) {
            @trailer = splice( @curTable, -$footerRows );
        }

        # Count the maximum number of columns of this table
        for my $row ( 0 .. $#curTable ) {
            my $thisRowMaxColCount = 0;
            for my $col ( 0 .. $#{ $curTable[$row] } ) {
                $thisRowMaxColCount++;
            }
            $maxCols = $thisRowMaxColCount
              if ( $thisRowMaxColCount > $maxCols );
        }

        # Handle multi-row labels by killing rowspans in sorted tables
        for my $row ( 0 .. $#curTable ) {
            for my $col ( 0 .. $#{ $curTable[$row] } ) {
                $curTable[$row][$col]->{attrs}->{rowspan} = 1;
                if ( $curTable[$row][$col]->{type} eq 'Y' ) {
                    $curTable[$row][$col]->{text} =
                      $curTable[ $row - 1 ][$col]->{text};
                    $curTable[$row][$col]->{type} = 'td';
                }
            }
        }

        $stype = $columnType{'UNDEFINED'}; # default value

        # only get the column type if within bounds
        if ( $sortCol < $maxCols ) {
            $stype = _guessColumnType($sortCol);
        }

        # invalidate sorting if no valid column
        if ( $stype eq $columnType{'UNDEFINED'} ) {
            undef $initSort;
            undef $sortCol;
        }
        elsif ( $stype eq $columnType{'TEXT'} ) {
            if ( $currentSortDirection == $sortDirection{'DESCENDING'} ) {

                # efficient way of sorting stripped HTML text
                # SMELL: efficient? That's not efficient!
                @curTable = map { $_->[0] }
                  sort { $b->[1] cmp $a->[1] }
                  map { [ $_, lc _stripHtml( $_->[$sortCol]->{text} ) ] }
                  @curTable;
            }
            if ( $currentSortDirection == $sortDirection{'ASCENDING'} ) {
                @curTable = map { $_->[0] }
                  sort { $a->[1] cmp $b->[1] }
                  map { [ $_, lc _stripHtml( $_->[$sortCol]->{text} ) ] }
                  @curTable;
            }
        }
        else {
            if ( $currentSortDirection == $sortDirection{'DESCENDING'} ) {
                @curTable =
                  sort { $b->[$sortCol]->{$stype} <=> $a->[$sortCol]->{$stype} }
                  @curTable;
            }
            if ( $currentSortDirection == $sortDirection{'ASCENDING'} ) {
                @curTable =
                  sort { $a->[$sortCol]->{$stype} <=> $b->[$sortCol]->{$stype} }
                  @curTable;
            }

        }

        # DG 08 Aug 2002: Cleanup after the header/trailer splicing
        # this is probably awfully inefficient - but how big is a table?
        @curTable = ( @header, @curTable, @trailer );
    }    # if defined $sortCol ...

    my $rowCount       = 0;
    my $numberOfRows   = scalar(@curTable);
    my $dataColorCount = 0;

    my @headerRowList = ();
    my @bodyRowList   = ();
    my @footerRowList = ();

    my $isPastHeaderRows = 0;

    foreach my $row (@curTable) {
        my $rowtext  = '';
        my $colCount = 0;

        # keep track of header cells: if all cells are header cells, do not
        # update the data color count
        my $headerCellCount = 0;
        my $numberOfCols    = scalar(@$row);

        foreach my $fcell (@$row) {

            # check if cell exists
            next if ( !$fcell || !$fcell->{type} );

            my $tableAnchor = '';
            next
              if ( $fcell->{type} eq 'X' )
              ;    # data was there so sort could work with col spanning
            my $type = $fcell->{type};
            my $cell = $fcell->{text};
            my $attr = $fcell->{attrs} || {};

            my $newDirection;
            my $isSorted = 0;

            if (
                   $currentSortDirection != $sortDirection{'NONE'}
                && defined $sortCol
                && $colCount == $sortCol

                # Removing the line below hides the marking of sorted columns
                # until the user clicks on a header (KJL)
                # && defined $requestedTable && $requestedTable == $tableCount
                && $stype ne ''
              )
            {
                $isSorted     = 1;
                $newDirection = _getNewSortDirection($currentSortDirection);
            }
            else {
                $newDirection = _getDefaultSortDirection();
            }

            if ( $type eq 'th' ) {
                $headerCellCount++;
                unless ($upchar) {
                    $upchar = CGI::span(
                        { class => 'tableSortIcon tableSortUp' },
                        CGI::img(
                            {
                                src    => $iconUrl . 'tablesortup.gif',
                                border => 0,
                                width  => 11,
                                height => 13,
                                alt    => 'Sorted ascending',
                                title  => 'Sorted ascending'
                            }
                        )
                    );
                    $downchar = CGI::span(
                        { class => 'tableSortIcon tableSortDown' },
                        CGI::img(
                            {
                                src    => $iconUrl . 'tablesortdown.gif',
                                border => 0,
                                width  => 11,
                                height => 13,
                                alt    => 'Sorted descending',
                                title  => 'Sorted descending'
                            }
                        )
                    );
                    $diamondchar = CGI::span(
                        { class => 'tableSortIcon tableSortUp' },
                        CGI::img(
                            {
                                src    => $iconUrl . 'tablesortdiamond.gif',
                                border => 0,
                                width  => 11,
                                height => 13,
                                alt    => 'Sort',
                                title  => 'Sort'
                            }
                        )
                    );
                }

                # DG: allow headers without b.g too (consistent and yes,
                # I use this)
                # html attribute
                $attr->{bgcolor} = $headerBg unless ( $headerBg =~ /none/i );

                # attribute 'maxcols' does not exist in html
                # so commenting out
                #$attr->{maxCols} = $maxCols;

                if ($isSorted) {
                    if ( $currentSortDirection == $sortDirection{'ASCENDING'} )
                    {
                        $tableAnchor = $upchar;
                    }
                    if ( $currentSortDirection == $sortDirection{'DESCENDING'} )
                    {
                        $tableAnchor = $downchar;
                    }
                }

                if (   defined $sortCol
                    && $colCount == $sortCol
                    && defined $requestedTable
                    && $requestedTable == $tableCount )
                {

                    $tableAnchor =
                      CGI::a( { name => 'sorted_table' }, '<!-- -->' )
                      . $tableAnchor;
                }

                if ($headerColor) {

                    my $cellAttrs = { color => $headerColor };

                    # html attribute
                    $cell = CGI::font( $cellAttrs, $cell );
                }

                if ( $sortThisTable && $rowCount == 0 ) {
                    if ($isSorted) {
                        unless ( $headerBgSorted =~ /none/i ) {

                            # html attribute
                            $attr->{bgcolor} = $headerBgSorted;
                        }
                    }

                    my $debugText      = '';
                    my $linkAttributes = {
                        href => $url
                          . 'sortcol='
                          . $colCount
                          . ';table='
                          . $tableCount . ';up='
                          . $newDirection
                          . '#sorted_table',
                        rel   => 'nofollow',
                        title => 'Sort by this column'
                    };
                    if ( $cell =~ /\[\[|href/o ) {
                        $cell .=
                            $debugText . ' '
                          . CGI::a( $linkAttributes, $diamondchar )
                          . $tableAnchor;
                    }
                    else {
                        $cell =
                            $debugText
                          . CGI::a( $linkAttributes, $cell )
                          . $tableAnchor;
                    }
                }

            }
            else {

                # $type is not 'th'
                if (@dataBg) {
                    my $bgcolor;
                    if ( $isSorted && @dataBgSorted ) {
                        $bgcolor =
                          $dataBgSorted[ $dataColorCount % (
                              $#dataBgSorted + 1 ) ];
                    }
                    else {
                        $bgcolor =
                          $dataBg[ $dataColorCount % ( $#dataBg + 1 ) ];
                    }
                    unless ( $bgcolor =~ /none/i ) {

                        # html attribute
                        $attr->{bgcolor} = $bgcolor;
                    }
                }
                if (@dataColor) {
                    my $color =
                      $dataColor[ $dataColorCount % ( $#dataColor + 1 ) ];

                    unless ( $color =~ /^(none)$/i ) {
                        my $cellAttrs = { color => $color };

                        # html attribute
                        $cell = CGI::font( $cellAttrs, ' ' . $cell . ' ' );
                    }
                }
                $type = 'td' unless $type eq 'Y';
            }    ###if( $type eq 'th' )

            if ($isSorted) {
                $attr->{class} = _appendSortedCssClass( $attr->{class} );
            }

            my $isLastRow = ( $rowCount == $numberOfRows - 1 );
            if ( $attr->{rowspan} ) {
                $isLastRow =
                  ( ( $rowCount + ( $attr->{rowspan} - 1 ) ) ==
                      $numberOfRows - 1 );
            }

            # CSS class name
            $attr->{class} = _appendFirstColumnCssClass( $attr->{class} )
              if $colCount == 0;
            my $isLastCol = ( $colCount == $numberOfCols - 1 );
            $attr->{class} = _appendLastColumnCssClass( $attr->{class} )
              if $isLastCol;

            $attr->{class} = _appendLastRowCssClass( $attr->{class} )
              if $isLastRow;

            $colCount++;
            next if ( $type eq 'Y' );
            my $fn = 'CGI::' . $type;
            no strict 'refs';
            my $cellEndPadding = ' ';
            $cellEndPadding = "\n$currTablePre" if( $cell =~ /$escNewline/ );
            $rowtext .= "\n$currTablePre" . &$fn( $attr, " $cell$cellEndPadding" );
            use strict 'refs';
        }    # foreach my $fcell ( @$row )

        # assign css class names to tr
        # based on settings: dataBg, dataBgSorted
        my $trClassName = '';

        # just 2 css names is too limited, but we will keep it for compatibility
        # with existing style sheets
        my $rowTypeName =
          ( $rowCount % 2 ) ? 'twikiTableEven' : 'twikiTableOdd';
        $trClassName = _appendToClassList( $trClassName, $rowTypeName );

        if ( scalar @dataBgSorted ) {
            my $modRowNum = $dataColorCount % ( $#dataBgSorted + 1 );
            $trClassName =
              _appendRowNumberCssClass( $trClassName, 'dataBgSorted',
                $modRowNum );
        }
        if ( scalar @dataBg ) {
            my $modRowNum = $dataColorCount % ( $#dataBg + 1 );
            $trClassName =
              _appendRowNumberCssClass( $trClassName, 'dataBg', $modRowNum );
        }
        if ( scalar @dataColor ) {
            my $modRowNum = $dataColorCount % ( $#dataColor + 1 );
            $trClassName =
              _appendRowNumberCssClass( $trClassName, 'dataColor', $modRowNum );
        }
        $rowtext .= "\n$currTablePre";

        my $rowHTML =
          "\n$currTablePre" . CGI::Tr( { class => $trClassName }, $rowtext );

        my $isHeaderRow = ( $headerCellCount == $colCount );
        my $isFooterRow = ( ( $numberOfRows - $rowCount ) <= $footerRows );

		if (!$isHeaderRow && !$isFooterRow) {
			# don't include non-adjacent header rows to the top block of header rows
			$isPastHeaderRows = 1;
		}
		
		
        if ($isFooterRow) {
            push @footerRowList, $rowHTML;
        }
        elsif ($isHeaderRow && !$isPastHeaderRows) {
            push( @headerRowList, $rowHTML );
        }
        else {
            push @bodyRowList, $rowHTML;
            $dataColorCount++;
        }
        
		if ($isHeaderRow) {
			# reset data color count to start with first color after
            # each table heading
            $dataColorCount = 0;
		}
		
        $rowCount++;
    }    # foreach my $row ( @curTable )


# Removing thead and tbody from following to fix Item5865
# In future - we need to work on better mechanism to apply 
# better thead/tbody to the tables, just removed thead/tbody words
# fix - starts
    my $thead =
        ""
      . join( "", @headerRowList )
      . "";
    $text .= $currTablePre . $thead if scalar @headerRowList;

    my $tfoot =
        "\n$currTablePre<tfoot>"
      . join( "", @footerRowList )
      . "\n$currTablePre</tfoot>";
    $text .= $currTablePre . $tfoot if scalar @footerRowList;

    my $tbody =
      "" . join( "", @bodyRowList ) . "";
    $text .= $currTablePre . $tbody if scalar @bodyRowList;

# fix ends for Item5865
#
    $text .= $currTablePre . CGI::end_table() . "\n";
    _setDefaults();
    return $text;
}

sub _handleEmbeddedTML {
    my ( $text ) = @_;
    if( $text =~ /(^|[\n\r])(\s*)\|/os ) {
        # Recursively handle embedded tables
        handler( $text );
    }

    $text =~ s/\r?\n/$escNewline/gos;
    $text =~ s/\|/$escPipe/gos;
    return $text;
}

sub _restoreEmbeddedTML {
    #my ( $_[0] ) = @_;
    $_[0] =~ s/$escNewline/\n/gos;
    $_[0] =~ s/$escPipe/\|/gos;
}

sub _addEmbeddedNestingLevel
{
    my( $type, $levelRef ) = @_;

    my $text = '';
    if( $type =~ />>/ ) {
        $$levelRef++;
        $text = "$escNesting-$$levelRef-$escStart";
    } else {
        $text = "$escNesting-$$levelRef-$escEnd";
        $$levelRef-- if( $$levelRef > 0 );
    }
    return $text;
}

sub handler {
    ### my ( $text, $removed ) = @_;

    unless ($TWiki::Plugins::TablePlugin::initialised) {
        $insideTABLE = 0;
        $tableCount  = 0;
        $didWriteDefaultStyle = 0;

        $twoCol = 1;

        my $cgi = TWiki::Func::getCgiQuery();
        return unless $cgi;

        # Copy existing values
        my (@origSort, @origTable, @origUp);
        @origSort  = $cgi->param('sortcol');
        @origTable = $cgi->param('table');
        @origUp    = $cgi->param('up');
        $cgi->delete('sortcol', 'table', 'up');
        $url = $cgi->url(-absolute => 1, -path => 1) . '?';
        my $queryString = $cgi->query_string();
        $url .= $queryString . ';' if $queryString;

        # Restore parameters, so we don't interfere on the remaining execution
        $cgi->param( -name => 'sortcol', -value => \@origSort )  if @origSort;
        $cgi->param( -name => 'table',   -value => \@origTable ) if @origTable;
        $cgi->param( -name => 'up',      -value => \@origUp )    if @origUp;

        $sortColFromUrl =
          $cgi->param('sortcol');    # zero based: 0 is first column
        $requestedTable = $cgi->param('table');
        $up             = $cgi->param('up');

        $sortTablesInText = 0;
        $sortAttachments  = 0;
        my $tmp = TWiki::Func::getPreferencesValue('TABLEPLUGIN_SORT');
        if ( !$tmp || $tmp =~ /^all$/oi ) {
            $sortTablesInText = 1;
            $sortAttachments  = 1;
        }
        elsif ( $tmp =~ /^attachments$/oi ) {
            $sortAttachments = 1;
        }

        $pluginAttrs =
          TWiki::Func::getPreferencesValue('TABLEPLUGIN_TABLEATTRIBUTES');
        $prefsAttrs = TWiki::Func::getPreferencesValue('TABLEATTRIBUTES');
        _setDefaults();

        $TWiki::Plugins::TablePlugin::initialised = 1;
    }

    # Handle embedded TWiki tables, and escape newlines & pipe symbol in |>> ... <<| blocks.
    # First we add the nesting level so that blocks can be handled left-to-right, inside-out.
    # Example:
    # | A |>> B <<|>> C start |>> | C1 | C2 | <<| C end <<|
    # Becomes:
    # | A |esc-1-start B esc-1-end|esc-1-start C start |esc-2-start | C1 | C2 | esc-2-end| C end esc-1-end|
    # Which allows us to handle matching & nested esc-n-start ... esc-n-end
    my $level = 0;
    $_[0] =~ s/((?<=\|)>>|<<(?=\|))/_addEmbeddedNestingLevel( $1, \$level )/geos;
    $_[0] =~ s/$escNesting-([0-9]+)-$escStart(.*?)$escNesting-\1-$escEnd/_handleEmbeddedTML( $2 )/geos;
    $_[0] =~ s/$escNesting-[0-9]+-[$escStart$escEnd]//go; # Clean up unbalanced tokens

    undef $initSort;
    $insideTABLE = 0;
    my $defaultSort = $sortAllTables;
    my $acceptable = $sortAllTables;

    my @lines = split( /\r?\n/, $_[0] );
    for (@lines) {
        if (
s/%TABLE(?:{(.*?)})?%/_parseParameters(1,undef,TWiki::Func::extractParameters($1))/se
          )
        {
            $acceptable = 1;
        }
        elsif (s/^(\s*)\|(.*\|\s*)$/_processTableRow($1,$2)/eo) {
            $insideTABLE = 1;
        }
        elsif ($insideTABLE) {
            $_           = emitTable() . $_;
            $insideTABLE = 0;
            undef $initSort;
            $sortAllTables = $defaultSort;
            $acceptable    = $defaultSort;
        }
    }
    $_[0] = join( "\n", @lines );

    if ($insideTABLE) {
        $_[0] .= emitTable();
    }

    # Restore newlines and pipe symbols in |>>...<<| table cells
    _restoreEmbeddedTML( $_[0] );
}

1;
