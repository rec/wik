# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2011-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
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
# For licensing info read LICENSE file in the TWiki root.

package TWiki::Plugins::BackupRestorePlugin::Core;

use strict;

use File::Copy;
use TWiki::Plugins::BackupRestorePlugin::CaptureOutput qw( capture_exec capture_exec_combined );

my @apacheConfLocations = (
    '/etc/httpd/conf.d',             # RHEL / Fedora / CentOS
    '/etc/apache2/conf.d/',          # Debian / Ubuntu / openSUSE
    '/usr/local/apache/conf.d',      # Cygwin
    '/usr/local/apache/conf/conf.d',
    '/usr/local/apache2/conf.d',
    '/usr/local/httpd/conf.d',
  );

my $checkStatusJS = << 'ENDJS';
<!--<pre>-->
<script type="text/javascript">
function ajaxStatusCheck( urlStr, queryStr ) {
  var request = false;
  var self = this;
  if (window.XMLHttpRequest) {
    self.request = new XMLHttpRequest();
  } else if (window.ActiveXObject) {
    self.request = new ActiveXObject("Microsoft.XMLHTTP");
  }
  self.request.open( "POST", urlStr, true );
  self.request.setRequestHeader( "Content-Type", "application/x-www-form-urlencoded" );
  self.request.onreadystatechange = function() {
    if (self.request.readyState == 4) {
      if( self.request.responseText.search( "backup_status: 0" ) >= 0 ) {
          var url = '%SCRIPTURL%/view%SCRIPTSUFFIX%/%WEB%/%TOPIC%';
          var startPos = self.request.responseText.search( /std_err_start: /m );
          var endPos   = self.request.responseText.search( /std_err_end/m );
          if( startPos >= 0 && endPos >= 0 ) {
              var err = self.request.responseText.substring( startPos + 15, endPos );
              url = url + '?std_err=' + escape( err );
          }
          window.location = url;
      } else {
          checkStatusWithDelay();
      }
    }
  };
  self.request.send( queryStr );
};
function checkStatusWithDelay( ) {
  setTimeout(
    "ajaxStatusCheck( '%SCRIPTURLPATH%/backuprestore%SCRIPTSUFFIX%', 'action=status' )",
    5000
  );
};
checkStatusWithDelay();
</script>
<!--</pre>-->
ENDJS

# Note: To remain compatible with older TWiki releases, do not use any TWiki internal
# modules except LocalSite.cfg, and that file is optional too.

#==================================================================
sub new {
    my ( $class, $this ) = @_;

    $this->{Debug}        = $TWiki::cfg{Plugins}{BackupRestorePlugin}{Debug} || 0;
    $this->{KeepNumBUs}   = $TWiki::cfg{Plugins}{BackupRestorePlugin}{KeepNumberOfBackups} || '7';
    my $dir               = $TWiki::cfg{Plugins}{BackupRestorePlugin}{BackupDir} || '/tmp';
    $this->{BackupDir}    = _untaintChecked( $dir );
    $dir                  = $TWiki::cfg{Plugins}{BackupRestorePlugin}{TempDir} || '/tmp';
    $this->{TempDir}      = _untaintChecked( $dir );
    $dir                  = $TWiki::cfg{Plugins}{BackupRestorePlugin}{createZipCmd} || 'zip -r';
    $this->{createZipCmd} = _untaintChecked( $dir );
    $dir                  = $TWiki::cfg{Plugins}{BackupRestorePlugin}{listZipCmd} || 'unzip -l';
    $this->{listZipCmd}   = _untaintChecked( $dir );
    $dir                  = $TWiki::cfg{Plugins}{BackupRestorePlugin}{unZipCmd} || 'unzip -o';
    $this->{unZipCmd}     = _untaintChecked( $dir );

    bless( $this, $class );

    $this->_writeDebug( "constructor" );

    $this->{Location} = $this->_gatherLocation();
    $this->{DaemonDir} = $this->{TempDir} . '/TWiki_BackupRestorePlugin_Daemon';
    $this->_clearError();

    return $this;
}

#==================================================================
# HIGH-LEVEL BACKUP/RESTORE METHODS
#==================================================================

#==================================================================
# Callback of registerTagHandler
#==================================================================
sub BACKUPRESTORE {
    my( $this, $params ) = @_;

    my $action = $params->{action} || '';
    $this->_clearError();
    # script calling this script might pass an error message to display
    $this->_setError( $params->{std_err} ) if( $params->{std_err} );
    $this->_writeDebug( "BACKUPRESTORE action=$action" );

    my $accessOK = 0;
    if( $this->{ScriptType} eq 'cli' ) {
        $this->_setError( 'NOTE: The backup and restore console is only available in CGI context' );
    } elsif( exists( &TWiki::Func::isAnAdmin ) && exists( &TWiki::Func::getCanonicalUserID ) ) {
        $accessOK = TWiki::Func::isAnAdmin( TWiki::Func::getCanonicalUserID() );
    } else {
        $accessOK = 1;
        $this->_setError( 'WARNING: This is an older TWiki version, access to the backup and restore '
                        . 'console __is not resticted__ to the TWiki admin group. Everybody can create '
                        . 'and download backups! Disable the BackupRestorePlugin after use!' );
    }

    my $text = '';
    if( $accessOK ) {
        if( $action eq 'backup_detail' ) {
            $text .= $this->_showBackupDetail( $params );
        } elsif( $action eq 'status' ) {
            $text .= $this->_showBackupStatus( $params );
        } elsif( $action eq 'create_backup' ) {
            $this->_startBackup( $params );
            $text .= $this->_showBackupSummary( $params );
        } elsif( $action eq 'restore_backup' ) {
            $this->_startRestore( $params );
            $text .= $this->_showBackupSummary( $params );
        } elsif( $action eq 'cancel_backup' ) {
            $this->_cancelBackup( $params );
            $text .= $this->_showBackupSummary( $params );
        } elsif( $action eq 'delete_backup' ) {
            $this->_deleteBackup( $params );
            $text .= $this->_showBackupSummary( $params );
        } elsif( $action eq 'debug' ) {
            $text .= $this->_debugBackup( $params );
        } else {
            $text .= $this->_showBackupSummary( $params );
        }

    } elsif( $this->{ScriptType} eq 'cli' ) {
        # error already set
    } else {
        $this->_setError( 'NOTE: Only members of the %USERSWEB%.TWikiAdminGroup can see the backup & restore console.' );
    }

    $text = $this->_renderError() . $text;
    return $text;
}

