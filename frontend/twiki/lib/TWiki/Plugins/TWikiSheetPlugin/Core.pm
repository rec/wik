# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2016-2018 Peter Thoeny, peter[at]thoeny.org 
# Copyright (C) 2016-2018 TWiki Contributors. All Rights Reserved.
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

package TWiki::Plugins::TWikiSheetPlugin::Core;

use Config;
use Fcntl qw(:flock);

our $debug = $TWiki::cfg{Plugins}{TWikiSheetPlugin}{Debug} || 0;

# =========================
# constants

our $canFlock = $Config{d_flock};      # file locking is not available on all platforms
our $vesc = "\x06";
our $vbar = "\x07";
our $tmlToJson = {
    '\\%\\x06VBAR\\%' => $vbar,
    '&#124;'          => $vbar,
    '\\%\\x06BR\\%'   => "\\n",
    '<br>'       => "\\n",
    '<br/>'      => "\\n",
    '<br />'     => "\\n",
};
our $jsonToTml = {
    '\\|'  => '%VBAR%',
    "\\n"  => '%BR%',
};
our $tableMarker = "~TWIKISHEETPLUGIN_TABLE_MARKER~";

our $pubBase = '%PUBURLPATH%/%SYSTEMWEB%/TWikiSheetPlugin';
our $restGetUrl = '%SCRIPTURL{rest}%/TWikiSheetPlugin/get';
our $restSaveUrl = '%SCRIPTURL{rest}%/TWikiSheetPlugin/save';
our $c = $debug ? '' : '//';

