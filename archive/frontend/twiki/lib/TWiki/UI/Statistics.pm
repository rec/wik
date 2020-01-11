# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
# Copyright (C) 2002 Richard Donkin, rdonkin@bigfoot.com
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

package ParaLogReader;

# An internal class to read TWiki log entries in the chronological order from
# multiple log files.

# Usage:
# <verbatim>
# my $reader = ParaLogReader->new(@logFiles);
# while ( my $line = $reader->getline() ) {
#    ...
# }
# </verbatim>

use strict;
use IO::File;

sub insert {
    my ($arrayRef, $val) = @_;
    my $idx = 0;
    while ( $idx < @$arrayRef ) {
	last if ( $val lt $arrayRef->[$idx] );
	$idx++;
    }
    splice(@$arrayRef, $idx, 0, $val);
    $idx;
}

sub readEnt {
    my $fh = shift;
    my $line;
    while ( $line = <$fh> ) {
	last if ( $line =~ /^\| \d{4}-\d\d-\d\d - \d\d:\d\d/ );
    }
    $line;
}

sub new {
    my ($class, @files) = @_;
    my $self = bless {}, $class;
    my @fhs;
    my @heads;
    for my $i ( @files ) {
	my $fh = IO::File->new("< $i");
	if ( $fh ) {
	    my $line = readEnt($fh);
	    if ( $line ) {
		splice(@fhs, insert(\@heads, $line), 0, $fh);
	    }
	    else {
		$fh->close();
	    }
	}
    }
    $self->{fhs} = \@fhs;
    $self->{heads} = \@heads;
    $self;
}

sub getline {
    my ($self) = @_;
    my $fhsRef = $self->{fhs};
    my $headsRef = $self->{heads};
    return undef if ( @$headsRef == 0 );
    my $val = shift @$headsRef;
    my $fh = shift @$fhsRef;
    my $next = readEnt($fh);
    if ( $next ) {
	splice(@$fhsRef, insert($headsRef, $next), 0, $fh);
    }
    else {
	$fh->close();
    }
    $val;
}
#===========================================================


=begin twiki

---+ package TWiki::UI::Statistics

Statistics extraction and presentation

=cut

package TWiki::UI::Statistics;

use strict;
use Assert;
use File::Temp qw/ :seekable /;
use Error qw( :try );

require TWiki;
require TWiki::Sandbox;

my $debug = 0;