#==================================================================
# Main entry point of backuprestore utility (cgi & cli)
#==================================================================
sub backuprestore {
    my( $this, $params ) = @_;

    my $action = $params->{action} || 'usage';

    $this->_writeDebug( "backuprestore, action=$action" );
    my $text = '';
    if( $action eq 'status' ) {
        print "Content-type: text/html\n\n" if( $this->{ScriptType} eq 'cgi' );
        $text .= $this->_showBackupStatus( $params );
    } elsif( $action eq 'debug' ) {
        print "Content-type: text/html\n\n" if( $this->{ScriptType} eq 'cgi' );
        $text .= $this->_debugBackup( $params );
    } elsif( $action eq 'create_backup' ) {
        print "Content-type: text/html\n\n" if( $this->{ScriptType} eq 'cgi' );
        $text .= $this->_createBackup( $params );
    } elsif( $action eq 'restore_backup' ) {
        print "Content-type: text/html\n\n" if( $this->{ScriptType} eq 'cgi' );
        $text .= $this->_restoreFromBackup( $params );
    } elsif( $action eq 'download_backup' ) {
        # content type is printed in _downloadBackup
        $text .= $this->_downloadBackup( $params );
    } else {
        print "Content-type: text/html\n\n" if( $this->{ScriptType} eq 'cgi' );
        $text .= $this->_showUsage( $params );
    }
    $text = $this->_renderError() . $text;
    return $text;
}

#==================================================================
sub _showUsage {
    my( $this, $params ) = @_;

    my $text = '';
    $text .= "<pre>\n" if( $this->{ScriptType} eq 'cgi' );
    $text .= "Backup and restore utility of TWiki's BackupRestorePlugin.\n";
    $text .= "Copyright 2011-2018 Peter[at]Thoeny.org and TWiki Contributors.\n";
    $text .= "Plugin home and documentation:\n";
    $text .= "  http://twiki.org/cgi-bin/view/Plugins/BackupRestorePlugin\n";
    $text .= "Usage:\n";
    if( $this->{ScriptType} ne 'cgi' ) {
        $text .= "  ./backuprestore status                   # show backup status\n";
        $text .= "  ./backuprestore create_backup            # create new backup\n";
        $text .= "  ./backuprestore download_backup name     # download a backup file\n";
    } else {
        $text .= "  /backuprestore?action=status             # show backup status\n";
    }
    $text .= "</pre>\n" if( $this->{ScriptType} eq 'cgi' );
    return $text;
}

#==================================================================
sub _showBackupStatus {
    my( $this, $params ) = @_;

    my $daemonStatus = $this->_daemonRunning();
    my $fileName = $this->_getBackupName( $daemonStatus );
    my $error = _untaintChecked( _readFile( $this->{DaemonDir} . '/stderr.txt' ) );
    my $text = '';
    $text .= "<pre>\n" if( $this->{ScriptType} eq 'cgi' );
    $text .= "backup_status: $daemonStatus\n";
    $text .= "file_name: $fileName\n";
    $text .= "std_err_start: $error\nstd_err_end\n" if( $error );
    $text .= "</pre>\n" if( $this->{ScriptType} eq 'cgi' ); 
    return $text;
}

#==================================================================
sub _showBackupSummary {
    my( $this, $params ) = @_;

    $this->_writeDebug( '_showBackupSummary' );
    my $text = "";
    my $daemonStatus = $this->_daemonRunning();
    my $fileName = $this->_getBackupName( $daemonStatus );
    if( $daemonStatus ) {
        my $message = $daemonStatus == 1 ? 'Creating backup now' : 'Restoring from backup now';
        $text .= "$checkStatusJS\n";
        $text .= "| *Backup* | *Size* | *Action* |\n";
        $text .= '| <img src="%PUBURLPATH%/%WEB%/BackupRestorePlugin/processing.gif" '
               . 'width="16" height="16" alt="Processing..." /> ' . $fileName
               . '| <img src="%PUBURLPATH%/%WEB%/BackupRestorePlugin/processing-bar.gif" '
               . 'width="92" height="16" alt="Processing..." /> '
               . "| $message, please wait. "
               . '<form action="%SCRIPTURLPATH%/view%SCRIPTSUFFIX%/%WEB%/%TOPIC%">'
               . '<input type="hidden" name="action" value="cancel_backup" />'
               . '<input type="submit" value="Cancel" class="twikiButton" />'
               . '</form> |' . "\n";
    } else {
        $text .= "| *Backup* | *Size* | *Action* |\n";
        $text .= '| <img src="%PUBURLPATH%/%WEB%/BackupRestorePlugin/newtopic.gif" '
               . 'width="16" height="16" alt="New backup" /> ' . $fileName . ' | '
               . '| <form action="%SCRIPTURLPATH%/view%SCRIPTSUFFIX%/%WEB%/%TOPIC%">'
               . '<input type="hidden" name="action" value="create_backup" />'
               . '<input type="submit" value="Create backup now" class="twikiButton" />'
               . '</form> |' . "\n";
    }
    my @backupFiles = $this->_listAllBackups();
    if( scalar @backupFiles ) {
        my $magic = $this->_generateMagic();
        foreach $fileName ( reverse sort @backupFiles ) {
            my $size = -s $this->{BackupDir} . "/$fileName";
            $size =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1,/g;
            $text .= '| <img src="%PUBURLPATH%/%WEB%/BackupRestorePlugin/zip.gif" '
                   . 'width="16" height="16" alt="ZIP" /> [[%SCRIPTURL%/backuprestore%SCRIPTSUFFIX%?'
                   . "action=download_backup;file=$fileName;magic=$magic][$fileName]] "
                   . "|   $size "
                   . '| <form action="%SCRIPTURLPATH%/view%SCRIPTSUFFIX%/%WEB%/%TOPIC%">'
                   . '<input type="hidden" name="action" value="backup_detail" />'
                   . '<input type="hidden" name="file" value="' . $fileName . '" />'
                   . '<input type="submit" value="Details / Restore..." class="twikiButton" />'
                   . '</form> '
                   . '<form action="%SCRIPTURLPATH%/view%SCRIPTSUFFIX%/%WEB%/%TOPIC%">'
                   . '<input type="hidden" name="action" value="delete_backup" />'
                   . '<input type="hidden" name="file" value="' . $fileName . '" />'
                   . '<input type="submit" value="Delete..." class="twikiButton" onClick="return confirm('
                   . "'Are you sure you want to delete $fileName?'" . ');" />'
                   . '</form> |' . "\n";
        }
    } else {
        $text .= "| (no existing backups ) | | |\n";
    }
    return $text;
}