our $htmlHead = <<"HERE";
<script src="$pubBase/handsontable/dist/handsontable.full.js"></script>
<link  href="$pubBase/handsontable/dist/handsontable.full.css" rel="stylesheet" media="screen" />
<script src="$pubBase/ruleJS/dist/lib/lodash/lodash.js"></script>
<script src="$pubBase/ruleJS/dist/lib/underscore.string/underscore.string.js"></script>
<script src="$pubBase/ruleJS/dist/lib/moment/moment.js"></script>
<script src="$pubBase/ruleJS/dist/lib/numeral/numeral.js"></script>
<script src="$pubBase/ruleJS/dist/lib/numericjs/numeric.js"></script>
<script src="$pubBase/ruleJS/dist/lib/js-md5/md5.js"></script>
<script src="$pubBase/ruleJS/dist/lib/jstat/jstat.js"></script>
<script src="$pubBase/ruleJS/dist/lib/formulajs/formula.js"></script>
<script src="$pubBase/ruleJS/dist/js/parser.js"></script>
<script src="$pubBase/ruleJS/dist/js/ruleJS.js"></script>
<script src="$pubBase/handsontable-ruleJS/src/handsontable.formula.js"></script>
<link  href="$pubBase/handsontable-ruleJS/src/handsontable.formula.css" rel="stylesheet" media="screen" />
<link  href="$pubBase/twSheet.css" rel="stylesheet" media="screen" />
<script type="text/javascript">
  var twSheets = {};
  function twSheetSetReadOnly( webTopic, n, readOnly ) {
    twSheets[webTopic][n].hotInstance.updateSettings({
      cells: function (row, col, prop) {
        var cellProperties = {};
        cellProperties.readOnly = readOnly;
        return cellProperties;
      }
    })
  }
  function twSheetAfterChange( webTopic, n, changes ) {
    $c console.log( '- twSheetAfterChange( '+webTopic+', '+n+', '+changes+' )' );
    var tws = twSheets[webTopic][n];
    if( tws.remoteUpdate ) {
      return; // avoid recursion of updates
    }
    if( \$authenticated && tws.save ) {
      if(!tws.uniqueID) {
        var random = Math.floor( Math.random() * 9000 + 1000 );
        tws.uniqueID = '%WIKINAME%-' + random.toString();
      }
      changes.unshift( tws.uniqueID );
      tws.changesQueue.push( changes );
      window.clearTimeout( tws.changesTimer );
      tws.changesTimer = window.setTimeout( function() {
        tws.changesTimer = null;
        var postData = {
          action: 'update',
          webTopic: webTopic,
          tableNumber: n,
          changes: JSON.stringify( tws.changesQueue )
        }
        tws.changesQueue = [];
        $c console.log( '- postData: '+JSON.stringify( postData, null, ' ' ) );
        var jqxhr = \$.ajax({
          url: '$restSaveUrl',
          method: 'POST',
          data: postData,
          dataType: 'json'
        })
        .done(function( result ) {
          // FIXME: check return code and push data back to queue if needed
          $c console.log( '- save ok: ' + JSON.stringify( result, null, ' ') );
        })
        .fail(function() {
          // FIXME: push data back to queue
          alert( 'TWiki Sheet Error: Failed to save changes' );
        });
      }, 500 );

    } else if( tws.save ) {
      alert( 'TWiki Sheet Error: You have to login before you can save changes' );
    }
  }
  function twSheetInitTable( webTopic, n ) {
    $c console.log( '- twSheetInitTable( '+webTopic+', '+n+' )' );
    var tws = twSheets[webTopic][n];
    if( !tws.concurrent || !\$authenticated ) {
      return;
    }
    var getReadIndexQuery = {
      action: 'getReadIndex',
      webTopic: webTopic,
      tableNumber: n
    }
    var jqxhr = \$.ajax({
      url: '$restGetUrl',
      method: 'GET',
      data: getReadIndexQuery,
      dataType: 'json'
    })
    .done(function( result ) {
      $c console.log( '- getReadIndex ok: ' + JSON.stringify( result, null, ' ') );
      if( result && !result.error ) {
        tws.readIndex = result.index;
        setInterval(
          function() {
            var tws = twSheets[webTopic][n];
            var getChangesQuery = {
              action: 'getChanges',
              webTopic: webTopic,
              tableNumber: n,
              index: tws.readIndex
            }
            var jqxhr = \$.ajax({
              url: '$restGetUrl',
              method: 'GET',
              data: getChangesQuery,
              dataType: 'json'
            })
            .done(function( result ) {
              $c console.log( '- getChanges ok: ' + JSON.stringify( result, null, ' ') );
              if( result && !result.error ) {
                tws.readIndex = result.index;
                tws.hotInstance.unlisten();
                tws.remoteUpdate = 0;
                for (var i = 0; i < result.changes.length; i++) {
                  var changeArray = result.changes[i];
                  var user = changeArray[0];
                  if( user !== tws.uniqueID ) {
                    var action = changeArray[1];
                    if( action === 'change' ) {
                      tws.remoteUpdate = 1;
                      var row = changeArray[2];
                      var col = changeArray[3];
                      var newVal = changeArray[5];
                      tws.data[row][col] = newVal;
                    } else if( action === 'createRow' ) {
                      tws.remoteUpdate = 1;
                      var row = changeArray[2];
                      var n = changeArray[3];
                      var nCol = tws.data[0].length;
                      var emptyCells = [];
                      for( var c = 0; c < nCol; c++ ) {
                          emptyCells.push( '' );
                      }
                      for( var r = 0; r < n; r++ ) {
                          tws.data.splice( row, 0, emptyCells );
                      }
                    } else if( action === 'removeRow' ) {
                      tws.remoteUpdate = 1;
                      var row = changeArray[2];
                      var n = changeArray[3];
                      tws.data.splice( row, n );
                    } else if( action === 'createCol' ) {
                      tws.remoteUpdate = 1;
                      var col = changeArray[2];
                      var n = changeArray[3];
                      var nRow = tws.data.length;
                      for( var r = 0; r < nRow; r++ ) {
                        for( var c = col; c < col + n; c++ ) {
                          tws.data[r].splice( c, 0, '' );
                        }
                      }
                    } else if( action === 'removeCol' ) {
                      tws.remoteUpdate = 1;
                      var col = changeArray[2];
                      var n = changeArray[3];
                      var nRow = tws.data.length;
                      for( var r = 0; r < nRow; r++ ) {
                        tws.data[r].splice( col, n );
                      }
                    }
                  }
                }
                if( tws.remoteUpdate ) {
                  tws.hotInstance.render();
                  tws.remoteUpdate = 1;
                }
                tws.hotInstance.listen();
              }
            })
            .fail(function() {
              alert( 'TWiki Sheet Error: Failed to concurent update TWiki Sheet' );
            });
          },
          \$concurrentEditRefresh
        );
      }
    })
    .fail(function() {
      alert( 'TWiki Sheet Error: Failed to initialize TWiki Sheet' );
    });
  }
  \$(document).ready(function() {
    \$('.twSheetEditButton').click(function(e) {
      \$(this).parent().hide();
      \$(this).parent().parent().find('.twSheetEdit').show();
      var n = \$(this).attr('data-table');
      var webTopic = \$(this).attr('data-topic');
      if( twSheets[webTopic][n].mode === 'toggle' ) {
        twSheetSetReadOnly( webTopic, n, 0 );
      }
    });
    \$('.twSheetDoneButton').click(function(e) {
      \$(this).parent().hide();
      \$(this).parent().parent().find('.twSheetView').show();
      var n = \$(this).attr('data-table');
      var webTopic = \$(this).attr('data-topic');
      var mode = twSheets[webTopic][n].mode;
      if( mode === 'toggle' ) {
        twSheetSetReadOnly( webTopic, n, 1 );
      } else if( mode === 'classic' && \$authenticated ) {
        var jqxhr = \$.ajax({
          url: '$restGetUrl',
          method: 'GET',
          data: {
            action: 'getRenderedTable',
            webTopic: webTopic,
            tableNumber: n
          },
          dataType: 'json'
        })
        .done(function( result ) {
          $c console.log( '- getRenderedTable return: ' + JSON.stringify( result, null, ' ') );
          if( result && !result.error ) {
            var tableDiv = '#twSheetTable' + n;
            \$(tableDiv).html(result.html);
          }
        })
        .fail(function() {
          alert( 'TWiki Sheet Error: Failed to refresh TWiki table' );
        });
      }
    });
  });
