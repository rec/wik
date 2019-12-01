# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2013-2015 Wave Systems Corp.
# Copyright (C) 2013-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2013-2018 TWiki Contributors
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

package TWiki::Plugins::WatchlistPlugin::Core;

use warnings;
use strict;

use TWiki::Func;

my $lowerAlpha;
my $upperAlpha;
my $numeric;
my $mixedAlphaNum = TWiki::Func::getRegularExpression('mixedAlphaNum');

my $debug           = $TWiki::cfg{Plugins}{WatchlistPlugin}{Debug} || 0;
my $watchedPreRegex = '[%]WATCHLIST\{ *"watched" +topics=" *';
my $watchedRegex    = '(' . $watchedPreRegex . ')([^"]*)';
my $prefsPreRegex   = '[%]WATCHLIST\{ *"preferences" +notification=" *';
my $prefsRegex      = '(' . $prefsPreRegex . ')([^"]*)';
my $webTopicRegex   = '[^' . $mixedAlphaNum . '_\-\.\/]';

# =========================
sub new {
    my ( $class, $baseWeb, $baseTopic ) = @_;

    my $this = {
        ChangesHeader => $TWiki::cfg{Plugins}{WatchlistPlugin}{ChangesHeader}
          || '| *Topic* | *Last Update* |',
        ChangesFormat => $TWiki::cfg{Plugins}{WatchlistPlugin}{ChangesFormat}
          || '| [[$web.$topic][$topic]] in <nop>$web web | $date - r$rev - [[$wikiname]] |',
        ChangesFooter => $TWiki::cfg{Plugins}{WatchlistPlugin}{ChangesFooter}
          || '<div style="margin: 5px 0 0 3px;">'
          . 'Show %CALCULATE{$SET(limit, %URLPARAM{"limit" '
          . 'default="50"}%)$LISTJOIN(&#44; , $LISTMAP($IF($VALUE($GET(limit))==$item, '
          . '<b>$item</b>, <a href="%SCRIPTURLPATH{"view"}%/%WEB%/%TOPIC%?limit=$item" '
          . 'rel="nofollow">$item</a>), 10, 20, 50, 100, 500, 1000))}% recent changes'
          . '</div>',
        EmptyMessage => $TWiki::cfg{Plugins}{WatchlistPlugin}{EmptyMessage}
          || 'The watchlist is empty. To watch topics, select the "Watch" menu item '
          . 'on topics of interest.',
        NotifyTextFormat =>
          $TWiki::cfg{Plugins}{WatchlistPlugin}{NotifyTextFormat}
          || '- $topic in $web web, updated by $wikiname, $date, r$rev$n'
          . '  $viewscript/$web/$topic$n$n',
        UseEmailField  => $TWiki::cfg{Plugins}{WatchlistPlugin}{UseEmailField},
        LogAction      => $TWiki::cfg{Plugins}{WatchlistPlugin}{LogAction},
        baseWeb        => $baseWeb,
        baseTopic      => $baseTopic,
        watchlistWeb   => $TWiki::cfg{UsersWebName},
        watchlistTopic => TWiki::Func::getWikiName() . 'Watchlist',
    };
    $this->{watchlistTopic} =~ /^(.*)$/;
    $this->{watchlistTopic} = $1;    # untaint
    bless( $this, $class );
    TWiki::Func::writeDebug("- WatchlistPlugin Core: Constructor") if $debug;

    # watched topics of logged in user
    $this->{watchedTopics} =
      $this->_getWatchedTopics( $this->{watchlistWeb},
        $this->{watchlistTopic} );

    # watch flag, indicating if base topic is beeing watched
    $this->{baseWatchFlag} = 0;
    if ( $this->{watchedTopics} =~ /\b$baseWeb\.$baseTopic\b/ ) {
        $this->{baseWatchFlag} = 1;
    }
    return $this;
}

# =========================
sub processAction {
    my $this = shift;

    my $query = TWiki::Func::getCgiQuery();
    if ( $query && ( my $action = $query->param('watchlist_action') ) ) {
        my $params;
        $params->{action} = $action;
        $this->VarWATCHLIST( undef, $params, $this->{baseTopic},
            $this->{baseWeb} );
    }

    return;
}