#==================================================================
sub _showBackupDetail {
    my( $this, $params ) = @_;

    my $fileName = _sanitizeFileName( $params->{file} );
    $this->_writeDebug( "_showBackupDetail file=$fileName" );
    my $buDate = $fileName;
    $buDate = '' unless( $buDate =~ s/[^0-9]*(.*?)-([0-9]+)-([0-9]+)\.zip/$1 $2:$3/ );
    my @fileList = $this->_listZip( $fileName );
    return '' unless( -e $this->_getZipFilePath( $fileName ) ); # bail out if file does not exist

    my ( $buVersion ) = map{ s/^.*BackupRestorePlugin\/twiki-version-long-(.*?)\.txt$/$1/; $_ }
        grep{ /BackupRestorePlugin\/twiki-version-long-/ }
        @fileList;
    my ( $buShort ) = map{ s/^.*BackupRestorePlugin\/twiki-version-short-(.*?)\.txt$/$1/; $_ }
        grep{ /BackupRestorePlugin\/twiki-version-short-/ }
        @fileList;
    my @webList = map{ s/^data\/(.*)\/WebPreferences\.txt$/$1/; $_ }
        grep{ /^data\/.*\/WebPreferences\.txt$/ }
        sort
        @fileList;
    my $magic = $this->_generateMagic();
    my ( $twikiVersion, $twikiShort ) = $this->_getTWikiVersion();
    my $buSize = -s $this->{BackupDir} . "/$fileName";
    $buSize =~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1,/g;
    my $upgradeWebChecked = ( $buShort < $twikiShort) ? 'checked="checked" ' : '';
    my $text = << 'ENDCHECK';
<!--<pre>-->
<script language="JavaScript">
function checkAllWebs( theCheck )
{
  for( var i = 0; i < document.restore_webs.length; i++ ) {
    if( document.restore_webs.elements[i].id.search( /^web:/ ) == 0 ) {
      document.restore_webs.elements[i].checked = theCheck;
    }
  }
}
</script>
<!--</pre>-->
ENDCHECK
    $text .= '<form action="%SCRIPTURLPATH%/view%SCRIPTSUFFIX%/%WEB%/%TOPIC%" name="restore_webs" method="post">' . "\n"
        . "| *Details of $fileName:* ||\n"
        . '| Backup file: | [[%SCRIPTURL%/backuprestore%SCRIPTSUFFIX%?'
        . "action=download_backup;file=$fileName;magic=$magic][$fileName]] |\n"
        . "| Backup date: | $buDate \%GRAY\% - local time of server \%ENDCOLOR\% |\n"
        . "| Backup size: | $buSize \%GRAY\% Bytes \%ENDCOLOR\% |\n"
        . "| Backup of: | $buVersion \%GRAY\% - the TWiki version this backup was taken from \%ENDCOLOR\% |\n"
        . "| This TWiki: | $twikiVersion \%GRAY\% - the TWiki version of the current installation \%ENDCOLOR\% |\n"
        . "| *Restore Options:* ||\n"
        . '| | <input type="checkbox" name="overwrite" id="overwrite" checked="checked" /> '
        . '<label for="overwrite"> Overwrite existing pages </label> - %RED% this cannot be undone! %ENDCOLOR% |' . "\n"
        . '| | <input type="checkbox" name="upgradewebs" id="upgradewebs" ' . $upgradeWebChecked . '/> '
        . '<label for="upgradewebs"> Upgrade restored webs with latest system pages (<nop>WebSearch etc.) </label> |' . "\n"
        . '| | <input type="checkbox" name="restoreworkarea" id="restoreworkarea" checked="checked" /> '
        . '<label for="restoreworkarea"> Restore plugin work area </label> |' . "\n";

    # Restore webs list
    $text .= '| *Restore Webs:'
        . ' &nbsp; &nbsp; &nbsp; '
        . '<input type="button" value="Set all webs" onClick="checkAllWebs(true);" class="twikiButton" />'
        . ' &nbsp; &nbsp; '
        . '<input type="button" value="Clear all webs" onClick="checkAllWebs(false);" class="twikiButton" />'
        . "* ||\n";
    my $systemWeb = 'TWiki';
    $systemWeb =  $TWiki::cfg{SystemWebName} if( defined $TWiki::cfg{SystemWebName} );
    foreach my $web ( grep{ /^($systemWeb|_default)$/ } @webList ) {
        my $note = 'do not restore over a different TWiki version!';
        $text .= _renderWebRow( $web, ( $buShort == $twikiShort ), $note );
    }
    foreach my $web ( @webList ) {
        next if( $web =~ /^($systemWeb|_default)$/ );
        $text .= _renderWebRow( $web, 1, '' );
    }
    $text .= "| *Restore Action:* ||\n"
        . '| | <input type="submit" value="Restore from backup..." class="twikiButton" onClick="return confirm('
        . "'Are you sure you want to restore from $fileName?'" . ');" /> |' . "\n"
        . '<input type="hidden" name="action" value="restore_backup" />'
        . '<input type="hidden" name="file" value="' . $fileName . '" />'
        . '</form>';
    return $text;
}
    
#==================================================================
sub _renderWebRow {
    my( $web, $checked, $note ) = @_;
    my $name = "web:$web";
    $name =~ s/\//:/go; #replace '/' sub-web separator with legal ':' char
    my $text = "| | <input type=\"checkbox\" name=\"$name\" id=\"$name\"";
    $text .= ' checked="checked"' if( $checked );
    $text .= " /> <label for=\"$name\">$web</label>";
    if( $note ) {
        $text .= " - \%RED\% $note \%ENDCOLOR\%";
    }
    $text .= " |\n";
    return $text;
}

#==================================================================
sub _debugBackup {
    my( $this, $params ) = @_;

    my $text = "Debug BACKUPRESTORE";
    if($this->{Debug}) {
        $text .= "<br /> " . $this->_testZipMethods();
    } else {
        $text .= ": Sorry, {Plugins}{BackupRestorePlugin}{Debug} must be enabled in configure.\n";
    }
    return $text;
}


#==================================================================
# MID-LEVEL BACKUP/RESTORE METHODS
#==================================================================

#==================================================================
sub _generateMagic {
    my( $this ) = @_;

    # create new magic number, used to protect web-based download of backups
    my $magic = $this->_buildFileName();
    $magic =~ s/\.zip//o;
    $magic .= '-' . sprintf( "%.10u", int( rand( 10000000000 ) ) );

    # read file with magic number array, add new magic number, and truncate array
    $this->_makeDir( $this->{DaemonDir} ) unless( -e $this->{DaemonDir} );
    my @magicArray = split( /\n/, _readFile( $this->{DaemonDir} . '/magic.txt' ) );
    push( @magicArray, $magic );
    my $size = scalar @magicArray;
    if( $size > 32 ) {
        splice( @magicArray, 0, $size - 32 );
    }
    _saveFile( $this->{DaemonDir} . '/magic.txt', join( "\n", @magicArray ) . "\n" );

    $this->_writeDebug( "_generateMagic() => $magic" );

    return $magic;
}

#==================================================================
sub _checkMagic {
    my( $this, $magic ) = @_;

    my @magicArray = grep{ /^$magic$/ }
                     split( /\n/, _readFile( $this->{DaemonDir} . '/magic.txt' ) );
    my $found = scalar @magicArray;
    $this->_writeDebug( "_checkMagic( $magic ) => $found" );

    return $found;
}

#==================================================================
sub _daemonRunning {
    my( $this ) = @_;
    my $pid = _untaintChecked( _readFile( $this->{DaemonDir} . '/pid.txt' ) );
    if( $pid && (kill 0, $pid) ) {
        my $text = _readFile( $this->{DaemonDir} . '/file_name.txt' );
        if( $text =~ m/type: ([0-9])-/s ) {
            # type: 1-backup, type: 2-restore (return only a digit)
            return $1;
        }
        return 1;
    }
    return 0;
}