</script>
<style>
.twSheetEditButton, .twSheetDoneButton {
  padding: 1px 5px;
  font-weight: normal;
  font-size: 15px;
  line-height: 16px;
  vertical-align: text-bottom;
}
.twSheetView {
}
.twSheetEdit {
}
</style>
HERE

our $htmlModeEdit = <<"HERE";
<div class="twSheetOuter">
<div id="\$twSheetID" class="twSheetEdit"></div>
</div>
HERE

our $htmlModeToggle = <<"HERE";
<div class="twSheetOuter">
<div class="twSheetView"\$toggleView>
<button class="twikiButton twSheetEditButton" data-topic="\$webTopic" data-table="\$n">\%ICON{edittable}\% Edit</button>
</div>
<div class="twSheetEdit"\$toggleEdit>
<button class="twikiButton twSheetDoneButton" data-topic="\$webTopic" data-table="\$n">\%ICON{led-cup-gray-close}\% Done</button>
</div>
<div id="\$twSheetID" class="twSheetEdit"></div>
</div>
HERE

our $htmlModeClassic = <<"HERE";
<div class="twSheetOuter">
<div class="twSheetView">
<button class="twikiButton twSheetEditButton" data-topic="\$webTopic" data-table="\$n">\%ICON{edittable}\% Edit</button>
<div id="twSheetTable\$n">
\$htmlTable
</div>
</div>
<div class="twSheetEdit" style="display: none;">
<button class="twikiButton twSheetDoneButton" data-topic="\$webTopic" data-table="\$n">\%ICON{led-cup-gray-close}\% Done</button>
<div id="\$twSheetID"></div>
</div>
</div>
HERE

our $htmlJavaScript = <<"HERE";
<script type="text/javascript">
\$(document).ready(function() {\$addWebTopic
  \$thisTwSheet = {};
  \$thisTwSheet.data = \$tableObject;
  var container = \$( '#\$twSheetID' );
  container.handsontable({
    rowHeaders: true,
    colHeaders: true,
    contextMenu: true,
    manualColumnResize: true,
    \$sheetOptions
    data: \$thisTwSheet.data,
    afterChange: function( changes, source ) {
      if( changes && source && source !== 'loadData' ) {
        var clone = changes.slice(0);
        clone.unshift( 'change' )
        twSheetAfterChange( '\$webTopic', \$n, clone );
      }
    },
    afterCreateRow: function( index, amount ) {
      twSheetAfterChange( '\$webTopic', \$n, [ 'createRow', index, amount] );
    },
    afterRemoveRow: function( index, amount ) {
      twSheetAfterChange( '\$webTopic', \$n, [ 'removeRow', index, amount] );
    },
    afterCreateCol: function( index, amount ) {
      // workaround for bug
      if( typeof index == 'undefined' ) {
        index = \$thisTwSheet.data[0].length - 1;
      }
      twSheetAfterChange( '\$webTopic', \$n, [ 'createCol', index, amount] );
    },
    afterRemoveCol: function( index, amount ) {
      twSheetAfterChange( '\$webTopic', \$n, [ 'removeCol', index, amount] );
    }
  });
  \$thisTwSheet.hotInstance = container.handsontable( 'getInstance' );
  \$thisTwSheet.changesQueue = [];
  \$thisTwSheet.changesTimer = null;
  \$thisTwSheet.save = \$save;
  \$thisTwSheet.readIndex = 0;
  \$thisTwSheet.mode = '\$mode';
  \$thisTwSheet.concurrent = \$concurrent;\$toggleJS
  twSheetInitTable( '\$webTopic', \$n );
});
</script>
HERE