BEGIN {
    # Do a dynamic 'use locale' for this module
    if( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

=pod

---++ StaticMethod statistics( $session )

=statistics= command handler.
This method is designed to be
invoked via the =UI::run= method.

Generate statistics topic.
If a web is specified in the session object, generate WebStatistics
topic update for that web. Otherwise do it for all webs

=cut

#===========================================================
sub statistics {
    my $session = shift;

    my $webName = $session->{webName};

    # web to redirect to after finishing
    my $logDate = $session->{request}->param( 'logdate' ) || '';
    $logDate =~ s/[^0-9]//g;  # remove all non numerals
    $debug = $session->{request}->param( 'debug' );

    unless( $session->inContext( 'command_line' )) {
        # running from CGI
        $session->generateHTTPHeaders();
        $session->{response}->body(
            CGI::start_html( -title => 'TWiki: Create Usage Statistics' ) );
        if ( $TWiki::cfg{Stats}{DisableInvocationFromBrowser} ) {
            _printMsg( $session,
                       'This script is not for interactive use from browser' );
            $session->{response}->body( $session->{response}->body .
                                        CGI::end_html() );
            return;
        }
    }
    # Initial messages
    _printMsg( $session, 'TWiki: Create Usage Statistics' );
    _printMsg( $session, '!Do not interrupt this script!' );
    _printMsg( $session, '(Please wait until page download has finished)' );

    require TWiki::Time;
    my $currentMonth = TWiki::Time::formatTime( time(), '$year$mo', 'gmtime' );
    unless( $logDate ) {
        $logDate = $currentMonth;
    }

    my $logMon;
    my $logMo;
    my $logYear;
    if ( $logDate =~ /^(\d\d\d\d)(\d\d)$/ ) {
        $logYear = $1;
        $logMo = $2;
        $logMon = $TWiki::Time::ISOMONTH[ ( $logMo % 12 ) - 1 ];
        $currentMonth = ( $logDate eq $currentMonth ) ? 1 : 0;
    } else {
        _printMsg( $session, "!Error in date $logDate - must be YYYY-MM or YYYYMM" );
        return;
    }

    my $logMonYear = "$logMon $logYear";
    my $logYearMo = "$logYear-$logMo";
    _printMsg( $session, "* Statistics for $logYearMo" );
    _printMsg( $session, '* Executed by ' . $session->{users}->getWikiName( $session->{user} ) );

    my @logFiles;
    if ( my $logFileGlob = $TWiki::cfg{Stats}{LogFileGlob} ) {
        $logFileGlob =~ s/%DATE%/$logDate/g;
        @logFiles = glob $logFileGlob;
        if ( @logFiles == 0 ) {
            _printMsg( $session, "!Log files $logFileGlob do not exist; aborting" );
            return;
        }
    }
    else {
        my $logFile = $TWiki::cfg{LogFileName};
        $logFile =~ s/%DATE%/$logDate/g;
        unless( -e $logFile ) {
            _printMsg( $session, "!Log file $logFile does not exist; aborting" );
            return;
        }
        @logFiles = ($logFile);
    }

    # Do a single data collection pass on the temporary copy of logfile,
    # then process each web once.
    my $stats = _collectLogData( $session, @logFiles );
    _printMsg( $session, "* Finished collecting log data at " .
               TWiki::Time::formatTime(time()) );

    my %roWeb;
    my $roWebStatsOn;
    my @weblist;
    my $webSet = TWiki::Sandbox::untaintUnchecked($session->{request}->param( 'webs' ))
               || $session->{requestedWebName};
    if( $webSet) {
        # do specific webs
        push( @weblist,
              grep { TWiki::Func::webExists( $_ ) }
              map { s/$TWiki::cfg{NameFilter}//go; $_; }
              split( /,\s*/, $webSet )
            );

    } else {
        # otherwise do all user webs:
        @weblist = $session->{store}->getListOfWebs( 'user,writable' );
        # add read-only webs if appropriate
        if ( $TWiki::cfg{Stats}{ReadOnlyWebs} ) {
            if ( $roWebStatsOn = $TWiki::cfg{Stats}{ReadOnlyWebStatsOn} ) {
                my %included = map { $_ => 1 } @weblist;
                if ( $included{$roWebStatsOn} ) {
                    %roWeb = map { $_ => 1 }
                                 @{$TWiki::cfg{Stats}{ReadOnlyWebs}};
                    push(@weblist, @{$TWiki::cfg{Stats}{ReadOnlyWebs}});
                }
            }
        }
        if ( $TWiki::cfg{Stats}{ExcludedWebRegex} ) {
            @weblist = grep { !/$TWiki::cfg{Stats}{ExcludedWebRegex}/ }
                @weblist;
        }
    }

    # do site statistics (only if no specific webs selected, or if force update from SiteStatistics)
    my $siteStatsTopic = $TWiki::cfg{Stats}{SiteStatsTopicName} || 'SiteStatistics';
    # append YYYY to the end of SiteStatistics if $cfg{Stats}{TopicPerYear} = 1
    $siteStatsTopic .= $logYear 
      if ( $TWiki::cfg{Stats}{TopicPerYear} );

    my $usersWebMode = $session->getContentMode($TWiki::cfg{UsersWebName});
    if( (!$webSet || $session->{topicName} eq $siteStatsTopic) &&
        ($usersWebMode eq 'local' || $usersWebMode eq 'master')
        # Site statistics written on the {UsersWebName} web, if the web is not
        # writable on this site, it's no use doing site statisitcs
    ) {
        try {
            my $siteStats = _collectSiteStats( $session, $currentMonth,
                                               $logYearMo, $stats );
            _processSiteStats( $session, $logYear, $logYearMo, $logMonYear, $siteStats );
        } catch TWiki::AccessControlException with  {
            _printMsg( $session, '  - ERROR: no permission to CHANGE site statistics topic');
        }
    }

    foreach my $web ( @weblist ) {
        my $webToSave;
        if ( $roWeb{$web} ) {
            $webToSave = $roWebStatsOn;
        }
        try {
            _processWeb( $session, $web, $logYear, $logYearMo, $logMonYear,
                         $stats, $webToSave );
        } catch TWiki::AccessControlException with  {
            _printMsg( $session, '  - ERROR: no permission to CHANGE statistics topic in '.$web);
        }
    }

    if( !$session->inContext( 'command_line' ) ) {
        my $web   = $session->{webName};
        my $topic = $session->{topicName};
        if( $topic eq $TWiki::cfg{HomeTopicName} ) {
            $web   = $TWiki::cfg{UsersWebName};
            $topic = $siteStatsTopic;
        }
        my $url = $session->getScriptUrl( 0, 'view', $web, $topic );
        _printMsg( $session, '* Go to '
                   . CGI::a( { href => $url,
                               rel => 'nofollow' }, "$web.$topic") );
    }
    _printMsg( $session, 'End creating usage statistics' );
    $session->{response}->body( $session->{response}->body . CGI::end_html() )
        unless ( $session->inContext('command_line') );
}

#===========================================================
# Debug only
# Print all entries in a view or contrib hash, sorted by web and item name
#===========================================================
sub _debugPrintHash {
    my ($statsRef) = @_;
    # print "Main.WebHome views = " . ${$statsRef}{'Main'}{'WebHome'}."\n";
    # print "Main web, TWikiGuest contribs = " . ${$statsRef}{'Main'}{'Main.TWikiGuest'}."\n";
    foreach my $web ( sort keys %$statsRef) {
        my $count = 0;
        print $web,' web:',"\n";
        # Get reference to the sub-hash for this web
        my $webhashref = ${$statsRef}{$web};
        # print 'webhashref is ' . ref ($webhashref) ."\n";
        # Items can be topics (for view hash) or users (for contrib hash)
        foreach my $item ( sort keys %$webhashref ) {
            print "  $item = ",( ${$webhashref}{$item} || 0 ),"\n";
            $count += ${$webhashref}{$item};
        }
        print "  WEB TOTAL = $count\n";
    }
}

#===========================================================
# Process the whole log file and collect information in hash tables.
# Must build stats for all webs, to handle case of renames into web
# requested for a single-web statistics run.
#
# Main hash tables are divided by web:
#
#   $view{$web}{$TopicName} == number of views, by topic
#   $contrib{$web}{"Main.".$WikiName} == number of saves/uploads, by user
#===========================================================
sub _collectLogData {
    my( $session, @logFiles ) = @_;

    # Log file format:
    # | date | user | operation | web.topic | notes | ip address |
    # date, such as "2011-04-17 - 02:43" (or "03 Feb 2000 - 02:43" up to TWiki-4.2)
    # user, such as "Main.PeterThoeny" (legacy)
    # user, such as "PeterThoeny" (TWiki internal authentication)
    # user, such as "peter" (intranet login)
    # operation, such as "view", "edit", "save"
    # web.topic, such as "MyWeb.MyTopic"
    # notes, such as "minor", "not on thursdays"
    # ip address, such as "127.0.0.5"

    my %view;	 # Hash of hashes, counts topic views by (web, topic)
    my %save;    # Hash of hashes, counts topic saves by (web, topic)
    my %contrib; # Hash of hashes, counts uploads/saves by (web, user)
    my %viewer;	 # Hash of hashes, counts views by (web, user)

    # Hashes for each type of statistic, one hash entry per web
    my %statViews;
    my %statViewsBreakdown;
    my %statViewsUnique;
    my %statSaves;
    my %statSavesBreakdown;
    my %statSavesUnique;
    my %statUploads;
    my %statUploadsBreakdown;
    my %statUploadsUnique;
    my $users = $session->{users};

    # Copy the log file to temp file, since analysis could take some time
    my $tmpFileHandle;
    if ( @logFiles > 1 ) {
        $tmpFileHandle = ParaLogReader->new(@logFiles);
    }
    else {
        $tmpFileHandle = new File::Temp(
            DIR      => $session->{store}->getWorkArea( 'CoreStatistics' ),
            TEMPLATE => 'twiki-stats-XXXXXXXXXX',
            SUFFIX   => '.txt',
            # UNLINK => 0      # To debug, uncomment this to keep the temp file
            );

        # Don't use File::Copy, it does not work with File::Temp older than 0.22
        _copy( $logFiles[0], $tmpFileHandle ) or throw Error::Simple( 'Cannot backup log file: '.$! );
        # Seek to start of temp file
        $tmpFileHandle->seek( 0, 0 );
    }

    my $breakdown = $TWiki::cfg{Stats}{Breakdown};
    my %u2a;
    my $excluded;
    if ( $TWiki::cfg{Stats}{ExcludedWebRegex} ) {
        $excluded = qr/$TWiki::cfg{Stats}{ExcludedWebRegex}/;
    }
    else {
        $excluded = qr/^$/; # a regex not matching any web
    }
    # main log file loop, line by line
    while ( my $line = $tmpFileHandle->getline ) {
        my @fields = split( /\s*\|\s*/, $line );

        my( $date, $logFileUserName, $affiliation );
        while( !$date && scalar( @fields )) {
            $date = shift @fields;
        }
        while( !$logFileUserName && scalar( @fields )) {
            $logFileUserName = shift @fields;
            $logFileUserName = TWiki::Func::getCanonicalUserID($logFileUserName);
        }
        if ( $breakdown ) {
            if ( !defined($affiliation = $u2a{$logFileUserName}) ) {
                $affiliation = $users->getAffiliation($logFileUserName);
                $affiliation = 'Unknown' if ( !defined($affiliation) );
                $u2a{$logFileUserName} = $affiliation;
            }
        }

        my( $opName, $webTopic, $notes, $ip ) = @fields;

        # ignore minor changes - not statistically helpful
        next if( $notes && $notes =~ /(minor|dontNotify)/ );

        # ignore op names we don't need
        next unless( $opName && $opName =~ /^(view|save|upload|rename)$/ );

        # .+ is used because topics name can contain stuff like !, (, ), =, -, _ and they should have stats anyway
        if( $opName && $webTopic =~ /(^$TWiki::regex{webNameRegex})\.(.+)/ ) {
            my $webName = $1;
            my $topicName = $2;

            # ignore excluded webs
            next if( $webName =~ $excluded );

            my $fqWikiName = $users->webDotWikiName($logFileUserName);
            if( $opName eq 'view' ) {
                next if( $topicName =~ /^(WebAtom|WebRss|WebStatistics\d*)$/ );
                next if( $notes &&
                         ($notes =~ /\(not exist\)/ ||
                          $notes =~ /\(web doesn\'t exist\)/) );
                $statViews{$webName}++;
                $statViewsBreakdown{$webName}{$affiliation}++
                    if ( $breakdown );
                $statViewsUnique{$webName}{$logFileUserName} = 1;
                $view{$webName}{$topicName}++;
                $viewer{$webName}{$fqWikiName}++;

            } elsif( $opName eq 'save' ) {
                next if( $topicName =~ /^(SiteStatistics|WebStatistics)\d*$/ );
                $statSaves{$webName}++;
                $statSavesBreakdown{$webName}{$affiliation}++
                    if ( $breakdown );
                $statSavesUnique{$webName}{$logFileUserName} = 1;
                $save{$webName}{$topicName}++;
                $contrib{$webName}{$fqWikiName}++;

            } elsif( $opName eq 'upload' ) {
                $statUploads{$webName}++;
                $statUploadsBreakdown{$webName}{$affiliation}++
                    if ( $breakdown );
                $statUploadsUnique{$webName}{$logFileUserName} = 1;
                $contrib{$webName}{$fqWikiName}++;

            } elsif( $opName eq 'rename' ) {
                # Pick up the old and new topic names
                $notes =~/moved to ($TWiki::regex{webNameRegex})\.($TWiki::regex{wikiWordRegex}|$TWiki::regex{abbrevRegex}|\w+)/o;
                my $newTopicWeb = $1;
                my $newTopicName = $2;

                # Get number of views for old topic this month (may be zero)
                my $oldViews = $view{$webName}{$topicName} || 0;

                # Transfer views from old to new topic
                $view{$newTopicWeb}{$newTopicName} = $oldViews
                    unless ( $newTopicWeb =~ $excluded );
                delete $view{$webName}{$topicName};

                # Transfer views from old to new web
                if ( $newTopicWeb ne $webName ) {
                    $statViews{$webName} -= $oldViews;
                    $statViews{$newTopicWeb} += $oldViews;
                }
            }
        } else {
            $session->writeDebug('WebStatistics: Bad logfile line '.$line)
                if ( $debug && $webTopic !~ /^_/ );
        }
    }

    # Note: No need to close $tmpFileHandle, temp file is removed by destructor

    return {
        view     => \%view,
        viewer   => \%viewer,
        views    => \%statViews,
        viewsb   => \%statViewsBreakdown,
        viewsu   => \%statViewsUnique,
        save     => \%save,
        saves    => \%statSaves,
        savesu   => \%statSavesUnique,
        savesb   => \%statSavesBreakdown,
        uploads  => \%statUploads,
        uploadsb => \%statUploadsBreakdown,
        uploadsu => \%statUploadsUnique,
        contrib  => \%contrib,
    };
}

#===========================================================
sub _copy {
    my( $fromFile, $toHandle ) = @_;

    open( FROM, '<', $fromFile ) or return;
    binmode( FROM ); # $toHandle is already binmode
    my $buff;
    while( read( FROM, $buff, 8 * 2**10 ) ) {
        print $toHandle $buff;
    }
    close( FROM ) or return; # do not close $toHandle
    return 1;
}

#===========================================================
sub _getDiskUse {
    my( $session, $dir ) = @_;
    my $diskUse = 0;
    my $cmd = $TWiki::cfg{Stats}{dfCmd} || 'df %DIRECTORY|F%';
    my( $output, $exit );
    try {
        ( $output, $exit ) = $TWiki::sandbox->sysCommand( $cmd, DIRECTORY => $dir );
        if( $exit ) {
            _printMsg( $session, "  - ERROR: $cmd of $dir failed: $exit $output" );
            return 0;
        } elsif( $output =~ /^.*[ \t]([0-9\.]+)\%.*?$/s ) {
            return $1;
        }
        return 0;

    } catch Error::Simple with {
        my $message =  shift->{-text};
        _printMsg( $session, "  - ERROR: $cmd of $dir failed: $message" );
        return 0;
    }
}

#===========================================================
sub _getDirSize {
    my( $dir ) = @_;
    my $size = 0;

    opendir( DIR, $dir ) || return $size;
    my @files = map { $dir . '/' . $_ } # create full path
                grep { !/^\.\.?$/ }     # omit . and .. files
                readdir( DIR );
    closedir( DIR );
    foreach my $f ( @files ) {
        if( -d $f ) {
            $size += _getDirSize( $f );
        } else {
            $size += ( -s $f || 0 );
        }
    }
    return $size;
}

# Align numbers by putting two &amp;nbsp;s for a digit. This is crude but
# works way better than single &amp;nbps; per diget.
sub _alignNums {
    defined($_[0]) or return ();
    $_[0] =~ /^(\d*)/;
    my $width = length($1);
    return
	map { s/^(\d+)/('&nbsp;' x (2*($width - length($1)))) . $1/e; $_ } @_;
}

sub _nbsp {
    my $str = shift;
    $str =~ s/\&/&amp;/g;
    $str =~ s/ /&nbsp;/g;
    return $str;
}

sub _numberUniqueBreakdown {
    my ($what, $stats, $maxAffiliations, $web) = @_;
    my ($n, $nu);
    if ( $web ) {
        $n = $stats->{$what}{$web} || 0;
        my $ref = $stats->{$what.'u'}{$web};
        $nu = ref $ref eq 'HASH' ? scalar keys %$ref : 0;
    }
    else {
        $n = 0;
        foreach my $v ( values %{$stats->{$what}} ) {
            $n += ( $v || 0 );
        }
        my %unique;
        foreach my $v ( values %{$stats->{$what.'u'}} ) {
            @unique{keys %$v} = (1) x (scalar keys %$v);
        }
        $nu = scalar keys %unique;
    }
    my $result = $n . CGI::br() .  "($nu unique users)";
    if ( $TWiki::cfg{Stats}{Breakdown} && $n ) {
        my $breakdown;
        if ( $web ) {
            $breakdown = $stats->{$what.'b'}{$web};
        }
        else {
            my %bd;
            foreach my $v ( values %{$stats->{$what.'b'}} ) {
                foreach my $w ( keys %$v ) {
                    $bd{$w} += ( $v->{$w} || 0 );
                }
            }
            $breakdown = \%bd;
        }
        my $i = 0;
        my @list =
            grep { $i++ < $maxAffiliations }
            map { _nbsp("$breakdown->{$_} $_") }
            sort { $breakdown->{$b} <=> $breakdown->{$a} }
            keys %$breakdown;
        $result .= CGI::br() . join(CGI::br(), _alignNums(@list));
    }
    unless ( $TWiki::cfg{Stats}{Breakdown} ) {
        $result = ' ' . $result;
        # to make the cell right aligned.
    }
    return $result;
}

sub _extractNumber {
    my $nub = shift;
    $nub =~ /^(\d*)/;
    return $1;
}

#===========================================================
sub _collectSiteStats {
    my( $session, $currentMonth, $logYearMo, $stats) = @_;

    _printMsg( $session, '* Reporting overall statistics' );

    my $siteStats;

    my $site = $TWiki::cfg{DefaultUrlHost} . $TWiki::cfg{ScriptUrlPath};
    my $ff = chr(255) x length( $site );
    $site = $site ^ $ff; # obfuscate site name
    $siteStats->{statSite} = uc( unpack( "H*", $site ) ); # hex encode

    $siteStats->{statVersion} = $TWiki::VERSION;
    $siteStats->{statVersion} =~ s/[, ].*//;
    $siteStats->{statVersion} = '' unless( $currentMonth );

    $siteStats->{statDate} = $logYearMo;

    my @weblist = $session->{store}->getListOfWebs( 'user' );
    if ( $TWiki::cfg{Stats}{ExcludedWebRegex} ) {
        @weblist = grep { !/$TWiki::cfg{Stats}{ExcludedWebRegex}/ } @weblist;
    }
    $siteStats->{statWebs} = scalar @weblist;
    $siteStats->{statWebs} = 0 unless( $currentMonth );

    $siteStats->{statTopics} = 0;
    $siteStats->{statAttachments} = 0;
    if( $currentMonth ) {
        foreach my $w ( @weblist ) {
            my @topics = $session->{store}->getTopicNames( $w );
            # add number of topics in web
            $siteStats->{statTopics} += scalar @topics;
            # add number of attachments in web using a search
            my $result = $session->{store}->searchInWebContent(
                           '[%]META:FILEATTACHMENT{', $w, \@topics,
                           { type => 'regex' }
                         );
            foreach my $topic ( keys %$result ) {
                $siteStats->{statAttachments} += scalar @{$result->{$topic}};
            }
        }
        _printMsg( $session,
            "  - webs: " . _extractNumber($siteStats->{statWebs}) . 
            ", topics: " . _extractNumber($siteStats->{statTopics}) .
            ", attachments: " . _extractNumber($siteStats->{statAttachments}) );
    }

    my $ma = $TWiki::cfg{Stats}{SiteTopAffiliation}; # max affiliations
    $siteStats->{statViews}   = _numberUniqueBreakdown('views',   $stats, $ma);
    $siteStats->{statSaves}   = _numberUniqueBreakdown('saves',   $stats, $ma);
    $siteStats->{statUploads} = _numberUniqueBreakdown('uploads', $stats, $ma);

    my $statWebsViewed = scalar keys %{$stats->{view}};
    if ( $TWiki::cfg{Stats}{SiteTopViews} ) {
        my @topViews =
            _getTopList($TWiki::cfg{Stats}{SiteTopViews}, $stats->{views}, 1);
        if ( @topViews ) {
            $statWebsViewed .= CGI::br() . join(CGI::br(), @topViews);
            $topViews[0] =~ s/^.*\]\[([^\]]*).*$/$1/;
            _printMsg( $session, '  - top web viewed: '.$topViews[0] );
        }
    }
    else {
        $statWebsViewed = ' ' . $statWebsViewed;
    }
    $siteStats->{statWebsViewed} = $statWebsViewed;

    $siteStats->{statTopicsViewed} = 0;
    foreach my $v ( values %{$stats->{view}} ) {
        $siteStats->{statTopicsViewed} += scalar keys %$v
            if ( ref $v eq 'HASH' );
    }

    my $statWebsUpdated = scalar keys %{$stats->{save}};
    if ( $TWiki::cfg{Stats}{SiteTopUpdates} ) {
        my @topUpdates =
            _getTopList($TWiki::cfg{Stats}{SiteTopUpdates}, $stats->{saves}, 1);
        if ( @topUpdates ) {
            $statWebsUpdated .= CGI::br() . join(CGI::br(), @topUpdates);
            $topUpdates[0] =~ s/^.*\]\[([^\]]*).*$/$1/;
            _printMsg( $session, '  - top web updated: '.$topUpdates[0] );
        }
    }
    else {
        $statWebsUpdated = ' ' . $statWebsUpdated;
    }
    $siteStats->{statWebsUpdated} = $statWebsUpdated;

    $siteStats->{statTopicsUpdated} = 0;
    foreach my $v ( values %{$stats->{save}} ) {
        $siteStats->{statTopicsUpdated} += scalar keys %$v
            if ( ref $v eq 'HASH' );
    }

    _printMsg( $session,
               "  - view: " . _extractNumber($siteStats->{statViews}) .
               ", save: "   . _extractNumber($siteStats->{statSaves}) .
               ", upload: " . _extractNumber($siteStats->{statUploads}) );

    $siteStats->{statDataSize} = 0;
    $siteStats->{statPubSize} = 0;
    if( $currentMonth ) {
        my $dataSize = 0;
        my $pubSize = 0;
        for my $diskID ( $session->getDiskList() ) {
            $dataSize +=
              _getDirSize($session->getDataDir('', $diskID)) / ( 1024 * 1024 );
            $pubSize  +=
              _getDirSize($session->getPubDir('', $diskID)) / ( 1024 * 1024 );
        }
        $siteStats->{statDataSize} = sprintf("%0.1f", $dataSize );
        $siteStats->{statPubSize}  = sprintf("%0.1f", $pubSize );
        _printMsg( $session, "  - data size: " . $siteStats->{statDataSize} .
                             " MB, pub size: " . $siteStats->{statPubSize} . " MB" );
    }

    $siteStats->{statDiskUse} = 0;
    if( $currentMonth ) {
        my $totalDiskUse = '';
        for my $diskID ( $session->getDiskList() ) {
            my $dataUse =
                _getDiskUse( $session, $session->getDataDir('', $diskID) );
            my $pubUse  =
                _getDiskUse( $session, $session->getPubDir('', $diskID) );
            if( $pubUse > $dataUse ) {
                # pub is mounted on different disk, report this one as the more
                # critical one
                $dataUse = $pubUse;
            }
            if ( $diskID ) {
                $totalDiskUse .= '<br/>' . $dataUse . '%';
            }
            else {
                $totalDiskUse = $dataUse . '%';
            }
        }
        $siteStats->{statDiskUse} = $totalDiskUse;
        _printMsg( $session, "  - disk use: " . $siteStats->{statDiskUse} );
    }

    $siteStats->{statUsers} = 0;
    $siteStats->{statGroups} = 0;
    if( $currentMonth ) {
        my $it = $session->{users}->eachUser();
        $it->{process} = sub { return 1; };
        while( $it->hasNext() ) {
            $siteStats->{statUsers} += $it->next();
        }
        $it = $session->{users}->eachGroup();
        $it->{process} = sub { return 1; };
        while( $it->hasNext() ) {
            $siteStats->{statGroups} += $it->next();
        }
        _printMsg( $session, "  - users: " . $siteStats->{statUsers} .
                             ", groups: " . $siteStats->{statGroups} );
    }

    $siteStats->{statPlugins} = 0;
    if( $currentMonth ) {
        $siteStats->{statPlugins} = scalar @{$session->{plugins}{plugins}};
        unless( $TWiki::cfg{Stats}{DontContactTWikiOrg} ) {
            my $url = 'http://twiki.org/cgi-bin/pluginstats?';
            while ( my( $key, $val ) = each( %$siteStats ) ) {
                $val = TWiki::urlEncode( $val );
                $url .= "$key=" . $val . ";";
            }
            my $response = TWiki::Func::getExternalResource( $url );
            if( $response->is_error() ) {
                my $msg = "Code " . $response->code() . ": " . $response->message();
                $msg =~ s/[\n\r]/ /gos;
                _printMsg( $session, "! ERROR: $msg" );
            } else {
                my $text = $response->content();
                if( $text =~ /plugins: ?([0-9]+)/ ) {
                    $siteStats->{statPlugins} .= " of $1";
                }
            }
        }
        _printMsg( $session, "  - plugins: " . $siteStats->{statPlugins} );
    }

    $siteStats->{statTopViewers} = '';
    my %viewers;
    for my $v ( values %{$stats->{viewer}} ) {
        while ( my ($user, $count) = each %$v ) {
            $viewers{$user} += $count;
        }
    }
    my @topViewers =
        _getTopList($TWiki::cfg{Stats}{SiteTopViewers}, \%viewers);
    if( @topViewers ) {
        $siteStats->{statTopViewers} = join( CGI::br(), @topViewers );
        $topViewers[0] =~ s/^.*\]\[([^\]]*).*$/$1/;
        _printMsg( $session, '  - top viewer: '.$topViewers[0] );
    }

    $siteStats->{statTopContributors} = '';
    my %contribs;
    for my $v ( values %{$stats->{contrib}} ) {
        while ( my ($user, $count) = each %$v ) {
            $contribs{$user} += $count;
        }
    }
    my @topContribs =
        _getTopList($TWiki::cfg{Stats}{SiteTopContrib}, \%contribs);
    if( @topContribs ) {
        $siteStats->{statTopContributors} = join( CGI::br(), @topContribs );
        $topContribs[0] =~ s/^.*\]\[([^\]]*).*$/$1/;
        _printMsg( $session, '  - top contributor: '.$topContribs[0] );
    }

    _printMsg( $session, "  - Finished collecting data at " .
               TWiki::Time::formatTime(time()) );

    # use Data::Dumper;
    # print STDERR "=====\n" . Dumper($siteStats) . "=====\n";

    return $siteStats;
}

#===========================================================
sub _processSiteStats {
    my( $session, $logYear, $logYearMo, $logMonYear, $siteStats ) = @_;

    # Update the SiteStatistics topic
    my $web = $TWiki::cfg{UsersWebName}; 
    my $statsTopic = $TWiki::cfg{Stats}{SiteStatsTopicName} || 'SiteStatistics';
    $statsTopic .= $logYear if ( $TWiki::cfg{Stats}{TopicPerYear} );

    my( $meta, $text );
    if( $session->{store}->topicExists( $web, $statsTopic ) ) {
        ( $meta, $text ) = $session->{store}->readTopic( undef, $web, $statsTopic );
    } else {
        ( $meta, $text ) = $session->{store}->readTopic(
            undef, $TWiki::cfg{SystemWebName}, 'SiteStatisticsTemplate' );
        $text = $session->expandVariablesOnTopicCreation( $text, $session->{user} );
    }

    my $line;
    my @lines = split( /\r?\n/, $text );
    my $statLine;
    my $idxStat = -1;
    my $idxTmpl = -1;
    my $oldStats;
    for( my $x = 0; $x < @lines; $x++ ) {
        $line = $lines[$x];
        # Check for existing line for this month+year in new and legacy format
        if( $line =~ /^\| ($logYearMo|$logMonYear) / ) {
            my @items = split( / *\| */, $line );
            if( scalar @items >= 12 ) {
                $oldStats->{statWebs}        = $items[2];
                $oldStats->{statTopics}      = $items[5];
                $oldStats->{statAttachments} = $items[8];
                $oldStats->{statDataSize}    = $items[12];
                $oldStats->{statPubSize}     = $items[13];
                $oldStats->{statDiskUse}     = $items[14];
                $oldStats->{statUsers}       = $items[15];
                $oldStats->{statGroups}      = $items[16];
                $oldStats->{statPlugins}     = $items[17];
            }
            $idxStat = $x;
        } elsif( $line =~ /<\!\-\-statDate\-\->/ ) {
            $statLine = $line;
            $idxTmpl = $x;
        }
    }
    if( ! $statLine ) {
        $statLine = '| <!--statDate--> |  <!--statWebs--> | <!--statWebsViewed--> '
                  . '| <!--statWebsUpdated--> |  <!--statTopics--> '
                  . '|  <!--statTopicsViewed--> |  <!--statTopicsUpdated--> '
                  . '|  <!--statAttachments--> | <!--statViews--> | <!--statSaves--> '
                  . '| <!--statUploads--> |  <!--statDataSize--> |  <!--statPubSize--> '
                  . '|  <!--statDiskUse--> |  <!--statUsers--> |  <!--statGroups--> '
                  . '|  <!--statPlugins--> '
                  . '| <!--statTopViewers--> | <!--statTopContributors--> |';
    }

    # update statistics line with collected values
    $statLine =~ s/<\!\-\-([^\-]+)\-\->/$siteStats->{$1} || $oldStats->{$1} || 0/ge;

    if( $idxStat >= 0 ) {
        # entry already exists, need to update
        $lines[$idxStat] = $statLine;

    } elsif( $idxTmpl >= 0 ) {
        # entry does not exist, add after <!--statDate--> line
        $lines[$idxTmpl] = "$lines[$idxTmpl]\n$statLine";

    } else {
        # entry does not exist, add at the end
        $lines[@lines] = $statLine;
    }
    $text = join( "\n", @lines );
    $text .= "\n";
    $session->{store}->saveTopic( $session->{user}, $web, $statsTopic,
                                  $text, $meta,
                                  { minor => 1,
                                    dontlog => 1 } );

    _printMsg( $session, "  - Topic $web.$statsTopic updated" );
}

#===========================================================
sub _processWeb {
    my( $session, $web, $logYear, $logYearMo, $logMonYear, $stats, $webToSave )
        = @_;

    _printMsg( $session, "* Reporting on $web web" );

    my $ma = $TWiki::cfg{Stats}{TopAffiliation}; # max affiliations
    my $statViews   = _numberUniqueBreakdown('views',   $stats, $ma, $web);
    my $statSaves   = _numberUniqueBreakdown('saves',   $stats, $ma, $web);
    my $statUploads = _numberUniqueBreakdown('uploads', $stats, $ma, $web);
    _printMsg( $session,
               "  - view: " . _extractNumber($statViews) .
               ", save: "   . _extractNumber($statSaves) .
               ", upload: " . _extractNumber($statUploads) );
    
    # Get the top N views and contribs in this web
    my @topViews =
        _getTopList($TWiki::cfg{Stats}{TopViews}, $stats->{view}{$web});
    my @topViewers =
        _getTopList($TWiki::cfg{Stats}{TopContrib}, $stats->{viewer}{$web});
    my @topContribs =
        _getTopList($TWiki::cfg{Stats}{TopContrib}, $stats->{contrib}{$web});

    # Print information to stdout
    my $statTopViews = '';
    my $statTopViewers = '';
    my $statTopContributors = '';
    if( @topViews ) {
        $statTopViews = join( CGI::br(), @topViews );
        $topViews[0] =~ s/[\[\]]*//g;
        _printMsg( $session, '  - top view: '.$topViews[0] );
    }
    if( @topViewers ) {
        $statTopViewers = join( CGI::br(), @topViewers );
        $topViewers[0] =~ s/^.*\]\[([^\]]*).*$/$1/;
        _printMsg( $session, '  - top viewer: '.$topViewers[0] );
    }
    if( @topContribs ) {
        $statTopContributors = join( CGI::br(), @topContribs );
        $topContribs[0] =~ s/^.*\]\[([^\]]*).*$/$1/;
        _printMsg( $session, '  - top contributor: '.$topContribs[0] );
    }

    # Update the WebStatistics topic

    my $line;
    my $statsTopicTmpl = $TWiki::cfg{Stats}{TopicName};
    my $statsTopic = $statsTopicTmpl;
    $statsTopic .= $logYear if ( $TWiki::cfg{Stats}{TopicPerYear} );

    if ( $webToSave ) {
        $statsTopic = $web . $statsTopic;
    }
    else {
        $webToSave = $web;
    }
    my( $meta, $text );
    if( $session->{store}->topicExists( $webToSave, $statsTopic ) ) {
        ( $meta, $text ) = $session->{store}->readTopic( undef, $webToSave, $statsTopic );
    } else {
        ( $meta, $text ) = $session->{store}->readTopic( undef, '_default', $statsTopicTmpl );
    }
    unless( $text ) {
        _printMsg( $session, "  - WARNING: No updates done, topic $web.$statsTopic and"
                           . " _default.$statsTopic do not exist." );
        return;
    }

    my @lines = split( /\r?\n/, $text );
    my $statLine;
    my $idxStat = -1;
    my $idxTmpl = -1;
    for( my $x = 0; $x < @lines; $x++ ) {
        $line = $lines[$x];
        # Check for existing line for this month+year in new and legacy format
        if( $line =~ /^\| ($logYearMo|$logMonYear) / ) {
            $idxStat = $x;
        } elsif( $line =~ /<\!\-\-statDate\-\->/ ) {
             $statLine = $line;
             $idxTmpl = $x;
        }
    }
    if( ! $statLine ) {
        $statLine =
'| <!--statDate--> ' .
'| <!--statViews--> | <!--statSaves--> | <!--statUploads--> ' .
'| <!--statTopViews--> | <!--statTopViewers--> | <!--statTopContributors--> |';
    }
    $statLine =~ s/<\!\-\-statDate\-\->/$logYearMo/;
    $statLine =~ s/<\!\-\-statViews\-\->/$statViews/;
    $statLine =~ s/<\!\-\-statSaves\-\->/$statSaves/;
    $statLine =~ s/<\!\-\-statUploads\-\->/$statUploads/;
    $statLine =~ s/<\!\-\-statTopViews\-\->/$statTopViews/;
    $statLine =~ s/<\!\-\-statTopViewers\-\->/$statTopViewers/;
    $statLine =~ s/<\!\-\-statTopContributors\-\->/$statTopContributors/;

    if( $idxStat >= 0 ) {
        # entry already exists, need to update
        $lines[$idxStat] = $statLine;

    } elsif( $idxTmpl >= 0 ) {
        # entry does not exist, add after <!--statDate--> line
        $lines[$idxTmpl] = "$lines[$idxTmpl]\n$statLine";

    } else {
        # entry does not exist, add at the end
        $lines[@lines] = $statLine;
    }
    $text = join( "\n", @lines );
    $text .= "\n";
    unless ( $session->{store}->webExists($web) ) {
        # There is a chance for the web to be delete after the web list is
        # generated
        _printMsg( $session,
    "  - Topic $statsTopic not updated because the $web web has been deleted" );
        return;
    }
    $session->{store}->saveTopic( $session->{user}, $webToSave, $statsTopic,
                                  $text, $meta,
                                  { minor => 1,
                                    dontlog => 1 } );

    _printMsg( $session, "  - Topic $statsTopic updated" );
}