#==================================================================
sub _getBackupName {
    my( $this, $inProgress ) = @_;
    if( $inProgress ) {
        my $text = _readFile( $this->{DaemonDir} . '/file_name.txt' );
        if( $text =~ m/file_name: ([^\n]+)/ ) {
            return _untaintChecked( $1 );
        }
        $this->_setError( 'ERROR: Can\'t determine backup filename.' );
        return '';
    } else {
        return $this->_buildFileName();
    }
}

#==================================================================
sub _startBackup {
    my( $this, $params ) = @_;

    $this->_writeDebug( "_startBackup()" );
    $this->_makeDir( $this->{DaemonDir} ) unless( -e $this->{DaemonDir} );

    my $daemonType = $this->_daemonRunning();
    if( $daemonType == 1 ) {
        $this->_setError( 'ERROR: Backup is already in progress.' );
    } elsif( $daemonType > 1 ) {
        $this->_setError( 'ERROR: Backup not possible while restore is in progress.' );
    } else {
        my $fileName = $this->_buildFileName();
        my $text = "file_name: " . $fileName . "\n"
                 . "type: 1-backup\n";
        _saveFile( $this->{DaemonDir} . '/file_name.txt', $text );
        # daemon is running as shell script, do not pass env vars that make it look like a cgi
        my $SaveGATEWAY_INTERFACE;
        if( $ENV{GATEWAY_INTERFACE} ) {
            $SaveGATEWAY_INTERFACE = $ENV{GATEWAY_INTERFACE};
            delete $ENV{GATEWAY_INTERFACE};
        }
        my $SaveMOD_PERL; 
        if( $ENV{MOD_PERL} ) {
            $SaveMOD_PERL = $ENV{MOD_PERL};
            delete $ENV{MOD_PERL};
        }
        # build backup daemon command
        my $cmd = $this->{Location}{BinDir} . "/backuprestore create_backup $fileName";
        $this->_writeDebug( "start new daemon: $cmd" );
        require TWiki::Plugins::BackupRestorePlugin::ProcDaemon;
        my $daemon = TWiki::Plugins::BackupRestorePlugin::ProcDaemon->new(
            work_dir     => $this->{Location}{BinDir},
            child_STDOUT => $this->{DaemonDir} . '/stdout.txt',
            child_STDERR => $this->{DaemonDir} . '/stderr.txt',
            pid_file     => $this->{DaemonDir} . '/pid.txt',
            exec_command => $cmd,
        );
        # fork background daemon process
        my $pid = $daemon->Init();
        # restore environment variables
        $ENV{GATEWAY_INTERFACE} = $SaveGATEWAY_INTERFACE if( $SaveGATEWAY_INTERFACE );
        $ENV{MOD_PERL}          = $SaveMOD_PERL if( $SaveMOD_PERL );
    }
}

#==================================================================
sub _startRestore {
    my( $this, $params ) = @_;

    my $fileName = _sanitizeFileName( $params->{file} );
    $this->_writeDebug( "_startRestore file=$fileName" );
    $this->_makeDir( $this->{DaemonDir} ) unless( -e $this->{DaemonDir} );

    unless( -e $this->_getZipFilePath( $fileName ) ) {
        # bail out if file does not exist
        $this->_setError( "ERROR: Backup $fileName does not exist" );
        return;
    }

    my $daemonType = $this->_daemonRunning();
    if( $daemonType == 1 ) {
        $this->_setError( 'ERROR: Restore not possible while backup is in progress.' );
    } elsif( $daemonType > 1 ) {
        $this->_setError( 'ERROR: Restore from backup is already in progress.' );
    } else {
        my $text = "file_name: " . $fileName . "\n"
                 . "type: 2-restore\n";
        for my $key ( sort keys %$params ) {
            next if( $key =~ /^(action|file|_RAW)$/o );
            $text .= "$key: " . $params->{$key} . "\n";
        }
        _saveFile( $this->{DaemonDir} . '/file_name.txt', $text );
        # daemon is running as shell script, do not pass env vars that make it look like a cgi
        my $SaveGATEWAY_INTERFACE;
        if( $ENV{GATEWAY_INTERFACE} ) {
            $SaveGATEWAY_INTERFACE = $ENV{GATEWAY_INTERFACE};
            delete $ENV{GATEWAY_INTERFACE};
        }
        my $SaveMOD_PERL; 
        if( $ENV{MOD_PERL} ) {
            $SaveMOD_PERL = $ENV{MOD_PERL};
            delete $ENV{MOD_PERL};
        }
        # build restore daemon command
        my $cmd = $this->{Location}{BinDir} . "/backuprestore restore_backup $fileName";
        $this->_writeDebug( "start new daemon: $cmd" );
        require TWiki::Plugins::BackupRestorePlugin::ProcDaemon;
        my $daemon = TWiki::Plugins::BackupRestorePlugin::ProcDaemon->new(
            work_dir     => $this->{Location}{BinDir},
            child_STDOUT => $this->{DaemonDir} . '/stdout.txt',
            child_STDERR => $this->{DaemonDir} . '/stderr.txt',
            pid_file     => $this->{DaemonDir} . '/pid.txt',
            exec_command => $cmd,
        );
        # fork background daemon process
        my $pid = $daemon->Init();
        # restore environment variables
        $ENV{GATEWAY_INTERFACE} = $SaveGATEWAY_INTERFACE if( $SaveGATEWAY_INTERFACE );
        $ENV{MOD_PERL}          = $SaveMOD_PERL if( $SaveMOD_PERL );
    }
}

#==================================================================
sub _cancelBackup {
    my( $this, $params ) = @_;

    my $daemonType = $this->_daemonRunning();
    if( $daemonType ) {
        my $pid = _untaintChecked( _readFile( $this->{DaemonDir} . '/pid.txt' ) );
        kill( 6, $pid ) if( $pid ); # send ABORT signal to backuprestore script
        unlink( $this->{DaemonDir} . '/pid.txt' );
        sleep( 10 ); # wait for zip to cleanup before deleting zip file
        if( $daemonType == 1 ) {
            # cleanup backup
            my $text = _readFile( $this->{DaemonDir} . '/file_name.txt' );
            if( $text =~ m/file_name: ([^\n]+)/ ) {
                my $zipFile = _untaintChecked( "$this->{BackupDir}/$1" );
                unlink( $zipFile ) if( -e $zipFile );
            }
        } else {
            # cleanup restore
            my $tmpRestoreDir = $this->{DaemonDir} . '/_tmp_restore';
            File::Path::rmtree( $tmpRestoreDir ) if( -e $tmpRestoreDir );
        }

    } else {
        $this->_setError( 'ERROR: No backup or restore is in progress.' );
    }
}