# =========================
sub new {
    my ( $class, $baseWebTopic ) = @_;

    my $concurrentEdit        = $TWiki::cfg{Plugins}{TWikiSheetPlugin}{ConcurrentEdit} || 0;
    my $concurrentEditRefresh = $TWiki::cfg{Plugins}{TWikiSheetPlugin}{ConcurrentEditRefresh} || 10;
    my $this = {
          mode                  => $TWiki::cfg{Plugins}{TWikiSheetPlugin}{Mode} || 'toggle',
          concurrentEdit        => int($concurrentEdit),
          concurrentEditRefresh => int($concurrentEditRefresh) * 1000,
          workDir               => TWiki::Func::getWorkArea( 'TWikiSheetPlugin' ),
          tableCount            => {}
        };

    bless( $this, $class );
    _writeDebug( "new() - constructor" );

    my $authenticated = TWiki::Func::getContext()->{authenticated} ? 1 : 0;
    my $html = $htmlHead;
    $html =~ s/\$authenticated/$authenticated/g;
    $html =~ s/\$concurrentEditRefresh/$this->{concurrentEditRefresh}/go;
    TWiki::Func::addToHEAD( 'TWIKISHEETPLUGIN', $html );

    return $this;
}

# =========================
sub protectVariables {
    # do not uncomment, use $_[0], $_[1]... instead
    ### my ( $text, $topic, $web, $meta ) = @_;
    my $this = shift;
    my $webTopic = "$_[2].$_[1]";
    _writeDebug( "protectVariables( $webTopic )");
    $_[0] =~ s/(\%TWIKISHEET\{.*?}\%)(([\n\r]+ *\|[^\n\r]+)*)/$this->_protectVariablesInTable( $1, $2 )/ges;
}

# =========================
sub processText {
    # do not uncomment, use $_[0], $_[1]... instead
    ### my ( $text, $topic, $web, $included, $meta ) = @_;
    my $this = shift;
    my $webTopic = "$_[2].$_[1]";
    _writeDebug( "processText( $webTopic )" );
    $_[0] =~ s/\%TWIKISHEET\{(.*?)}\%(([\n\r]+ *\|[^\n\r]+)*)/$this->_processTable( $1, $2, $webTopic )/ges;
}

# =========================
sub restGetTable {
    my( $this, $query ) = @_;
    require JSON;
    my $action = $query->param( 'action' );
    my $webTopic = $query->param( 'webTopic' );
    my $tn = $query->param( 'tableNumber' );
    my $index = $query->param( 'index' ) || 0;

    _writeDebug( "restGetTable( $action, $webTopic, table: $tn, index: $index )" );

    if( $action eq 'getReadIndex' ) {
        $this->_loadTableChanges( $webTopic, $tn, \$index );
        return '{ "error": 0, "index": ' . $index . ' }';
    } elsif( $action eq 'getChanges' ) {
        my @changes = $this->_loadTableChanges( $webTopic, $tn, \$index );
        return '{ "error": 0, "changes": [' . join( ', ', @changes ) . '], "index": ' . $index . ' }';
    } elsif( $action eq 'getRenderedTable' ) {
        my ( $html, $error )  = $this->_getRenderedTable( $webTopic, $tn );
        return JSON::encode_json( { error => $error, html => $html } );
    }

    my $result = '{ error: 1, message: "Unsupported action $action" }';
    return $result;
}