# =========================
sub VarWATCHLIST {
    my ( $this, $session, $params, $topic, $web ) = @_;

    my $query = TWiki::Func::getCgiQuery();
    my $action = $params->{_DEFAULT} || $params->{action} || 'showwatchlink';
    TWiki::Func::writeDebug("- WatchlistPlugin WATCHLIST: action=$action")
      if $debug;
    $this->{text}     = '';
    $this->{note}     = '';
    $this->{error}    = '';
    $this->{redirect} = '';

    if ( $action eq 'showwatchlink' ) {
        $this->_actionShowWatchLink($params);
    }
    elsif ( $action eq 'showwatchlistlink' ) {
        $this->_actionShowWatchlistLink( $web, $topic, $params );
    }
    elsif ( $action eq 'togglewatch' ) {
        $this->_actionToggleWatch($query);
    }
    elsif ( $action eq 'showchanges' ) {
        $this->_actionShowChanges( $web, $topic, $params, $query );
    }
    elsif ( $action eq 'watched' ) {
        $this->_actionShowWatchedTopics( $web, $topic, $params );
    }
    elsif ( $action eq 'updatelist' ) {
        $this->_actionUpdateWatchedTopics($query);
    }
    elsif ( $action eq 'preferences' ) {
        $this->_actionShowPreferences( $web, $topic, $params );
    }
    elsif ( $action eq 'updatepreferences' ) {
        $this->_actionUpdatePreferences($query);
    }

    if ( $this->{redirect} ) {
        my ( $rWeb, $rTopic, $rParams ) = split( /, */, $this->{redirect} );
        my $url = TWiki::Func::getScriptUrl( $rWeb, $rTopic, 'view' );
        $url .= '?' . $rParams if ($rParams);
        TWiki::Func::redirectCgiQuery( undef, $url, 0 );
    }

    my $text  = $this->{text};
    my $style = 'margin: 0 0.5em 0 0; padding: 0.3em 0.5em;';
    if ( $this->{note} ) {
        $text .=
            "<span style='background-color: #feffc2; $style'> "
          . $this->{note}
          . ( CGI::referer() ? " [[" . CGI::referer() . '][OK]] ' : '' )
          . "</span>";
    }
    if ( $this->{error} ) {
        $text .=
            "<span style='background-color: #ff9594; $style'> *Error:* "
          . $this->{error}
          . " [[$web.$topic][OK]] </span>";
    }
    return $text;
}

# =========================
sub beforeSaveHandler {

    # do not uncomment, use $_[0], $_[1]... instead
    ### my ( $this, $text, $topic, $web, $meta ) = @_;

    my $this  = shift;
    my $web   = $_[2];
    my $topic = $_[1];

    TWiki::Func::writeDebug(
        "- WatchlistPlugin: beforeSaveHandler( " . "$_[2].$_[1] )" )
      if $debug;

    # Prevent recursion
    my $query = TWiki::Func::getCgiQuery();
    return if ( $query && $query->param('watchlist_action') );

    push @{ $this->{exists} }, TWiki::Func::topicExists( $web, $topic ) || 0;

    return;
}

# =========================
sub afterSaveHandler {

    # do not uncomment, use $_[0], $_[1]... instead
    ### my ( $text, $topic, $web, $error, $meta ) = @_;
    my $this  = shift;
    my $web   = $_[2];
    my $topic = $_[1];    # May differ from beforeSave topic (e.g. autoinc)

    TWiki::Func::writeDebug( "- WatchlistPlugin: afterSaveHandler( "
          . "$_[2].$_[1] ) based on  $this->{baseWeb}.$this->{baseTopic}" )
      if $debug;

    # Prevent recursion
    my $query = TWiki::Func::getCgiQuery();
    return if ( $query && $query->param('watchlist_action') );

    my $newtopic = !pop @{ $this->{exists} } || 0;
    return if ( @{ $this->{exists} } );    # Recursing

    my $savingUser = TWiki::Func::getWikiName || '';
    my @topics = $this->_findWatchlistTopicsByWatchedTopic("$web.$topic");
    foreach
      my $wikiUser ( $this->_findWatchlistTopicsByPrefs( \@topics, 'n1' ) )
    {
        if ($newtopic) {
            my $ttext =
              TWiki::Func::readTopicText( $this->{watchlistWeb}, $wikiUser,
                undef, 1 );
            if ( $ttext && $ttext !~ /^http.*?\/oops/ ) {
                my $regex = $watchedPreRegex;
                $regex .= ".*\\b$web\\.##(?:\\b|[,\"])";
                if ( $ttext =~ /$regex/ ) {
                    if ( $ttext =~ s/$watchedRegex/$1$web.$topic, $2/ )
                    {    # at least Web.## exists, so safe to insert at front
                            # We know this topic exists, so this can't recurse.
                        TWiki::Func::saveTopicText( $this->{watchlistWeb},
                            $wikiUser, $ttext, 1, 1 );
                    }
                }
            }
        }
        $wikiUser =~ s/Watchlist$//;
        $this->_sendWatchlistEmail( $web, $topic, $wikiUser )
          unless ( $wikiUser eq $savingUser );
    }
    return;
}

# =========================
sub afterRenameHandler {
    my ( $this, $oldWeb, $oldTopic, $unused, $newWeb, $newTopic ) = @_;

    TWiki::Func::writeDebug( "- WatchlistPlugin: afterRenameHandler( "
          . "$_[0].$_[1] $_[2] -> $_[3].$_[4] $_[5] )" )
      if $debug;

    my $rmTopic  = "$oldWeb.$oldTopic";
    my $addTopic = "$newWeb.$newTopic";
    return if ( $rmTopic eq $addTopic );
    my $web = $this->{watchlistWeb};
    foreach my $topic ( $this->_findWatchlistTopicsByWatchedTopic($rmTopic) ) {
        $this->_updateWatchlistTopic( $web, $topic, $rmTopic, $addTopic, 1 );
    }
}

# =========================
# Digest notification, called by tools/watchlistnotify commandline script
# This method is designed to be invoked via the TWiki::UI::run method.

