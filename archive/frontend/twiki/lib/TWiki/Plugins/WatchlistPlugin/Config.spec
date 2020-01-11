# ---+ Extensions
# ---++ WatchlistPlugin

# **STRING 80**
# Format of one line of recently changed topics in the watchlist. Supported
# variables: $web: Name of web, $topic: Topic name, $title: Topic title or spaced
# topic name, $date: Date of last change, $rev: Last revision number, 
# $wikiname: WikiName of last user, $n or $n(): Newline.
$TWiki::cfg{Plugins}{WatchlistPlugin}{ChangesFormat} = '| [[$web.$topic][$title]] in <nop>$web web | [[%SCRIPTURL{rdiff}%/$web/$topic][$date]] - r$rev - [[$wikiname]] |';

# **STRING 80**
# Format of the header of the recently changed topic list. Supported variable:
# $n or $n(): Newline.
$TWiki::cfg{Plugins}{WatchlistPlugin}{ChangesHeader} = '| *Topic* | *Last Update* |';

# **STRING 80**
# Format of the footer of the recently changed topic list. Supported variable:
# $n or $n(): Newline.
$TWiki::cfg{Plugins}{WatchlistPlugin}{ChangesFooter} = '<div style="margin: 5px 0 0 3px;">Show %CALCULATE{$SET(limit, %URLPARAM{"limit" default="50"}%)$LISTJOIN(&#44; , $LISTMAP($IF($VALUE($GET(limit))==$item, <b>$item</b>, <a href="%SCRIPTURLPATH{"view"}%/%WEB%/%TOPIC%?limit=$item" rel="nofollow">$item</a>), 10, 20, 50, 100, 500, 1000))}% recent changes</div>';

# **STRING 80**
# Text shown in the recent changes and watchlist topics screen if no topics are watched.
$TWiki::cfg{Plugins}{WatchlistPlugin}{EmptyMessage} = 'The watchlist is empty. To watch topics, select the "Watch" menu item on topics of interest.';

# **STRING 80**
# Format of one topic in the digest notification e-mail. Supported variables:
# $web: Name of web, $topic: Topic name, $title: Topic title or spaced topic name,
# $date: Date of last change, $rev: Last revision number, $wikiname: WikiName of 
# last user, $viewscript: URL of view script, $n: newline
$TWiki::cfg{Plugins}{WatchlistPlugin}{NotifyTextFormat} = '- $topic in $web web, updated by $wikiname, $date, r$rev$n  $viewscript/$web/$topic$n$n';

# **BOOLEAN**
# Use the "Email" form field of user profile topic instead of the e-mail
# stored in the password system. This is useful if LDAP authentication is used.
$TWiki::cfg{Plugins}{WatchlistPlugin}{UseEmailField} = 0;

# **BOOLEAN**
# Log plugin actions. See output in data/logYYYYMM.txt
$TWiki::cfg{Plugins}{WatchlistPlugin}{LogAction} = 1;

# **BOOLEAN**
# Debug plugin. See output in data/debug.txt
$TWiki::cfg{Plugins}{WatchlistPlugin}{Debug} = 0;

1;