# =========================
sub restSaveTable {
    my( $this, $query ) = @_;

    require JSON;
    my $action = $query->param( 'action' );
    my $webTopic = $query->param( 'webTopic' );
    my $tn = $query->param( 'tableNumber' );
    my $changes = JSON::decode_json( $query->param( 'changes' ) );

    _writeDebug( "restSaveTable( $action, $webTopic, table: $tn, changes: ".$query->param( 'changes' )." )" );

    if( $action ne 'update' ) {
        my $message = "Nothing to do";
        return '{ "error": 0, "message": "' . $message . '" }';
    }

    my $wikiName = TWiki::Func::getWikiName();
    unless( $wikiName ) {
        my $message = "Error: You must be logged in to update content";
        return '{ "error": 2, "message": "' . $message . '" }';
    }
    my( $web, $topic ) = TWiki::Func::normalizeWebTopicName( '', $webTopic );

    my $lockFile  = $this->_getFileName( $webTopic, 'update', 'lock' );
    my $lockHandle = undef;
    if( $canFlock ) {
        open( $lockHandle, ">$lockFile") || die "Cannot create lock $lockFile - $!\n";
        flock( $lockHandle, LOCK_EX );  # wait for exclusive rights
    }
    my( $topicMeta, $topicText ) = TWiki::Func::readTopic( $web, $topic );
    unless( TWiki::Func::checkAccessPermission('CHANGE', $wikiName, $topicText, $topic, $web, $topicMeta ) ) {
        my $message = "Error: You do not have permission to update topic $topic";
        return '{ "error": 3, "message": "' . $message . '" }';
    }
    my $n = 0;
    my $changed = 0;
    $topicText =~ s/(\%TWIKISHEET\{.*?}\%)(([\n\r]+ *\|[^\n\r]+)*)/$this->_updateTable( $1, $2, $webTopic, $tn, $n++, $changes, \$changed )/ges;
    #_writeDebug( "=========\n$topicText\n========= ($changed)" );
    if( $changed ) {
        TWiki::Func::saveTopic( $web, $topic, $topicMeta, $topicText );
    }
    if( $canFlock ) {
        flock( $lockHandle, LOCK_UN );
        close( $lockHandle );
    }
    my $message = "Table update OK";
    unless( $changed ) {
        $message = "Table update ignored";
    }
    my $result = '{ "error": 0, "message": "' . $message . '" }';
    return $result;
}

# =========================
sub _protectVariablesInTable {
    my( $this, $var, $table ) = @_;
    my %params = TWiki::Func::extractParameters( $args );
    $table =~ s/(\%)([A-Z])/$1$vesc$2/gs;
    return "$var$table";
}

# =========================
sub _processTable {
    my( $this, $args, $table, $webTopic ) = @_;
    my %params = TWiki::Func::extractParameters( $args );
    my $save = TWiki::Func::isTrue( $params{save}, 1 );
    my $mode = $params{mode} || $this->{mode};
    my $concurrent = TWiki::Func::isTrue( $params{concurrent}, $this->{concurrentEdit} );
    my $addWebTopic = '';
    unless( defined $this->{tableCount}{$webTopic} ) {
        $this->{tableCount}{$webTopic} = -1;
        $addWebTopic = "\n  twSheets['$webTopic'] = [];";
    }
    my $n = $this->{tableCount}{$webTopic} + 1;
    $this->{tableCount}{$webTopic} = $n;
    my $toggleJS = '';
    my $toggleView = ' style="display: none;"';
    my $toggleEdit = '';
    if( $mode =~ /^toggle/ && $mode !~ /^toggle-(on|edit)$/ ) {
        $toggleJS = "\n  twSheetSetReadOnly( '$webTopic', $n, 1 );";
        $toggleView = '';
        $toggleEdit = ' style="display: none;"';
    }
    $mode =~ s/\-.*//;
    _writeDebug( "_prepareTable( $webTopic, table $n, save $save, mode $mode )" );

    # collect Handsontable options
    my $sheetOptions = 'formulas: true,';
    foreach my $k ( keys %params ) {
        next if $k =~ /^(_.*|mode|save)$/;
        my $v = $params{$k};
        $sheetOptions .= "\n    $k: $v,";
    }

    # extract table cells and create JavaScript table object
    my @tableRows = $this->_parseTable( $table );
    my $tableObject = '[';
    foreach my $cellsRef ( @tableRows ) {
        $tableObject .= '   [' . join( ', ', @$cellsRef ) . "],\n";
    }
    $tableObject =~ s/,$//s;
    $tableObject .= '  ]';
    _writeDebug( "table data: $tableObject" );

    # create HTML with div for Handsontable
    my $twSheetID = "twSheetContainer$webTopic$n";
    $twSheetID =~ s/[^a-zA-Z0-9]//g;
    my $text = '';
    if( $mode eq 'edit' ) {
        $text = $htmlModeEdit;
    } elsif( $mode eq 'toggle' ) {
        $text = $htmlModeToggle;
    } else { # 'classic' mode
        $table =~ s/^[\n\r]+//s;
        $table =~ s/$vesc//gs;
        $text = $htmlModeClassic;
        $text =~ s/\$htmlTable/$table/go;
    }
    $text =~ s/\$toggleView/$toggleView/go;
    $text =~ s/\$toggleEdit/$toggleEdit/go;

    # add JavaScript with Handsontable
    my $js = $htmlJavaScript;
    $js =~ s/\$addWebTopic/$addWebTopic/go;
    $js =~ s/\$webTopic/$webTopic/go;
    $js =~ s/\$save/$save/go;
    $js =~ s/\$mode/$mode/go;
    $js =~ s/\$concurrent/$concurrent/go;
    $js =~ s/\$sheetOptions/$sheetOptions/go;
    $js =~ s/\$tableObject/$tableObject/go;
    $js =~ s/\$thisTwSheet/twSheets['$webTopic'][$n]/go;
    $js =~ s/\$toggleJS/$toggleJS/go;
    $text .= $js;
    $text =~ s/\$twSheetID/$twSheetID/go;
    $text =~ s/\$webTopic/$webTopic/go;
    $text =~ s/\$n/$n/go;
    return $text;
}