sub watchlistNotify {
    my ($this) = @_;

    TWiki::Func::writeDebug("- WatchlistPlugin: watchlistnotify()") if $debug;

    my $query   = TWiki::Func::getCgiQuery();
    my $verbose = 1;
    $verbose = 0
      if ( $query && ( $query->param('quiet') || $query->param('q') ) );

    my $workDir        = TWiki::Func::getWorkArea('WatchlistPlugin');
    my $lastUpdateFile = "$workDir/lastupdate.txt";
    my $lastUpdate     = TWiki::Func::readFile($lastUpdateFile) || 0;
    my $now            = time();
    TWiki::Func::saveFile( $lastUpdateFile, $now );
    print "WatchlistPlugin digest notification START at "
      . TWiki::Time::formatTime($now)
      . ", since "
      . TWiki::Time::formatTime($lastUpdate) . "\n"
      if ($verbose);
    my $web = $this->{watchlistWeb};
    my $viewScriptUrl = TWiki::Func::getViewUrl( 'WebName', 'TopicName' );
    $viewScriptUrl =~ s/.WebName.TopicName//o;    # cut web and topic
    my $webItrs;                                  # Cache changes in the webs
    my $webData;

    foreach my $topic ( $this->_findWatchlistTopicsByPrefs( undef, 'n2' ) )
    {    # Users wanting digest notification
        print "- processing $web.$topic\n" . "  - updated since last time: "
          if ($verbose);
        my $wikiUser = $topic;
        $wikiUser =~ s/Watchlist$//;
        my $dateRef;
        my $wTopics = $this->_getWatchedTopics( $web, $topic )
          ;    # Topics watched by this user
        foreach my $item ( split( /,\s*/, $wTopics ) ) {
            my ( $w, $t ) = $item =~ /^(.*)\.([^.]+)$/;
            unless ( $webItrs->{$w} ) {
                my $it = TWiki::Func::eachChangeSince( $w, $lastUpdate + 1 );
                $webItrs->{$w} = $it;
                while ( $it->hasNext() ) {
                    my $change = $it->next();
                    my $cTopic = $change->{topic};
                    next if $change->{more} && $change->{more} =~ /minor$/;
                    next unless TWiki::Func::topicExists( $w, $cTopic );
                    $webData->{$w}{$cTopic} = {
                        user => $change->{user},
                        time => $change->{time},
                        rev  => $change->{revision},
                      }
                      unless ( exists $webData->{$w}{$cTopic} )
                      ;    # Keep only most recent revision.
                }
            }
            next if ( $t eq '##' );    # Ignore new topic token
            if ( $t eq '#' ) {   # Watching entire web, match all changed topics
                next unless ( exists $webData->{$w} );
                foreach my $t ( keys %{ $webData->{$w} } ) {
                    if (   $webData->{$w}{$t}
                        && $webData->{$w}{$t}{user} ne $wikiUser )
                    {

                        # changed topic is watched, so add to date reference
                        $dateRef->{"$w~$t"} = $webData->{$w}{$t}{time};
                        print "$w.$t, " if ($verbose);
                    }
                }
                next;
            }
            if ( $webData->{$w}{$t} && $webData->{$w}{$t}{user} ne $wikiUser ) {

                # changed topic is watched, so add to date reference
                $dateRef->{"$w~$t"} = $webData->{$w}{$t}{time};
                print "$w.$t, " if ($verbose);
            }
        }

        my $size = scalar keys %$dateRef;
        if ( $size > 0 ) {
            print "-- total $size\n" if ($verbose);
            my $text      = '';
            my @webTopics = ();
            my $w;
            my $t;
            foreach my $item (
                sort { $dateRef->{$b} cmp $dateRef->{$a} }
                keys %$dateRef
              )
            {
                ( $w, $t ) = split( /~/, $item );
                push( @webTopics, "$w.$t" );
                my $d    = TWiki::Func::formatTime( $dateRef->{$item} );
                my $line = $this->{NotifyTextFormat};
                $line =~ s/\$web/$w/go;
                $line =~ s/\$topic/$t/go;
                $line =~ s/\$title/$this->_getTopicTitle( $w, $t )/geo;
                $line =~ s/\$date/$d/go;
                $line =~ s/\$rev/$webData->{$w}{$t}{rev}/go;
                $line =~ s/\$wikiname/$webData->{$w}{$t}{user}/go;
                $line =~ s/\$viewscript/$viewScriptUrl/go;
                $line =~ s/\$n/\n/go;
                $text .= $line;
                print "$line" if ($verbose);
            }
            $text =~ s/[\r\n]*$//s;

            # Notify user
            my $topicList = join( ', ', sort @webTopics );
            $this->_sendWatchlistEmail( $w, $t, $wikiUser, $text, $topicList );
        }
        else {
            print "(none)\n" if ($verbose);
        }
    }
    print "WatchlistPlugin digest notification END at "
      . TWiki::Time::formatTime( time() ) . "\n"
      if ($verbose);
    return;
}