#==================================================================
sub _createBackup {
    my( $this, $params ) = @_;

    my $name = _sanitizeFileName( $params->{file} );
    $name = $this->_buildFileName() unless( $name );
    $name = _untaintChecked( $name );
    $this->_writeDebug( "_createBackup( $name )" ) if $this->{Debug};

    if( $this->{ScriptType} eq 'cgi' ) {
        $this->_setError( "ERROR: Backup can only be done from the console or from the command line" );
        return '';
    }

    # delete old backups based on $TWiki::cfg{Plugins}{BackupRestorePlugin}{KeepNumberOfBackups}
    if( $this->{KeepNumBUs} > 0 ) {
        my @backupFiles = sort $this->_listAllBackups();
        my $nFiles = scalar @backupFiles;
        if( $nFiles > $this->{KeepNumBUs} ) {
            splice( @backupFiles, $nFiles - $this->{KeepNumBUs} + 1, $nFiles );
            foreach my $fileName ( @backupFiles ) {
                $this->_deleteZip( _untaintChecked( $fileName ) );
            }
        }
    }

    my @exclude = ( '-x', '*.svn/*' );

    # backup data dir
    my( $base, $dir ) = _splitTopDir( $this->{Location}{DataDir} );
    $this->_createZip( $name, $base, $dir, @exclude );

    # backup pub dir
    ( $base, $dir ) = _splitTopDir( $this->{Location}{PubDir} );
    $this->_createZip( $name, $base, $dir, @exclude );

    # backup system configuration files (backed-up later in working dir)
    $dir = $this->{Location}{WorkingDir};
    $this->_makeDir( $dir, 0755 ) unless( -e $dir );
    $dir .= "/work_areas";
    $this->_makeDir( $dir, 0755 ) unless( -e $dir );
    $dir .= "/BackupRestorePlugin";
    File::Path::rmtree( $dir ) if( -e $dir);
    $this->_makeDir( $dir, 0755 ) unless( -e $dir );
    my $file = $this->{Location}{LocalLib};
    $this->_copyFile( $file, $dir ) if( $file && -e $file );
    $file = $this->{Location}{LocalSite};
    $this->_copyFile( $file, $dir ) if( $file && -e $file );
    $file = $this->{Location}{ApacheConf};
    $this->_copyFile( $file, $dir ) if( $file && -e $file );
    my( $version, $short ) = $this->_getTWikiVersion();
    if( $version ) {
        _saveFile( "$dir/twiki-version.txt", "version: $version\nshort: $short\n" );
        _saveFile( "$dir/twiki-version-long-$version.txt", "(version is in file name)\n" );
        _saveFile( "$dir/twiki-version-short-$short.txt", "(version is in file name)\n" );
    }

    # backup working dir
    ( $base, $dir ) = _splitTopDir( $this->{Location}{WorkingDir} );
    push( @exclude, '*/tmp/*', '*/registration_approvals/*' );
    $this->_createZip( $name, $base, $dir, @exclude );
    return '';
}