# =========================
sub _updateTable {
    my( $this, $twikiSheetVar, $tableText, $webTopic, $tableNr, $n, $changesSet, $changedRef ) = @_;

    # - $twikiSheetVar: TWIKISHEET variable with parameters, such as "%TWIKISHEET{ save="0" }%".
    # - $tableText: TWiki table text that follows the TWIKISHEET variable.
    # - $tableNr: Desired TWIKISHEET table number on topic.
    # - $n: Actual TWIKISHEET table number on topic; action is only taken if $n == $tableNr.
    # - $changesSet: Reference to array of changes. Each change is an array where the first element indicates
    #   the unique ID of a sheet (composed of the WikiName of the user, a dash, and a random 4 digit number),
    #   followeed by the type of change, followed by elements that depend on the type of change. Example
    #   $changesSet with explanation:
    #   [ [ "JaneSmith-1234", "change", [4,5,"old","x"], [4,6,"","y"]], # cell changes, row 4, column 5 & 6, new values "x" and "y"
    #     [ "JaneSmith-1234", "createCol", 6, 1],                       # insert a new column at column 6
    #     [ "JaneSmith-1234", "removeCol", 6, 2],                       # delete columns 6 and 7
    #     [ "JaneSmith-1234", "createRow", 3, 1],                       # insert a new row at row 3
    #     [ "JaneSmith-1234", "removeRow", 3, 2]                        # delete rows 4 and 5
    #   ]
    # - $changedRef: Reference to changed flag; set to 1 if TWiki Sheet has changes, e.g. topic needs to be saved

    unless( $tableNr == $n ) {
        return "$twikiSheetVar$tableText";
    }

    if( $twikiSheetVar =~ /\bsave=["'](0|off|no|false)["']/ ) {
        # save="0" flag, so don't save
        _writeDebug( "_updateTable( $twikiSheetVar, $tableNr, $n ) - save cancelled due to save=\"0\" parameter" );
        return "$twikiSheetVar$tableText";
    }

    _writeDebug( "_updateTable( $twikiSheetVar, $tableNr, $n )" );
    my $needsSave = 0;
    my @tableRows = $this->_parseTable( $tableText, 1 );
    my @saveChanges = ();
    foreach my $changes ( @$changesSet ) {
      my $user = shift( @$changes );
      my $action = shift( @$changes );
      if( $action eq 'change' ) {
          foreach my $ch ( @$changes ) {
              my $row = $$ch[0];
              my $col = $$ch[1];
              my $old = $$ch[2] || '';
              my $new = $$ch[3];
              _writeDebug( " - save action $action, row $row, col $col, \"$new\"" );
              if( $tableRows[$row][$col] ne $new ) {
                  $tableRows[$row][$col] = $new;
                  $needsSave = 1;
              }
              push( @saveChanges, JSON::encode_json( [ $user, $action, int($row), int($col), $old, $new ] ) );
          }

      } elsif( $action eq 'createRow' ) {
          $needsSave = 1;
          my $row = $$changes[0];
          my $n = $$changes[1];
          _writeDebug( " - save action $action, row $row, n $n" );
          my $nCol = scalar @{$tableRows[0]};
          my @emptyCells = ();
          for( my $i = 0; $i < $nCol; $i++ ) {
              push( @emptyCells, '' );
          }
          for( my $i = 0; $i < $n; $i++ ) {
              splice( @tableRows, $row, 0, \@emptyCells );
          }
          push( @saveChanges, JSON::encode_json( [ $user, $action, int($row), int($n) ] ) );

      } elsif( $action eq 'removeRow' ) {
          $needsSave = 1;
          my $row = $$changes[0];
          my $n = $$changes[1];
          _writeDebug( " - save action $action, row $row, n $n" );
          splice( @tableRows, $row, $n );
          push( @saveChanges, JSON::encode_json( [ $user, $action, int($row), int($n) ] ) );

      } elsif( $action eq 'createCol' ) {
          $needsSave = 1;
          my $col = $$changes[0];
          my $n = $$changes[1];
          my $nRow = scalar @tableRows;
          _writeDebug( " - save action $action, col $col, n $n" );
          for( my $r = 0; $r < $nRow; $r++ ) {
              for( my $c = $col; $c < $col + $n; $c++ ) {
                  splice( @{$tableRows[$r]}, $c, 0, '' );
              }
          }
          push( @saveChanges, JSON::encode_json( [ $user, $action, int($col), int($n) ] ) );

      } elsif( $action eq 'removeCol' ) {
          $needsSave = 1;
          my $col = $$changes[0];
          my $n = $$changes[1];
          my $nRow = scalar @tableRows;
          _writeDebug( " - save action $action, col $col, n $n" );
          for( my $r = 0; $r < $nRow; $r++ ) {
              splice( @{$tableRows[$r]}, $col, $n );
          }
          push( @saveChanges, JSON::encode_json( [ $user, $action, int($col), int($n) ] ) );
      }
    }

    $this->_saveTableChanges( $webTopic, $tableNr, \@saveChanges );

    if( $needsSave ) {
        $$changedRef = 1;
        _writeDebug( " - old table:\n===== OLD =====$tableText\n===============" );
        my $text = '';
        foreach my $row (@tableRows) {
            $text .= "\n|";
            foreach my $cell (@{$row}) {
                $cell = '' unless( defined $cell );
                foreach my $key ( keys %$jsonToTml ) {
                    $cell =~ s/$key/$jsonToTml->{$key}/gs;
                }
                $text .= " $cell |";
            }
        }
        _writeDebug( " - new table:\n===== NEW =====$text\n===============" );
        return "$twikiSheetVar$text";
    } else {
        _writeDebug( " - no change in table, save not needed" );
        return "$twikiSheetVar$tableText";
    }
}

# =========================
sub _parseTable {
    my( $this, $text, $noJson ) = @_;
    # extract table cells
    $text =~ s/^[\n\r]+//s;
    my $maxCells = 0;
    my @tableRows = ();
    foreach my $line ( split( /[\n\r]+/, $text ) ) {
        next unless $line;
        $line =~ s/^ *\|//;
        $line =~ s/\| *$//;
        foreach my $key ( keys %$tmlToJson ) {
            $line =~ s/$key/$tmlToJson->{$key}/gs;
        }
        unless( $noJson ) {
          $line =~ s/$vesc/<nop>/g;
          $line =~ s/"/\\"/g;
        }
        my @cells = map {
                      s/^ *//;
                      s/ *$//;
                      s/$vbar/\|/g;
                      unless( $noJson || /^[0-9]+$/ ) {
                        $_ = "\"$_\""
                      }
                      $_
                    }
                    split(/\|/, $line);
        if( scalar @cells > $maxCells ) {
            $maxCells = scalar @cells;
        }
        push( @tableRows, \@cells );
    }
    foreach my $cellsRef ( @tableRows ) {
        # make sure all rows have the same number of cells
        my $empty = $noJson ? '' : '""';
        while( scalar @$cellsRef < $maxCells ) {
            push( @$cellsRef, $empty );
        }
    }
    return @tableRows;
}

# =========================
sub _getRenderedTable {
    my ( $this, $webTopic, $tableNr ) = @_;
    my( $web, $topic ) = TWiki::Func::normalizeWebTopicName( '', $webTopic );
    my( $meta, $text ) = TWiki::Func::readTopic( $web, $topic );
    my $wikiName = TWiki::Func::getWikiName();
    unless( TWiki::Func::checkAccessPermission('VIEW', $wikiName, $text, $topic, $web, $tmeta ) ) {
        my $message = "Error: You do not have permission to view topic $topic";
        return( '', $message );
    }
    my $n = 0;
    $text =~ s/(\%TWIKISHEET\{.*?}\%)(([\n\r]+ *\|[^\n\r]+)*)/$this->_markTable( $1, $2, $webTopic, $tableNr, $n++ )/ges;
    $text = TWiki::Func::expandCommonVariables( $text, $topic, $web, $meta );
    my $html = TWiki::Func::renderText( $text, $web );
    $html =~ s/^.*?$tableMarker//s;
    $html =~ s/$tableMarker.*$//s;
    return( $html, '' );
}

# =========================
sub _markTable {
    my( $this, $twikiSheetVar, $tableText, $webTopic, $tableNr, $n ) = @_;
    unless( $tableNr == $n ) {
        return "$tableText";
    }
    return "$tableMarker$tableText\n$tableMarker";
}

# =========================
sub _loadTableChanges {
    my ( $this, $webTopic, $tableNr, $indexRef ) = @_;

    my $changesFile = $this->_getFileName( $webTopic, $tableNr, 'txt' );
    my $lockFile  = $this->_getFileName( $webTopic, $tableNr, 'lock' );
    my $lockHandle = undef;
    if( $canFlock ) {
        open( $lockHandle, ">$lockFile") || die "Cannot create lock $lockFile - $!\n";
        flock( $lockHandle, LOCK_SH );  # wait for shared rights
    }
    my $text = '';
    if( open( FILE, "<$changesFile" ) )  {
        local $/ = undef; # set to read to EOF
        $text = <FILE>;
        close( FILE );
    }
    $text = '' unless $text; # no undefined
    $text =~ /^(.*)$/gs; # untaint, it's safe
    $text = $1;
    if( $canFlock ) {
        flock( $lockHandle, LOCK_UN );
        close( $lockHandle );
    }
    my @changes = split( /[\n\r]/, $text );
    my $size = scalar @changes;
    if( $$indexRef ) {
      splice( @changes, 0, $$indexRef );
    }
    $$indexRef = $size;
    _writeDebug( "_loadTableChanges( $webTopic, table $tableNr, last line " . $changes[$#changes] . " )" );
    return @changes;
}

# =========================
sub _saveTableChanges {
    my ( $this, $webTopic, $tableNr, $changes ) = @_;

    _writeDebug( "_saveTableChanges( $webTopic, table $tableNr, last line " . $$changes[$#$changes] . " )" );
    return unless scalar @$changes;
    my $changesFile = $this->_getFileName( $webTopic, $tableNr, 'txt' );
    my $lockFile  = $this->_getFileName( $webTopic, $tableNr, 'lock' );
    my $lockHandle = undef;
    if( $canFlock ) {
        open( $lockHandle, ">$lockFile") || die "Cannot create lock $lockFile - $!\n";
        flock( $lockHandle, LOCK_EX );  # wait for exclusive rights
    }
    unless( open( FILE, ">>$changesFile" ) )  {
        if( $canFlock ) {
            flock( $lockHandle, LOCK_UN );
            close( $lockHandle );
        }
        die "Can't create file $changesFile - $!\n";
    }
    print FILE join("\n", @$changes ) . "\n";
    close( FILE);
    if( $canFlock ) {
        flock( $lockHandle, LOCK_UN );
        close( $lockHandle );
    }
}

# =========================
sub _getFileName {
    my ( $this, $webTopic, $tableNr, $ext ) = @_;
    $webTopic =~ s/[^a-zA-Z0-9\-\.]/_/go;
    $webTopic =~ s/_+/_/go;
    my $name = $this->{workDir} . '/tws.' . $webTopic . '_' . $tableNr . '.' . $ext;
    $name =~ /^(.*)$/gs; # untaint, it's safe
    $name = $1;
    return $name;
}

# =========================
sub _writeDebug
{
    my ( $msg ) = @_;
    return unless( $debug );
    TWiki::Func::writeDebug( "- TWikiSheetPlugin::Core::$msg" );
}

# =========================
sub _writeError
{
    my ( $msg ) = @_;
    print STDERR "ERROR TWiki TWikiSheetPlugin::Core::$msg\n";
}

# =========================
1;