# =========================
sub _actionShowWatchLink {
    my ( $this, $params ) = @_;
    my $format = $params->{format} || '[[$url][$watch]]';
    my $url = '%SCRIPTURL{viewauth}%/%BASEWEB%/%BASETOPIC%'
      . '?watchlist_action=togglewatch;watchlist_topic=%BASEWEB%.%BASETOPIC%';
    $format =~ s/\$url/$url/go;
    my $watch = $this->{baseWatchFlag} ? 'Unwatch' : 'Watch';
    $format =~ s/\$watch/$watch/g;
    $this->{text} .= $format;
}

# =========================
sub _actionShowWatchlistLink {
    my ( $this, $web, $topic, $params ) = @_;
    my $format = $params->{format} || '[[$url][Watchlist Changes]]';

    my $wikiName = $topic;
    my $context  = TWiki::Func::getContext();
    if ( $params->{wikiname} ) {
        $wikiName = $params->{wikiname};
    }
    elsif ( $context->{authenticated} ) {
        $wikiName = TWiki::Func::getWikiName();
    }
    $wikiName =~ s/Watchlist$//;
    $web   = $this->{watchlistWeb};
    $topic = $wikiName . 'Watchlist';
    my $url = '%SCRIPTURL{view}%/' . "$web/$topic";
    unless ( TWiki::Func::topicExists( $web, $topic ) ) {
        $url =
            '%SCRIPTURL{viewauth}%/'
          . "$web/$topic?createifnotexist=1"
          . ';templatetopic=%SYSTEMWEB%.WatchlistTemplate;topicparent='
          . $wikiName;
    }
    $format =~ s/\$url/$url/go;
    $format =~ s/\$wikiname/$wikiName/go;
    my $watch = $this->{baseWatchFlag} ? 'Unwatch' : 'Watch';
    $format =~ s/\$watch/$watch/g;
    $this->{text} .= $format;
}

# =========================
sub _actionToggleWatch {
    my ( $this, $query ) = @_;
    my ( $web, $topic ) =
      $this->_sanitizeWebTopic( $query->param('watchlist_topic') );
    return unless ($topic);
    my $wWeb   = $this->{watchlistWeb};
    my $wTopic = $this->{watchlistTopic};
    unless ( TWiki::Func::topicExists( $wWeb, $wTopic ) ) {

        # watchlist topic does not exist, so create it
        my ( $meta, $text ) =
          TWiki::Func::readTopic( $TWiki::cfg{SystemWebName},
            'WatchlistTemplate' );
        $text = TWiki::Func::expandVariablesOnTopicCreation($text);
        $meta->put( 'TOPICPARENT', { name => TWiki::Func::getWikiName() } );
        TWiki::Func::saveTopic( $wWeb, $wTopic, $meta, $text, { minor => 1 } );
    }
    $this->_updateWatchlistTopic( $wWeb, $wTopic, "$web.$topic", '', 1 );
    $this->{redirect} = "$web, $topic";
}

# =========================
sub _actionShowChanges {
    my ( $this, $web, $topic, $params, $query ) = @_;

    my $header    = $params->{header}    || $this->{ChangesHeader};
    my $format    = $params->{format}    || $this->{ChangesFormat};
    my $footer    = $params->{footer}    || $this->{ChangesFooter};
    my $separator = $params->{separator} || "\n";
    my $limit     = $params->{limit}     || 50;
    $limit = $query->param('limit') if ( $query && $query->param('limit') );
    if ( $params->{format} ) {
        $header = '' unless ( $params->{header} );
        $footer = '' unless ( $params->{footer} );
    }
    $header    =~ s/\$n(\(\)|\b)/\n/go;
    $format    =~ s/\$n(\(\)|\b)/\n/go;
    $footer    =~ s/\$n(\(\)|\b)/\n/go;
    $separator =~ s/\$n(\(\)|\b)/\n/go;
    if ( $params->{wikiname} ) {
        $topic = $params->{wikiname};
        $topic = $this->{watchlistWeb} . '.' . $topic unless ( $topic =~ /\./ );
    }
    $topic .= 'Watchlist' unless ( $topic =~ /Watchlist$/ );
    ( $web, $topic ) = TWiki::Func::normalizeWebTopicName( $web, $topic );
    my $watchedTopics = $this->_getWatchedTopics( $web, $topic );
    if ($watchedTopics) {
        my $dateRef;
        my $userRef;
        my $revRef;
        foreach my $item ( split( /, */, $watchedTopics ) ) {
            my ( $w, $t ) = TWiki::Func::normalizeWebTopicName( $web, $item );
            next if ( $t eq '##' );
            if ( $t eq '#' ) {
                next unless ( TWiki::Func::webExists($w) );
                foreach my $t ( TWiki::Func::getTopicList($w) ) {
                    my ( $date, $user, $rev ) =
                      TWiki::Func::getRevisionInfo( $w, $t );
                    $dateRef->{"$w~$t"} = $date;
                    $userRef->{"$w~$t"} = $user;
                    $revRef->{"$w~$t"}  = $rev;
                }
                next;
            }
            next unless ( TWiki::Func::topicExists( $w, $t ) );
            my ( $date, $user, $rev ) = TWiki::Func::getRevisionInfo( $w, $t );
            $dateRef->{"$w~$t"} = $date;
            $userRef->{"$w~$t"} = $user;
            $revRef->{"$w~$t"}  = $rev;
        }
        $this->{text} .= $header . $separator if ($header);
        foreach
          my $item ( sort { $dateRef->{$b} cmp $dateRef->{$a} } keys %$dateRef )
        {
            last unless ( $limit-- );
            my ( $w, $t ) = split( /~/, $item );
            my $d    = TWiki::Func::formatTime( $dateRef->{$item} );
            my $line = $format;
            $line =~ s/\$web/$w/go;
            $line =~ s/\$topic/$t/go;
            $line =~ s/\$title/$this->_getTopicTitle( $w, $t )/geo;
            $line =~ s/\$date/$d/go;
            $line =~ s/\$rev/$revRef->{$item}/go;
            $line =~ s/\$wikiname/$userRef->{$item}/go;
            $line =~ s/\$percnt/%/go;
            $this->{text} .= $line . $separator;
        }
        if ($footer) {
            $this->{text} .= $footer;
        }
        else {
            $this->{text} =~ s/$separator$//s;    # remove trailing separator;
        }

    }
    elsif ( $params->{empty} ) {
        my $empty = $params->{empty};
        $empty =~ s/\$percnt/%/go;
        $this->{text} .= $empty;
    }
    else {
        $this->{note} .= $this->{EmptyMessage};
    }
    return;
}