#==================================================================
sub _restoreFromBackup {
    my( $this, $params ) = @_;

    my $name = _sanitizeFileName( $params->{file} );
    $name = _untaintChecked( $name );
    $this->_writeDebug( "_restoreFromBackup( $name )" ) if $this->{Debug};

    if( $this->{ScriptType} eq 'cgi' ) {
        $this->_setError( "ERROR: Restore from backup can only be done from the console" );
        return '';
    }
    unless( $name ) {
        $this->_setError( "ERROR: Backup filename must be specified" );
        return '';
    }
    my $file = $this->_getZipFilePath( $name );
    unless( -e $file ) {
        $this->_setError( "ERROR: Backup $name does not exist" );
        return '';
    }
    my $zipTimestamp = ( stat( $file ) )[9];

    # get options and list of webs to restore
    my $text = _readFile( $this->{DaemonDir} . '/file_name.txt' );
    if( $text !~ m/type: 2-/s ) {
        $this->_setError( "ERROR: Restore can only be called from the console" );
        return '';
    }
    my $overwrite = 0;
    $overwrite = 1 if( $text =~ /(^|\n)overwrite\: on/m );
    my $upgradeWebs = 0;
    $upgradeWebs = 1 if( $text =~ /(^|\n)upgradewebs\: on/m );
    my $restoreWorkArea = 0;
    $restoreWorkArea = 1 if( $text =~ /(^|\n)restoreworkarea\: on/m );
    my @webs = sort
        map{ s/\:/\//go; $_; }
        map{ /^web\:(.*)\: .*/; $1; }
        grep{ /^web\:.*\: / }
        split( /\n/, $text );

    unless( scalar @webs ) {
        $this->_setError( "NOTE: Nothing to do, no webselected to restore" );
        return '';
    }

    # remove and re-create temp dir for restore
    my $tmpRestoreDir = $this->{DaemonDir} . '/_tmp_restore';
    File::Path::rmtree( $tmpRestoreDir ) if( -e $tmpRestoreDir );
    $this->_makeDir( $tmpRestoreDir ) unless( -e $tmpRestoreDir );
    return '' if( $this->_isError() );

    # unzip into temp dir
    chdir( $tmpRestoreDir );
    $this->_unZip( $name );
    if( $this->_isError() ) {
        File::Path::rmtree( $tmpRestoreDir );
        return '';
    }

    # restore webs
    my @processed = ();
    foreach my $web ( @webs ) {
        $this->_restoreWeb( $web, $tmpRestoreDir, $overwrite, $upgradeWebs, $zipTimestamp );
        last if( $this->_isError() );
        push( @processed, $web );
    }
    if( scalar @processed == 1 ) {
        $this->_setError( "NOTE: The following web of $name has been successfully restored: <nop>"
                        . $processed[0] );
    } elsif( scalar @processed ) {
        $text = join( ', <nop>', @processed );
        $this->_setError( "NOTE: The following webs of $name have been successfully restored: <nop>$text" );
    }

    # restore plugin work aera
    if( $restoreWorkArea ) {
        my ( $base, $dir ) = _splitTopDir( $this->{Location}{WorkingDir} );
        $this->_copyDirRecursively( "$tmpRestoreDir/working", $base, 0775, 0644, $zipTimestamp );
    }

    # cleanup temp area
    File::Path::rmtree( $tmpRestoreDir );
    return '';
}

#==================================================================
sub _restoreWeb {
    my( $this, $web, $baseDir, $overwrite, $upgradeWeb, $zipTimestamp ) = @_;
    $this->_writeDebug( "_restoreWeb( $web )" ) if $this->{Debug};

    my $sourceDir = "$baseDir/data/$web";
    my $destDir   = $this->{Location}{DataDir};
    foreach my $subWeb ( split( /[\/\\]+/, $web ) ) {
        $destDir .= "/$subWeb";
        $this->_makeDir( $destDir, 0755, $zipTimestamp ) unless( -e $destDir );
        return if( $this->_isError() );
    }

    foreach my $topic ( map{ s/\.txt$//; $_; } grep{ /\.txt$/ } _getDirContent( $sourceDir ) ) {
        next if( -e "$destDir/$topic.txt" && !$overwrite );
        $this->_restoreTopic( $web, $topic, $baseDir, $web, $destDir, $zipTimestamp );
        return if( $this->_isError() );
    }

    if( $upgradeWeb ) {
        # base dir is parent of data dir, source web is '_default'
        my( $base, $dir ) = _splitTopDir( $this->{Location}{DataDir} );

        # upgrade old web, overwriting existing topics if overwrite flag set
        my @topics = ( 'WebAtom', 'WebChanges', 'WebIndex', 'WebRss', 'WebSearchAdvanced', 'WebSearch', 'WebTopicList' );
        foreach my $topic ( @topics ) {
            next if( -e "$destDir/$topic.txt" && !$overwrite );
            $this->_restoreTopic( '_default', $topic, $base, $web, $destDir, $zipTimestamp );
            return if( $this->_isError() );
        }

        # upgrade old web, create topics if not exist
        @topics = ( 'WebCreateNewTopic', 'WebTopMenu' );
        foreach my $topic ( @topics ) {
            next if( -e "$destDir/$topic.txt" );
            $this->_restoreTopic( '_default', $topic, $base, $web, $destDir, $zipTimestamp );
            return if( $this->_isError() );
        }
    }
}

#==================================================================
sub _restoreTopic {
    my( $this, $web, $topic, $baseDir, $destWeb, $destDir, $timestamp ) = @_;
    $this->_writeDebug( "_restoreTopic( $web, $topic, $baseDir, $destWeb, $destDir )" ) if $this->{Debug};

    # copy topic
    my $file = "$baseDir/data/$web/$topic.txt";
    my $dest = "$destDir/$topic.txt";
    my $text = _readFile( $file, 1 ); # read topic meta
    if( $text =~ /\%META\:TOPICINFO\{[^\n]* date=\"([0-9]+)\"/ ) {
        $timestamp = $1; # use timestamp of topic meta if found
    }
    unlink( $dest ) if( -e $dest );
    $this->_copyFile( $file, $destDir, 0644, $timestamp );
    return if( $this->_isError() );

    # copy rcs history
    $file .= ',v';
    $dest .= ',v';
    unlink( $dest ) if( -e $dest );
    $this->_copyFile( $file, $destDir, 0444, $timestamp ) if( -e $file );
    return if( $this->_isError() );

    # copy attachments (if any)
    my $attachDir = "$baseDir/pub/$web/$topic";
    if( -e $attachDir ) {
        my $destDir   = $this->{Location}{PubDir};
        foreach my $subWeb ( split( /[\/\\]+/, $destWeb ) ) {
            $destDir .= "/$subWeb";
            $this->_makeDir( $destDir, 0755, $timestamp ) unless( -e $destDir ); 
            return if( $this->_isError() );
        }

        $destDir .= "/$topic";
        File::Path::rmtree( $destDir ) if( -e $destDir );
        $this->_makeDir( $destDir, 0755, $timestamp ) unless( -e $destDir );
        return if( $this->_isError() );

        foreach my $attachment ( _getDirContent( $attachDir ) ) {
            $file = "$attachDir/$attachment";
            if( -f $file ) {
                my $mode = ( $file =~ /,v$/ ) ? 0444 : 0644;
                $this->_copyFile( $file, $destDir, $mode, $timestamp );
                return if( $this->_isError() );
            } elsif( -d $file ) {
                $this->_copyDirRecursively( "$file", $destDir, 0775, 0644, $timestamp );
            }
        }
    }
}

#==================================================================
sub _downloadBackup {
    my( $this, $params ) = @_;

    my $text = '';
    my $name = _sanitizeFileName( $params->{file} );
    $name = _untaintChecked( $name );
    unless( $name ) {
        print "Content-type: text/html\n\n" if( $this->{ScriptType} eq 'cgi' );
        $this->_setError( "ERROR: Backup filename must be specified" );
        return $text;
    }

    my $magic = _sanitizeFileName( $params->{magic}, 1 );
    if( $this->{ScriptType} eq 'cgi' && ! $this->_checkMagic( $magic ) ) {
        print "Content-type: text/html\n\n";
        $this->_setError( "NOTE: Only TWiki administrators can download backups" );
        return $text;
    }

    my $file = $this->_getZipFilePath( $name );
    my $size = -s $file;
    unless( open( ZIPFILE, $file ) ) {
        print "Content-type: text/html\n\n" if( $this->{ScriptType} eq 'cgi' );
        $this->_setError( "ERROR: Backup $name does not exist" );
        return $text;
    }

    # enforce binmode for binary zip file
    binmode( ZIPFILE );
    binmode( STDOUT );

    # if in cgi context, output content-type
    if( $this->{ScriptType} eq 'cgi' ) {
        print "Content-Type: application/zip\n";
        print "Content-Length: $size\n";
        print "Content-Disposition: attachment; filename=$name\n\n";
    }

    # directly print to STDOUT because of potentially big zip file size
    my $buffer;
    while( read( ZIPFILE, $buffer, 8 * 2**10 ) ) {
        print STDOUT $buffer;
    }
    close( ZIPFILE );

    return ''; # empty
}

#==================================================================
sub _deleteBackup {
    my( $this, $params ) = @_;

    my $name = _sanitizeFileName( $params->{file} );
    return $this->_deleteZip( _untaintChecked( $name ) );
}


#==================================================================
# LOW-LEVEL METHODS
#==================================================================

#==================================================================
sub _clearError {
    my( $this ) = @_;
    $this->{error} = '';
}

#==================================================================
sub _setError {
    my( $this, $error ) = @_;
    $this->{error} .=  "$error\n"
}

#==================================================================
sub _isError {
    my( $this ) = @_;
    $this->{error} ? return 1 : return 0;
}   

#==================================================================
sub _renderError {
    my( $this ) = @_;

    my $text = '';
    return $text unless $this->{error};

    if( $this->{ScriptType} eq 'cgi' ) {
        $this->{error} =~ s/\n*$//; # remove trailing newline
        $this->{error} =~ s/\n/<br \/>\n/go if( $this->{error} ); # separate errors with <br />
        $text = '<div style="background-color: #f0f0f4; padding: 10px 20px">'
              . $this->{error}
              . "</div>\n";
    } else {
        print STDERR $this->{error};
    }
    $this->{error} = '';
    return $text;
}

#==================================================================
sub _getTWikiVersion {
    my( $this ) = @_;

    my $version = '';
    my $short = '';
    my $text = _readFile( $this->{Location}{LibDir} . "/TWiki.pm" );
    if( $text =~ m/\$wikiversion *= *['"]([^'"]+)/s ) {
        # older than TWiki-4.0
        $version = 'TWiki-' . $1;
        $version =~ s/ /-/go;
        $short = '1.0' if( $version =~ m/-2001/ );
        $short = '2.0' if( $version =~ m/-2003/ );
        $short = '3.0' if( $version =~ m/-2004/ );
        $this->_writeDebug( "found old $version, short version $short" );
    } elsif( $text =~ m/\$RELEASE *= *['"]([^'"]+)/s ) {
        # TWiki-4.0 and newer
        $version = $1;
        $short = $1 if( $version =~ m/([0-9]+\.[0-9]+)/ );
        $this->_writeDebug( "found $version, short version $short" );
    }
    return( $version, $short );
}

#==================================================================
sub _buildFileName {
    my( $this ) = @_;
    my( $sec, $min, $hour, $day, $mon, $year ) = localtime( time() );
    my $text = 'twiki-backup-';
    $text .= sprintf( "%.4u", $year + 1900 ) . '-';
    $text .= sprintf( "%.2u", $mon + 1 ) . '-';
    $text .= sprintf( "%.2u", $day ) . '-';
    $text .= sprintf( "%.2u", $hour ) . '-';
    $text .= sprintf( "%.2u", $min ) . '.zip';
    return _untaintChecked( $text );
}

#==================================================================
sub _gatherLocation {
    my( $this ) = @_;

    my $loc;

    # discover TWiki bin dir
    my $binDir = $ENV{SCRIPT_FILENAME} || '';
    $binDir =~ s|(.*)[\\/]+.*|$1|;       # cut off script to get name of bin dir
    unless( $binDir )  {
        # last resort to discover bin dir
        require Cwd;
        import Cwd qw( cwd );
        $binDir = cwd();
    }
    $loc->{BinDir} = _untaintChecked( $binDir );

    # discover twiki/bin/LocalLib.cfg
    $loc->{LocalLib}   = _untaintChecked( "$binDir/LocalLib.cfg" ) if( -e "$binDir/LocalLib.cfg" );

    # discover lib dir via twiki/lib/TWiki.pm
    foreach my $dir ( @INC ) {
        if( -e "$dir/TWiki.pm" ) {
            $loc->{LibDir} = _untaintChecked( $dir );
            last;
        }
    }
    if( ! $loc->{LibDir} && $TWiki::cfg{DataDir} ) {
        my $dir = $TWiki::cfg{DataDir};
        $dir =~ s|(.*)[\\/]+.*|$1|;      # go one directory up
        if( -e "$dir/lib/TWiki.pm" ) {
            $loc->{LibDir} = _untaintChecked( "$dir/lib" );
        }
    }
    unless( $loc->{LibDir} ) {
        my $dir = $loc->{BinDir};
        $dir =~ s|(.*)[\\/]+.*|$1|;      # go one directory up
        $loc->{LibDir} = _untaintChecked( "$dir/lib" );
    }

    # discover twiki/lib/LocalSite.cfg
    if( -e $loc->{LibDir} . "/LocalSite.cfg" ) {
        $loc->{LocalSite} = $loc->{LibDir} . "/LocalSite.cfg";
    }

    # discover TWiki root dir
    my $rootDir = $TWiki::cfg{DataDir} || $loc->{LibDir};
    $rootDir =~ s|(.*)[\\/]+.*|$1|;      # go one directory up
    $loc->{RootDir} = _untaintChecked( $rootDir );

    # discover common TWiki directories
    $loc->{DataDir}    = _untaintChecked( $TWiki::cfg{DataDir}    || "$rootDir/data" );
    $loc->{PubDir}     = _untaintChecked( $TWiki::cfg{PubDir}     || "$rootDir/pub" );
    $loc->{WorkingDir} = _untaintChecked( $TWiki::cfg{WorkingDir} || "$rootDir/working" );

    # discover apache conf file twiki.conf
    foreach my $dir ( @apacheConfLocations ) {
        if( -e "$dir/twiki.conf" ) {
            $loc->{ApacheConf} = _untaintChecked( "$dir/twiki.conf" );
            last;
        }
    }

    return $loc;
}

#==================================================================
sub _testZipMethods {
    my( $this ) = @_;

    my $text = '';
    $text .= "\n<br />===== Dirs <pre>\n"
           . "- BaseTopic:    $this->{BaseTopic}\n"
           . "- BaseWeb:      $this->{BaseWeb}\n"
           . "- Root:         $this->{Location}{RootDir}\n"
           . "- BinDir:       $this->{Location}{BinDir}\n"
           . "- LibDir:       $this->{Location}{LibDir}\n"
           . "- DataDir:      $this->{Location}{DataDir}\n"
           . "- PubDir:       $this->{Location}{PubDir}\n"
           . "- WorkingDir:   $this->{Location}{WorkingDir}\n"
           . "- LocalLib:     $this->{Location}{LocalLib}\n"
           . "- LocalSite:    $this->{Location}{LocalSite}\n"
           . "- ApacheConf:   $this->{Location}{ApacheConf}\n"
           . "- TempDir:      $this->{TempDir}\n"
           . "- DaemonDir:    $this->{DaemonDir}\n"
           . "\n</pre>\n";

    $text .= "\n<br />===== Test _listAllBackups()<pre>\n"
           . join( "\n", $this->_listAllBackups() )
           . "\n</pre>Error return: $this->{error} <p />\n";

    my $zip = 'twiki-backup-2018-01-18-19-33.zip';
    $this->{error} = '';
    $text .= "<br />===== Test _createBackup( { file => $zip } )<pre>\n" 
           . $this->_createBackup( undef, { file => $zip } ) 
           . "\n</pre>Error return: $this->{error}\n";

    $this->{error} = '';
    $text .= "<br />===== Test _listZip( $zip )<pre>\n"
           . join( "\n", $this->_listZip( $zip ) )
           . "\n</pre>Error return: $this->{error}\n";

    chdir( $this->{BackupDir} );
    $this->{error} = '';
    $text .= "<br />===== Test _unZip( $zip )\n";
    $this->_unZip( $zip );
    $text .= "<br />Error return: $this->{error}\n";

#    $this->{error} = '';
#    $text .= "<br />===== Test _deleteZip( $zip )\n";
#    $this->_deleteZip( "$zip" );
#    $text .= "<br />Error return: $this->{error}\n";

    $this->{error} = '';
    $text .= "<br />===== Test _deleteZip( not-exist-$zip )\n";
    $this->_deleteZip( "not-exist-$zip" );
    $text .= "<br />Error return: $this->{error}\n";

    return $text;
}

#==================================================================
sub _listAllBackups {
    my( $this ) = @_;

    $this->_writeDebug( "_listAllBackups" );

    my @files = ();
    unless( opendir( DIR, $this->{BackupDir} ) ) {
        $this->_setError( "ERROR: Can't open the backup directory - $!" );
        return @files;
    }
    @files = grep{ /twiki-backup-.*\.zip/ }
             grep{ -f "$this->{BackupDir}/$_" }
             readdir( DIR );
    closedir( DIR ); 

    return @files;
}

#==================================================================
sub _getZipFilePath {
    my( $this, $name ) = @_;
    return "$this->{BackupDir}/$name";
}

#==================================================================
sub _createZip {
    my( $this, $name, $baseDir, @dirs ) = @_;

    $this->_writeDebug( "_createZip( $name, $baseDir, " 
      . join( ", ", @dirs ) . " )" ) if $this->{Debug};

    chdir( $baseDir );
    my $zipFile = "$this->{BackupDir}/$name";
    my @cmd = split( /\s+/, $this->{createZipCmd} );
    if( $this->{ScriptType} eq 'cli' ) {
        print "Backing up to $name: " . join( ", ", @dirs ) . "\n";
    }
    my ( $stdOut, $stdErr, $success, $exitCode ) = capture_exec( @cmd, $zipFile, @dirs );
    if( $exitCode ) {
        $this->_setError( "ERROR: Can't create backup $name. $stdErr" );
    }
    return;
}

#==================================================================
sub _deleteZip {
    my( $this, $name ) = @_;

    $this->_writeDebug( "_deleteZip( $name )" ) if $this->{Debug};

    my $zipFile = "$this->{BackupDir}/$name";
    unless( -e $zipFile ) {
        $this->_setError( "ERROR: Backup $name does not exist" );
        return;
    }
    unless( unlink( $zipFile ) ) {
        $this->_setError( "ERROR: Can't delete $name - $!" );
    }
    return;
}

#==================================================================
sub _listZip {
    my( $this, $name ) = @_;

    $this->_writeDebug( "_listZip( $name )" ) if $this->{Debug};

    my @files = ();
    my $zipFile = "$this->{BackupDir}/$name";
    unless( -e $zipFile ) {
        $this->_setError( "ERROR: Backup $name does not exist" );
        return @files;
    }
    my @cmd = split( /\s+/, $this->{listZipCmd} );
    my ( $stdOut, $stdErr, $success, $exitCode ) = capture_exec( @cmd, $zipFile );
    if( $exitCode ) {
        $this->_setError( "ERROR: Can't list content of backup $name. $stdErr" );
    }
    @files = map{ s/^\s*([0-9\-\:]+\s*){3}//; $_ }   # remove size and timestamp
             grep{ /^\s*[0-9]+\s*[0-9]+\-.*[^\/]$/ } # exclude header, footer & directories
             split( /[\n\r]+/, $stdOut );
    return @files;
}

#==================================================================
sub _unZip {
    my( $this, $name ) = @_;

    $this->_writeDebug( "_unZip( $name )" ) if $this->{Debug};

    my $zipFile = "$this->{BackupDir}/$name";
    unless( -e $zipFile ) {
        $this->_setError( "ERROR: Backup $name does not exist" );
        return;
    }
    my @cmd = split( /\s+/, $this->{unZipCmd} );
    my ( $stdOut, $stdErr, $success, $exitCode ) = capture_exec( @cmd, $zipFile );
    if( $exitCode ) {
        $this->_setError( "ERROR: Can't unzip $name. $stdErr" );
    }
    return;
}

#==================================================================
sub _writeDebug {
    my( $this, $text ) = @_;

    return unless( $this->{Debug} );
    if( $this->{ScriptType} eq 'cli' ) {
        print "DEBUG: $text\n";
    } elsif( exists( &TWiki::Func::writeDebug ) ) {
        TWiki::Func::writeDebug( "- BackupRestorePlugin: $text" );
    } else {
        print STDERR "DEBUG BackupRestorePlugin: $text\n";
    }
}

#==================================================================
sub _makeDir {
    my( $this, $dir, $mode, $timestamp ) = @_;

    unless( mkdir( $dir ) ) {
        $this->_setError( "ERROR: Can't create $dir" );
        return 1;
    }
    chmod( $mode, $dir ) if( $mode );
    utime( $timestamp, $timestamp, $dir ) if( $timestamp );
    return 0;
}

#==================================================================
sub _copyFile {
    my( $this, $fromFile, $toDir, $mode, $timestamp ) = @_;

    unless( File::Copy::copy( $fromFile, $toDir ) ) {
        $this->_setError( "ERROR: Can't copy $fromFile to $toDir" );
        return 1;
    }
    return 0 unless( $mode || $timestamp );

    my $dest = $toDir;
    if( -d $dest ) {
        $fromFile =~ s/.*[\/\\]+//; # remove path from source file
        $dest .= "/$fromFile";
    }
    chmod( $mode, $dest ) if( $mode );
    utime( $timestamp, $timestamp, $dest ) if( $timestamp );
    return 0;
}

#==================================================================
sub _copyDirRecursively {
    my( $this, $fromDir, $toDir, $dirMode, $fileMode, $timestamp ) = @_;

    unless( -d $fromDir ) {
        $this->_setError( "ERROR: Can't copy directory, source directory $fromDir does not exist" );
        return 1;
    }
    unless( -d $toDir ) {
        $this->_setError( "ERROR: Can't copy directory, destination $toDir must be an existing directory" );
        return 1;
    }

    # create destination directory if needed
    my $dir = $fromDir;
    $dir =~ s/.*[\/\\]+//; # remove path from source dir
    $toDir .= "/$dir";
    if( -d $toDir ) {
        # copy into existing sub-dir
    } elsif( -e $toDir ) {
        $this->_setError( "ERROR: Can't copy directory, destination $toDir exists but is not a directory" );
        return 1;
    } else {
        # create sub-dir
        if( $this->_makeDir( $toDir, $dirMode, $timestamp ) ) {
            return 1;
        }
    }

    # copy directory content
    foreach my $file ( _getDirContent( $fromDir ) ) {
        if( -d "$fromDir/$file" ) {
            if( $this->_copyDirRecursively( "$fromDir/$file", $toDir, $dirMode, $fileMode, $timestamp ) ) {
                return 1;
            }
        } elsif( -f "$fromDir/$file" ) {
            if( $this->_copyFile( "$fromDir/$file", $toDir, $fileMode, $timestamp ) ) {
                return 1;
            }
        }
    }
    return 0;
}

#==================================================================
# LOW LEVEL FUNCTIONS (NOT METHODS)
#==================================================================

#==================================================================
sub _readFile {
    my( $name, $lines ) = @_;
    my $data = '';
    open( IN_FILE, "<$name" ) || return '';
    if( $lines ) {
        # read up to $lines of file
        while( $lines-- && ( $data .= <IN_FILE> ) ) { };
    } else {
        # read whole file at once to EOF
        local $/ = undef;
        $data = <IN_FILE>;
    }
    close( IN_FILE );
    $data = '' unless $data; # no undefined
    return $data;
}

#==================================================================
sub _saveFile {
    my( $name, $text ) = @_;

    unless ( open( FILE, ">$name" ) )  {
        return "Can't create file $name - $!\n";
    }
    print FILE $text;
    close( FILE );
    return '';
}

#==================================================================
sub _sanitizeFileName {
    my( $name, $escapeDot ) = @_;

    $name ||= '';
    $name =~ s/[^0-9a-zA-Z_\-\.]//go;
    $name =~ s/\./\\\./go if( $escapeDot );
    return $name;
}

#==================================================================
sub _getDirContent {
    my( $dir ) = @_;

    my @files;
    opendir( DIR, $dir ) or return;
    while( my $file = readdir( DIR )) {
        next if( $file =~ m/^\.\.?$/ );
	push( @files, _untaintChecked( $file ) );
    }
    closedir( DIR );

    return @files;
}

#==================================================================
sub _splitTopDir {
    my( $dir ) = @_;

    my $base = '';
    if( $dir =~ /^(.*)[\/\\]+(.*)$/ ) {
        $base = $1;
        $dir  = $2;
    }
    return( $base, $dir );
}

#==================================================================
sub _untaintChecked {
    my( $text ) = @_;

    $text = $1 if( $text =~ /^(.*)$/ );
    return $text;
}

#==================================================================
1;
