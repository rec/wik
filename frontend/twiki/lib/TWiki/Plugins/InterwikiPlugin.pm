# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2003 Andrea Sterbini, a.sterbini@flashnet.it
# Copyright (C) 2001-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2008-2018 TWiki Contributor
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

=pod

---+ package TWiki::Plugins::InterwikiPlugin

Recognises and processes special links to other sites defined
using "inter-site syntax".

The recognized syntax is:
<pre>
       InterSiteName:TopicName
</pre>

Sites must start with upper case and must be preceded by white
space, '-', '*' or '(', or be part of the link expression
in a [[link]] or [[link][text]] expression.

=cut

# =========================
package TWiki::Plugins::InterwikiPlugin;

use strict;

require TWiki::Func;    # The plugins API
require TWiki::Plugins; # For the API version

# =========================
our $VERSION = '$Rev: 30454 (2018-07-16) $';
our $RELEASE = '2018-07-05';

# =========================
our $SHORTDESCRIPTION = 'Write ==ExternalSite:Page== to link to a page on an external site based on aliases defined in a rules topic';
our $NO_PREFS_IN_TOPIC = 1;
our $interWeb;
our $interLinkFormat;
our $sitePattern;
our $pagePattern;
our %interSiteTable;

# =========================
BEGIN {
    # 'Use locale' for internationalisation of Perl sorting and searching - 
    if( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale ();
    }
}

# =========================
sub initPlugin {
    my( $topic, $web, $user, $installWeb ) = @_;

    $interWeb = $installWeb;

    # check for Plugins.pm versions
    if( $TWiki::Plugins::VERSION < 1.026 ) {
        TWiki::Func::writeWarning( "Version mismatch between InterwikiPlugin and Plugins.pm" );
        return 0;
    }

    # Regexes for the Site:page format InterWiki reference
    my $man = TWiki::Func::getRegularExpression('mixedAlphaNum');
    my $ua = TWiki::Func::getRegularExpression('upperAlpha');
    $sitePattern    = "([$ua][$man]+)";
    $pagePattern    = "((?:'[^']*')|(?:\"[^\"]*\")|(?:[${man}\_\~\%\/][$man" . '\.\/\+\_\~\,\&\;\:\=\!\?\%\#\@\-]*?))';

    %interSiteTable = ();

    # Get plugin preferences from InterwikiPlugin topic
    $interLinkFormat =
      TWiki::Func::getPreferencesValue( 'INTERWIKIPLUGIN_INTERLINKFORMAT' ) ||
      _defaultFormat();

    my $interTopicList =
      TWiki::Func::getPreferencesValue( 'INTERWIKIPLUGIN_RULESTOPIC' ) || 'InterWikis';

    if ($interTopicList =~ /%/) {
        $interTopicList =
          TWiki::Func::expandCommonVariables($interTopicList, $topic, $web);
    }

    for my $interTopic (split /[,\s]+/, $interTopicList) {
        next if $interTopic eq '';

        my( $eachWeb, $eachTopic ) =
          TWiki::Func::normalizeWebTopicName( $interWeb, $interTopic );

        my $text = TWiki::Func::readTopicText( $eachWeb, $eachTopic, undef, 1 );

        # '| alias | URL | ...' table and extract into 'alias', "URL" list
        $text =~ s/^\|\s*$sitePattern\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|.*$/_map($1,$2,$3)/mego;
    }

    $sitePattern = "(" . join( "|", keys %interSiteTable ) . ")";
    return 1;
}

# =========================
sub _defaultFormat {
    if ( $TWiki::cfg{Links} ) {
        # Append external link icon correctly
        my $aTag = TWiki::Func::renderText('[[http://external][$label]]');
        $aTag =~ s{http://external}{\$url};
        $aTag =~ s{\$label}{<noautolink>\$label</noautolink>};
        $aTag =~ s{<(a\s+("[^"]*?"|'[^']*?'|[^"'>])*?)>}{<$1 title="\$tooltip" class="interwikiLink">}i;
        return $aTag;
    }
    else {
        # Fall back to plain link
        return '<a href="$url" title="$tooltip" class="interwikiLink"><noautolink>$label</noautolink></a>';
    }
}

sub _map {
    my( $site, $url, $tooltip ) = @_;
    if( $site ) {
        $interSiteTable{$site}{url} = $url || '';
        $interSiteTable{$site}{tooltip} = $tooltip || '';
    }
    return '';
}

# =========================
sub preRenderingHandler {
    # ref in [[ref]] or [[ref][
    $_[0] =~ s/(\[\[)$sitePattern:$pagePattern(\]\]|\]\[[^\]]+\]\])/_link($1,$2,$3,$4)/ge;
    # ref in text
    $_[0] =~ s/(^|[\s\-\*\(])$sitePattern:$pagePattern(?=[\s\.\,\;\:\!\?\)\|]*(\s|$))/_link($1,$2,$3)/ge;
}

# =========================
sub _link {
    my( $prefix, $site, $page, $postfix ) = @_;

    $prefix ||= '';
    $site ||= '';
    $page ||= '';
    $postfix ||= '';

    my $upage = $page;
    if( $page =~ /^['"](.*)["']$/ ) {
        $page = $1;
        $upage = TWiki::urlEncode( $1 );
    }

    my $text = $prefix;
    if( defined( $interSiteTable{$site} ) ) {
        my $tooltip = $interSiteTable{$site}{tooltip};
        my $url = $interSiteTable{$site}{url};
        my $label = "$site:$page";
        if( $site eq 'TWiki' ) {
            # TWikibug:Item6503 - hack to prettify TWiki.org link URL
            $upage =~ s/^([A-Za-z0-9]+)\./$1\//; # change first '.' to '/' 
        }
        if( $url =~ /\$page/ ) {
            $url =~ s/\$page/$upage/g;
        } else {
            $url .= $upage;
        }

        if( $postfix ) {
            # [[...]] or [[...][...]] interwiki link
            $text = '';
            if( $postfix =~ /^\]\[([^\]]+)/ ) {
                $label = $1;
            }
        }

        my $format = $interLinkFormat;
        $format =~ s/\$url/$url/g;
        $format =~ s/\$tooltip/$tooltip/g;
        $format =~ s/\$label/$label/g;
        $format =~ s/\$site/$site/g;
        $format =~ s/\$page/$page/g;
        $text .= $format;
    } else {
        $text .= "$site\:$upage$postfix";
    }
    return $text;
}

# =========================
1;