# =========================
sub _actionShowWatchedTopics {
    my ( $this, $web, $topic, $params ) = @_;
    my $watchedTopics = $params->{topics};
    $watchedTopics =~ s/^\s+//s;
    $watchedTopics =~ s/\s+$//s;
    $watchedTopics = join(
        ', ',
        sort
          grep {
            /^(.*)\.##?$/
              ? TWiki::Func::webExists($1)
              : TWiki::Func::topicExists( $web, $_ )
          }
          split( /[\s,]+/, $watchedTopics )
    );
    my %webs =
      map { $_ => 1 }
      grep { $_ !~ /^(?:$TWiki::cfg{TrashWebName})$/ }
      TWiki::Func::getListOfWebs( 'user, allowed' );

    $this->{text} .= (
q(<div style="font-size:90%; margin-bottom:.5em;">
%TWISTY{
 mode="div"
 showlink="Instructions %ICONURL{toggleopen}%"
 hidelink="Hide instructions %ICONURL{toggleclose}%"
}%
   * %MAKETEXT{"To unwatch multiple topics, uncheck the topics, then click *Update Watchlist*."}%
   * %MAKETEXT{"To watch all topics in a web, check the *All* checkbox, then click *Update Watchlist*."}%
   * %MAKETEXT{"To have new topics added to your watchlist automatically, check the *New* checkbox, then click *Update Watchlist*."}%
   * %MAKETEXT{"To add a topic to the list, visit it and click *Watch* on the menu bar."}%
%ENDTWISTY%
</div> 
)
          . '<form action="%SCRIPTURLPATH{viewauth}%/'
          . "$web/$topic\""
          . ' id="watchlist_topics" method="post">'
          . "\n" );
    my $context = TWiki::Func::getContext();
    my $header = "| <div style='width:25em;'><b>Webs and watched topics:</b></div> | <b>Options:</b> ||\n"; 
    my $first = 1;
    if ($watchedTopics) {
        my $currentWeb = '';
        my @items = split( /, */, $watchedTopics );
        while (@items) {
            my $item = shift @items;
            my ( $w, $t ) = TWiki::Func::normalizeWebTopicName( $web, $item );
            if( $first ) {
                $this->{text} .= '%TABLE{ sort="off" dataalign="left" headeralign="left"'
                  . 'headerrows="1" footerrows="2"}%' . "\n" if( $context->{TablePluginEnabled} );
                $this->{text} .= $header;
                $first = 0;
            }
            if ( $w ne $currentWeb ) {
                delete $webs{$w};
                $this->{text} .=
                  '| *<img src="%ICONURL{web-bg}%" border="0" alt="Web color" '
                  . 'width="16" height="16" style="background-color:%VAR{"WEBBGCOLOR" '
                  . "web=\"$w\"}%\" /> <nop>$w:*";
                $currentWeb = $w;
                $this->{text} .= ' | *<noautolink>'
                  . '<label><input type="checkbox" name="watchlist_all" value="'
                  . "$w.#"
                  . '" title="Watch all topics in the '
                  . $w . ' web"';
                if ( $t eq '#' ) {
                    $this->{text} .= ' checked="checked"';
                }
                $this->{text} .= " /> All </label>* |"
                  . ' *<label><input type="checkbox" name="watchlist_new" value="'
                  . "$w.##"
                  . '" title="Watch new topics in the '
                  . $w . ' web"';
                if ( @items && $items[0] =~ /^$w\.##$/ ) {
                    $t = '##';
                    shift @items;
                }
                if ( $t eq '##' ) {
                    $this->{text} .= ' checked="checked"';
                }
                $this->{text} .= " /> New </label></autolink>* |\n";
                next if ( $t =~ /^##?$/ );
            }

            $this->{text} .=
                '| <label> %ICON{empty}% <input type="checkbox" name="watchlist_item" '
              . "value=\"$w.$t\" checked=\"checked\" /> "
              . "[[$w.$t][$t]] </label> |||\n";
        }
    }
    foreach my $web ( sort keys %webs ) {
        if( $first ) {
            $this->{text} .= '%TABLE{ sort="off" dataalign="left" headeralign="left"' 
              . 'headerrows="1" footerrows="2"}%' . "\n" if( $context->{TablePluginEnabled} );
            $this->{text} .= $header;
            $first = 0;
        }
        $this->{text} .= '|  *<noautolink><img src="%ICONURL{web-bg}%" border="0" alt="Web color" '
          . 'width="16" height="16" style="background-color:%VAR{"WEBBGCOLOR" '
          . "web=\"$web\"}%\" /> <nop>$web*";
        $this->{text} .=
            '   | *<label><input type="checkbox" name="watchlist_all" value="'
          . "$web.#"
          . '" title="Watch all topics in the '
          . $web
          . ' web" /> All </label>* |';
        $this->{text} .=
            ' *<label><input type="checkbox" name="watchlist_new" value="'
          . "$web.##"
          . '" title="Watch new topics in the '
          . $web
          . ' web" /> New </label></noautolink>*' . " |\n";
    }
    if ($first) {
        $this->{note} .= $this->{EmptyMessage};
    }
    else {
        $this->{text} .= '| *';
        if ($watchedTopics) {
            $this->{text} .=
q(<div style="font-size:90%;">%ICON{empty}% <input type="button" value="%MAKETEXT{"Clear all"}%" class="twikiButton" title="Deselect all watched topics" onclick="$('[name=\&quot;watchlist_item\&quot;]').attr('checked', false);" /> &nbsp; <input type="button" value="%MAKETEXT{"Set all"}%" class="twikiButton" title="Select all watched topics" onclick="$('[name=\&quot;watchlist_item\&quot;]').attr('checked', true);" /></div>*);
        }
        else {
            $this->{text} .= '&nbsp;*';
        }
        $this->{text} .=
q( | *<label><input type="checkbox" title="Select all webs" checked="checked" onchange="$('[name=\&quot;watchlist_all\&quot;]').attr('checked',!this.checked);this.title=(this.checked? 'Select all webs':'Deselect all webs');return true;" /> All </label>* | *<label><input type="checkbox" title="Select all new topics" checked="checked" onchange="$('[name=\&quot;watchlist_new\&quot;]').attr('checked',!this.checked);this.title=(this.checked? 'Select all new topics':'Deselect all new topics');return true;" /> New </label>* |);
        $this->{text} .= "\n"
          . '| <input type="hidden" name="watchlist_topic" value="'
          . "$web.$topic\" />"
          . '<input type="hidden" name="watchlist_action" value="updatelist" />'
          . '<input type="submit" value="Update Watchlist" '
          . 'class="twikiSubmit" /> |||' . "\n";
    }
    $this->{text} .= "</form>";

    return;
}

# =========================
sub _actionUpdateWatchedTopics {
    my ( $this, $query ) = @_;

    my ( $web, $topic ) =
      $this->_sanitizeWebTopic( $query->param('watchlist_topic') );
    return unless ($topic);
    my $watchedTopics = join(
        ', ',
        sort( $query->param('watchlist_item'), $query->param('watchlist_new'),
            $query->param('watchlist_all') )
    ) || '';
    $this->_writeLog( "Update watchlist to: $watchedTopics", $web, $topic );
    $this->_saveWatchedTopics( $web, $topic, $watchedTopics );
    $this->{redirect} = "$web, $topic";
}

# =========================
sub _actionShowPreferences {
    my ( $this, $web, $topic, $params ) = @_;
    my $notification = $params->{notification} || 'n0';
    $this->{text} .=
        '<form action="%SCRIPTURLPATH{viewauth}%/'
      . "$web/$topic\""
      . ' id="watchlist_topics" method="get">' . "\n"
      . '| E-mail notification: | '
      . '<label> <input type="radio" name="notification" value="n0"';
    $this->{text} .= ' checked="checked"'
      unless ( $notification =~ /^n[1-9]$/ );
    $this->{text} .= '/> None %GRAY% - watchlist only %ENDCOLOR% </label> '
      . '%BR% <label> <input type="radio" name="notification" value="n1"';
    $this->{text} .= ' checked="checked"' if ( $notification eq 'n1' );
    $this->{text} .=
        '/> Immediate %GRAY% - get notified on each topic change '
      . 'on watchlist. %ENDCOLOR% </label>'
      . '%BR% <label> <input type="radio" name="notification" value="n2"';
    $this->{text} .= ' checked="checked"' if ( $notification eq 'n2' );
    $this->{text} .=
        '/> Digest %GRAY% - get notified of topic changes on watchlist'
      . ' in batch mode once a day. %ENDCOLOR% </label> |' . "\n"
      . '|  | <input type="submit" value="Save Preferences" class="twikiSubmit" /> |'
      . "\n"
      . '<input type="hidden" name="watchlist_topic" value="'
      . "$web.$topic\" />\n"
      . '<input type="hidden" name="watchlist_action" value="updatepreferences" />'
      . "\n</form>";
}

# =========================
sub _actionUpdatePreferences {
    my ( $this, $query ) = @_;
    my ( $web, $topic ) =
      $this->_sanitizeWebTopic( $query->param('watchlist_topic') );
    return unless ($topic);
    my $notification = $query->param('notification') || 'n0';

    unless ( TWiki::Func::topicExists( $web, $topic ) ) {
        $this->{error} .= "Watchlist topic <nop>$web.$topic does not exist.";
        return;
    }
    my $text = TWiki::Func::readTopicText( $web, $topic, undef, 1 );
    $text ||= '';
    unless ( $text =~ s/$prefsRegex/$1$notification/ ) {
        $this->{error} .=
          "Watchlist topic <nop>$web.$topic does not have a WATCHLIST.";
        return;
    }
    $this->_writeLog( "Notify preference: $notification", $web, $topic );
    TWiki::Func::saveTopicText( $web, $topic, $text, 0, 1 );
    $this->{redirect} = "$web, $topic";
}

# =========================
sub _findWatchlistTopicsByWatchedTopic {
    my ( $this, $webTopic ) = @_;

    # All watchlist topics:
    my $web = $this->{watchlistWeb};
    my @topics = grep { /Watchlist$/ } TWiki::Func::getTopicList($web);

    # Reduce watchlist topics to those that have the "Web.Topic", "Web.#", or "Web.##":
    my $regex = $watchedPreRegex;
    my ( $w ) = $webTopic =~ /^(.*)\.[^.]*$/;
    $w        =~ s/\./\\./g;
    $webTopic =~ s/\./\\./g;
    $regex .= ".*\\b($webTopic\\b|$w\\.##?(\\b|[,\"]))";
    my $result =
      TWiki::Func::searchInWebContent( $regex, $web, \@topics,
        { type => 'regex' } );
    return sort ( keys %$result );
}

# =========================
sub _findWatchlistTopicsByPrefs {
    my ( $this, $topicRef, $notify ) = @_;

    # All watchlist topics:
    my $web = $this->{watchlistWeb};
    unless ($topicRef) {
        my @topics = grep { /Watchlist$/ } TWiki::Func::getTopicList($web);
        $topicRef = \@topics;
    }

# Reduce watchlist topics to those that have the "$notify" type (immed,digest,etc) preference:
    my $regex = $prefsPreRegex . ".*\\b$notify\\b";
    my $result =
      TWiki::Func::searchInWebContent( $regex, $web, $topicRef,
        { type => 'regex' } );
    return sort ( keys %$result );
}

# =========================
sub _getWatchedTopics {
    my ( $this, $web, $topic ) = @_;
    my $watchedTopics = '';
    my $text = TWiki::Func::readTopicText( $web, $topic, undef, 1 );
    return '' unless ( $text && $text =~ /$watchedRegex/ );
    $watchedTopics = $2;
    $watchedTopics =~ s/\s+$//s;
    $watchedTopics = join( ', ', sort split( /[\s,]+/, $watchedTopics ) );
    return $watchedTopics;
}

# =========================
sub _updateWatchlistTopic {
    my ( $this, $web, $topic, $rmTopic, $addTopic, $ignorePermissions ) = @_;
    unless ( TWiki::Func::topicExists( $web, $topic ) ) {
        $this->{error} .= "Watchlist topic <nop>$web.$topic does not exist.";
        return;
    }
    my $text = TWiki::Func::readTopicText( $web, $topic, undef, 1 );
    $text ||= '';
    my $marker = '__W-A-T-C-H-E-D--T-O-P-I-C-S__';
    unless ( $text =~ s/$watchedRegex/$1$marker/ ) {
        $this->{error} .=
          "Watchlist topic <nop>$web.$topic does not have a WATCHLIST.";
        return;
    }
    my $watchedTopics = $2;
    $watchedTopics =~ s/\s+$//s;
    my @arr = sort split( /[\s,]+/, $watchedTopics );
    my $rmFound = scalar grep { /^$rmTopic$/ } @arr;
    return if ( !$rmFound && $addTopic );
    if ( !$rmFound && !$addTopic ) {

        # toggle
        $addTopic = $rmTopic;
        $rmTopic  = '';
    }
    $addTopic = ''
      if ( $addTopic =~ /^$TWiki::cfg{TrashWebName}/ );    # Report error?
    my $logInfo = 'Change watchlist:';
    $logInfo .= " Remove $rmTopic" if ($rmTopic);
    $logInfo .= " &"               if ( $rmTopic && $addTopic );
    $logInfo .= " Add $addTopic"   if ($addTopic);
    $this->_writeLog( $logInfo, $web, $topic );
    TWiki::Func::writeDebug(
        "- WatchlistPlugin: $logInfo" . " In '$watchedTopics' of $web.$topic" )
      if $debug;
    push( @arr, $addTopic ) if ($addTopic);
    $watchedTopics = join( ', ', grep { !/^$rmTopic$/ } @arr );
    $text =~ s/$marker/$watchedTopics/;
    TWiki::Func::saveTopicText( $web, $topic, $text, $ignorePermissions, 1 );
}

# =========================
sub _saveWatchedTopics {
    my ( $this, $web, $topic, $watchedTopics ) = @_;
    unless ( TWiki::Func::topicExists( $web, $topic ) ) {
        $this->{error} .= "Watchlist topic <nop>$web.$topic does not exist.";
        return;
    }
    my $text = TWiki::Func::readTopicText( $web, $topic, undef, 1 );
    $text ||= '';
    unless ( $text =~ s/$watchedRegex/$1$watchedTopics/ ) {
        $this->{error} .=
          "Watchlist topic <nop>$web.$topic does not have a WATCHLIST.";
        return;
    }
    TWiki::Func::saveTopicText( $web, $topic, $text, 0, 1 );
}

# =========================
sub _sanitizeWebTopic {
    my ( $this, $text ) = @_;
    $text ||= '';
    $text =~ s/$webTopicRegex//go;
    unless ( $text =~ /^(.+)\.(.+)$/ ) {
        $this->{error} =
            "Can't update watchlist topic, inproper use of parameters"
          . " (watchlist_topic is missing)";
        return ( '', '' );
    }
    return ( $1, $2 );
}

# =========================
sub _getTopicTitle {
    my ( $this, $web, $topic ) = @_;

    # For title, use TOPICTITLE if available, else space out topic name
    my $rawTitle = "%TOPICTITLE{ topic=\"$web.$topic\" }%";
    my $title = TWiki::Func::expandCommonVariables( $rawTitle, $topic, $web );
    if ( $title eq $rawTitle || $title eq $topic || !$title ) {
        $title = TWiki::Func::spaceOutWikiWord($topic);
    }
    return $title;
}

# =========================
sub _sendWatchlistEmail {
    my ( $this, $web, $topic, $wikiUser, $textChanges, $topicList ) = @_;

    my @emails = ();
    if ( $this->{UseEmailField} ) {

        # Get e-mails from Email form field of user profile topics
        my $w = $this->{watchlistWeb};
        my $t = "%FORMFIELD{ \"Email\" topic=\"$w.$wikiUser\" }%";
        @emails =
          map { $_ = "$wikiUser <$_>"; $_; }
          split(
            /[,;]\s*/,
            TWiki::Func::expandCommonVariables(
                $t, $wikiUser, $this->{watchlistWeb}
            )
          );

    }
    else {

        # Get e-mails from password system
        foreach my $mail ( TWiki::Func::wikinameToEmails($wikiUser) ) {
            push( @emails, "$wikiUser <$mail>" );
        }
    }
    my $toEmails = join( ', ', @emails );

    # Read template & compose e-mail
    my $text    = '';
    my $logInfo = '';
    if ($topicList) {

        # Digest notification
        my $template = 'watchlistdigestnotify';    # FIXME: Config value
        $text = TWiki::Func::readTemplate($template);
        $text =~ s/%WATCHCHANGESTEXT%/$textChanges/go;
        $logInfo = "Digest notify: $toEmails; changed topics: $topicList";

    }
    else {

        # Immediate notification
        my $template = 'watchlistimmediatenotify';    # FIXME: Config value
        $text = TWiki::Func::readTemplate($template);
        my $info = "%REVINFO{ web=\"$web\" topic=\"$topic\" "
          . 'format="$wikiname, $rev, $date - $time" }%';
        $info = TWiki::Func::expandCommonVariables( $info, $topic, $web );
        my ( $watchUser, $watchRev, $watchDate ) = split( /, /, $info );
        $text =~ s/%WATCHTITLE%/$this->_getTopicTitle( $web, $topic )/geo;
        $text =~ s/%WATCHUSER%/$watchUser/go;
        $text =~ s/%WATCHREV%/$watchRev/go;
        $text =~ s/%WATCHDATE%/$watchDate/go;
        $logInfo = "Immediate notify: $toEmails";
    }
    $text =~ s/%WATCHLISTUSER%/$wikiUser/go;
    $text =~ s/%WATCHLISTTO%/$toEmails/go;
    $text =~ s/%WATCHWEB%/$web/go;
    $text =~ s/%WATCHTOPIC%/$topic/go;
    $text = TWiki::Func::expandCommonVariables( $text, $topic, $web );

    # Log and debug output
    $this->_writeLog( $logInfo, $web, $topic, $wikiUser );
    TWiki::Func::writeDebug("- WatchlistPlugin: $logInfo") if ($debug);

    # Send e-mail
    TWiki::Func::writeDebug("- WatchlistPlugin: Email\n=====\n$text\n=====")
      if $debug;
    $this->{error} = TWiki::Func::sendEmail($text);

    return;
}

# =========================
sub _writeLog {
    my ( $this, $extra, $web, $topic, $wikiUser ) = @_;
    if ( $this->{LogAction} && $TWiki::Plugins::VERSION >= 1.4 ) {
        TWiki::Func::writeLog( 'watchlist', $extra, $web, $topic, $wikiUser );
    }
}

# =========================
1;