sub _itemLink {
    my ( $item, $isWeb ) = @_;
    if ( $isWeb ) {
        return "[[$item.WebHome][$item]]";
    }
    else {
        if ( $item =~ /^(.*)\.(.*)$/ ) {
            return "[[$item][$2]]";
        }
        else {
            return "[[$item]]";
        }
    }
}

#===========================================================
# Get the items with top N frequency counts
# Items can be topics (for view hash) or users (for contrib hash)
#===========================================================
sub _getTopList
{
    my( $theMaxNum, $itemsRef, $isWeb ) = @_;
    my $i = 0;
    my @list =
        grep { $i++ < $theMaxNum }
        map  { _nbsp($itemsRef->{$_} . ' ' . _itemLink($_, $isWeb)) }
        sort { $itemsRef->{$b} <=> $itemsRef->{$a} }
        keys %$itemsRef;
    @list = _alignNums(@list);
    return @list;
}

#===========================================================
sub _printMsg {
    my( $session, $msg ) = @_;

    if( $session->inContext('command_line') ) {
        $msg =~ s/&nbsp;/ /go;
        print $msg, "\n";
    } else {
        if( $msg =~ s/^\!// ) {
            $msg = CGI::h4( CGI::span( { class=>'twikiAlert' }, $msg ));
        } elsif( $msg =~ /^[A-Z]/ ) {
            # SMELL: does not support internationalised script messages
            $msg =~ s/^([A-Z].*)/CGI::h3($1)/ge;
        } else {
            $msg =~ s/(\*\*\*.*)/CGI::span( { class=>'twikiAlert' }, $1 )/ge;
            $msg =~ s/^\s\s/&nbsp;&nbsp;/go;
            $msg =~ s/^\s/&nbsp;/go;
            $msg .= CGI::br();
        }
        $msg =~ s/==([A-Z]*)==/'=='.CGI::span( { class=>'twikiAlert' }, $1 ).'=='/ge;
        $session->{response}->body( ($session->{response}->body || '') . $msg . "\n" );
    }
}

#===========================================================
1;
