# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2006-2018 TWiki Contributors. All Rights Reserved.
# TWiki Contributors are listed in the AUTHORS file in the root of
# this distribution. NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
#
# Based on parts of Ward Cunninghams original Wiki and JosWiki.
# Copyright (C) 1998 Markus Peter - SPiN GmbH (warpi@spin.de)
# Some changes by Dave Harris (drh@bhresearch.co.uk) incorporated
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

package TWiki;

=pod

---+ package TWiki

TWiki operates by creating a singleton object (known as the Session
object) that acts as a point of reference for all the different
modules in the system. This package is the class for this singleton,
and also contains the vast bulk of the basic constants and the per-
site configuration mechanisms.

Global variables are avoided wherever possible to avoid problems
with CGI accelerators such as mod_perl.

---+++!! Public Data members
   * =request=          Pointer to the TWiki::Request
   * =response=         Pointer to the TWiki::Respose
   * =context=          Hash of context ids
   * moved: =loginManager=     TWiki::LoginManager singleton (moved to TWiki::Users)
   * =plugins=          TWiki::Plugins singleton
   * =prefs=            TWiki::Prefs singleton
   * =remoteUser=       Login ID when using ApacheLogin. Maintained for
                        compatibility only, do not use.
   * =requestedWebName= Name of web found in URL path or =web= URL parameter
   * =sandbox=          TWiki::Sandbox singleton
   * =scriptUrlPath=    URL path to the current script. May be dynamically
                        extracted from the URL path if {GetScriptUrlFromCgi}.
                        Only required to support {GetScriptUrlFromCgi} and
                        not consistently used. Avoid.
   * =security=         TWiki::Access singleton
   * =SESSION_TAGS=     Hash of TWiki variables whose value is specific to
                        the current request.
   * =store=            TWiki::Store singleton
   * =topicName=        Name of topic found in URL path or =topic= URL
                        parameter
   * =urlHost=          Host part of the URL (including the protocol)
                        determined during intialisation and defaulting to
                        {DefaultUrlHost}
   * =user=             Unique user ID of logged-in user
   * =users=            TWiki::Users singleton
   * =webName=          Name of web found in URL path, or =web= URL parameter,
                        or {UsersWebName}

=cut

use strict;
use Assert;
use Error qw( :try );
use CGI;
$CGI::LIST_CONTEXT_WARN = 0;
use TWiki::Response;
use TWiki::Request;
use TWiki::Time;

require 5.010001;  # Perl 5.10.1

# Site configuration constants
use vars qw( %cfg );

# Uncomment this and the __END__ to enable AutoLoader
#use AutoLoader 'AUTOLOAD';
# You then need to autosplit TWiki.pm:
# cd lib
# perl -e 'use AutoSplit; autosplit("TWiki.pm", "auto")'

# Other computed constants
use vars qw(
      $TranslationToken
      $percentSubstitute
      $twikiLibDir
      %regex
      %functionTags
      %contextFreeSyntax
      %restDispatch
      $VERSION $RELEASE
      $TRUE
      $FALSE
      $sandbox
      $engine
      $ifParser
      %scriptOnMaster
      %httpHiddenField
    );

# Token character that must not occur in any normal text - converted
# to a flag character if it ever does occur (very unlikely)
# TWiki uses $TranslationToken to mark points in the text. This is
# normally \0, which is not a useful character in any 8-bit character
# set we can find, nor in UTF-8. But if you *do* encounter problems
# with it, the workaround is to change $TranslationToken to something
# longer that is unlikely to occur in your text - for example
# muRfleFli5ble8leep (do *not* use punctuation characters or whitspace
# in the string!)
# See Codev.NationalCharTokenClash for more.
$TranslationToken= "\0";

# Hack to substitute a % into a non-printable character so that a
# search string can be passed from URLPARAM to SEARCH without variable
# expansion, e.g. for a literal search.
# (TWiki:Codev.NewModeSearchEncodingInENCODEandURLPARAM & Item7847)
$percentSubstitute = "\x1a";

=pod

---++ StaticMethod getTWikiLibDir() -> $path

Returns the full path of the directory containing TWiki.pm

=cut

sub getTWikiLibDir {
    if( $twikiLibDir ) {
        return $twikiLibDir;
    }

    # FIXME: Should just use $INC{"TWiki.pm"} to get path used to load this
    # module.
    my $dir = '';
    foreach $dir ( @INC ) {
        if( $dir && -e "$dir/TWiki.pm" ) {
            $twikiLibDir = $dir;
            last;
        }
    }

    # fix path relative to location of called script
    if( $twikiLibDir =~ /^\./ ) {
        print STDERR "WARNING: TWiki lib path $twikiLibDir is relative; you should make it"
                   . " absolute, otherwise some scripts may not run from the command line.";
        my $bin;
        # TSA SMELL : Should not assume environment variables and get data from request
        if( $ENV{SCRIPT_FILENAME} &&
            $ENV{SCRIPT_FILENAME} =~ /^(.+)\/[^\/]+$/ ) {
            # CGI script name
            $bin = $1;
        } elsif ( $0 =~ /^(.*)\/.*?$/ ) {
            # program name
            $bin = $1;
        } else {
            # last ditch; relative to current directory.
            require Cwd;
            import Cwd qw( cwd );
            $bin = cwd();
        }
        $twikiLibDir = "$bin/$twikiLibDir/";
        # normalize "/../" and "/./"
        while ( $twikiLibDir =~ s|([\\/])[^\\/]+[\\/]\.\.[\\/]|$1| ) {
        };
        $twikiLibDir =~ s|([\\/])\.[\\/]|$1|g;
    }
    $twikiLibDir =~ s|([\\/])[\\/]*|$1|g; # reduce "//" to "/"
    $twikiLibDir =~ s|[\\/]$||;           # cut trailing "/"

    return $twikiLibDir;
}

BEGIN {
    require TWiki::Sandbox;            # system command sandbox
    require TWiki::Configure::Load;    # read configuration files

    $TRUE = 1;
    $FALSE = 0;

    if( DEBUG ) {
        # If ASSERTs are on, then warnings are errors. Paranoid,
        # but the only way to be sure we eliminate them all.
        # Look out also for $cfg{WarningsAreErrors}, below, which
        # is another way to install this handler without enabling
        # ASSERTs
        # ASSERTS are turned on by defining the environment variable
        # TWIKI_ASSERTS. If ASSERTs are off, this is assumed to be a
        # production environment, and no stack traces or paths are
        # output to the browser.
        $SIG{'__WARN__'} = sub { die @_ };
        $Error::Debug = 1; # verbose stack traces, please
    } else {
        $Error::Debug = 0; # no verbose stack traces
    }

    # DO NOT CHANGE THE FORMAT OF $VERSION
    # The $VERSION is automatically expanded on checkin of this module
    $VERSION = '$Date: 2018-07-16 12:09:47 +0900 (Mon, 16 Jul 2018) $ $Rev: 30610 (2018-07-16) $ ';
    $RELEASE = 'TWiki-6.1.0';
    $VERSION =~ s/^.*?\((.*)\).*: (\d+) .*?$/$RELEASE, $1, build $2/;

    # Default handlers for different %TAGS%
    %functionTags = (
        ADDTOHEAD         => \&ADDTOHEAD,
        ALLVARIABLES      => \&ALLVARIABLES,
        ATTACHURL         => \&ATTACHURL,
        ATTACHURLPATH     => \&ATTACHURLPATH,
        BASETOPIC         => \&BASETOPIC,
        BASEWEB           => \&BASEWEB,
        CONTENTMODE       => \&CONTENTMODE,
        CRYPTTOKEN        => \&CRYPTTOKEN,
        DATE              => \&DATE,
        DISKID            => \&DISKID,
        DISPLAYTIME       => \&DISPLAYTIME,
        EDITFORM          => \&EDITFORM,
        EDITFORMFIELD     => \&EDITFORMFIELD,
        ENCODE            => \&ENCODE,
        ENTITY            => \&ENTITY,
        ENV               => \&ENV,
        FORM              => \&FORM,
        FORMFIELD         => \&FORMFIELD,
        GMTIME            => \&GMTIME,
        GROUPS            => \&GROUPS,
        HIDE              => \&HIDE,
        HIDEINPRINT       => \&HIDEINPRINT,
        HTTP_HOST         => \&HTTP_HOST_deprecated,
        HTTP              => \&HTTP,
        HTTPS             => \&HTTPS,
        ICON              => \&ICON,
        ICONURL           => \&ICONURL,
        ICONURLPATH       => \&ICONURLPATH,
        IF                => \&IF,
        INCLUDE           => \&INCLUDE,
        INCLUDINGTOPIC    => \&INCLUDINGTOPIC,
        INCLUDINGWEB      => \&INCLUDINGWEB,
        INTURLENCODE      => \&INTURLENCODE_deprecated,
        LANGUAGES         => \&LANGUAGES,
        MAKETEXT          => \&MAKETEXT,
	MDREPO            => \&MDREPO,
        META              => \&META,
        METASEARCH        => \&METASEARCH,
        NOP               => \&NOP,
        PARENTTOPIC       => \&PARENTTOPIC,
        PLUGINVERSION     => \&PLUGINVERSION,
        PUBURL            => \&PUBURL,
        PUBURLPATH        => \&PUBURLPATH,
        QUERYPARAMS       => \&QUERYPARAMS,
        QUERYSTRING       => \&QUERYSTRING,
        RELATIVETOPICPATH => \&RELATIVETOPICPATH,
        REMOTE_ADDR       => \&REMOTE_ADDR_deprecated,
        REMOTE_PORT       => \&REMOTE_PORT_deprecated,
        REMOTE_USER       => \&REMOTE_USER_deprecated,
        RENDERHEAD        => \&RENDERHEAD,
        REVINFO           => \&REVINFO,
        REVTITLE          => \&REVTITLE,
        REVARG            => \&REVARG,
        SCRIPTNAME        => \&SCRIPTNAME,
        SCRIPTURL         => \&SCRIPTURL,
        SCRIPTURLPATH     => \&SCRIPTURLPATH,
        SEARCH            => \&SEARCH,
        SEP               => \&SEP,
        SERVERTIME        => \&SERVERTIME,
        SPACEDTOPIC       => \&SPACEDTOPIC_deprecated,
        SPACEOUT          => \&SPACEOUT,
        'TMPL:P'          => \&TMPLP,
        TOPIC             => \&TOPIC,
        TOPICLIST         => \&TOPICLIST,
        TOPICTITLE        => \&TOPICTITLE,
        TRASHWEB          => \&TRASHWEB,
        URLENCODE         => \&ENCODE,
        URLPARAM          => \&URLPARAM,
        LANGUAGE          => \&LANGUAGE,
        USERINFO          => \&USERINFO,
        USERNAME          => \&USERNAME_deprecated,
        VAR               => \&VAR,
        WEB               => \&WEB,
        WEBLIST           => \&WEBLIST,
        WIKINAME          => \&WIKINAME_deprecated,
        WIKIUSERNAME      => \&WIKIUSERNAME_deprecated,
        WIKIWEBMASTER     => \&WIKIWEBMASTER,
        WIKIWEBMASTERNAME => \&WIKIWEBMASTERNAME,
        # Constant tag strings _not_ dependent on config. These get nicely
        # optimised by the compiler.
        ENDSECTION        => sub { '' },
        WIKIVERSION       => sub { $VERSION },
        STARTSECTION      => sub { '' },
        STARTINCLUDE      => sub { '' },
        STOPINCLUDE       => sub { '' },
       );
    $contextFreeSyntax{IF} = 1;

    unless( ( $TWiki::cfg{DetailedOS} = $^O ) ) {
        require Config;
        $TWiki::cfg{DetailedOS} = $Config::Config{'osname'};
    }
    $TWiki::cfg{OS} = 'UNIX';
    if ($TWiki::cfg{DetailedOS} =~ /darwin/i) { # MacOS X
        $TWiki::cfg{OS} = 'UNIX';
    } elsif ($TWiki::cfg{DetailedOS} =~ /Win/i) {
        $TWiki::cfg{OS} = 'WINDOWS';
    } elsif ($TWiki::cfg{DetailedOS} =~ /vms/i) {
        $TWiki::cfg{OS} = 'VMS';
    } elsif ($TWiki::cfg{DetailedOS} =~ /bsdos/i) {
        $TWiki::cfg{OS} = 'UNIX';
    } elsif ($TWiki::cfg{DetailedOS} =~ /dos/i) {
        $TWiki::cfg{OS} = 'DOS';
    } elsif ($TWiki::cfg{DetailedOS} =~ /^MacOS$/i) { # MacOS 9 or earlier
        $TWiki::cfg{OS} = 'MACINTOSH';
    } elsif ($TWiki::cfg{DetailedOS} =~ /os2/i) {
        $TWiki::cfg{OS} = 'OS2';
    }

    # Validate and untaint Apache's SERVER_NAME Environment variable
    # for use in referencing virtualhost-based paths for separate data/ and templates/ instances, etc
    if ( $ENV{SERVER_NAME} &&
         $ENV{SERVER_NAME} =~ /^(([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,6})$/ ) {
        $ENV{SERVER_NAME} =
          TWiki::Sandbox::untaintUnchecked( $ENV{SERVER_NAME} );
    }

    # readConfig is defined in TWiki::Configure::Load to allow overriding it
    TWiki::Configure::Load::readConfig();

    if( $TWiki::cfg{WarningsAreErrors} ) {
        # Note: Warnings are always errors if ASSERTs are enabled
        $SIG{'__WARN__'} = sub { die @_ };
    }

    if( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }

    # Constant tags dependent on the config
    $functionTags{ALLOWLOGINNAME}  =
      sub { $TWiki::cfg{Register}{AllowLoginName} || 0 };
    $functionTags{AUTHREALM}       = sub { $TWiki::cfg{AuthRealm} };
    $functionTags{DEFAULTURLHOST}  = sub { $TWiki::cfg{DefaultUrlHost} };
    $functionTags{HOMETOPIC}       = sub { $TWiki::cfg{HomeTopicName} };
    $functionTags{LOCALSITEPREFS}  = sub { $TWiki::cfg{LocalSitePreferences} };
    $functionTags{NOFOLLOW}        =
      sub { $TWiki::cfg{NoFollow} ? 'rel='.$TWiki::cfg{NoFollow} : '' };
    $functionTags{NOTIFYTOPIC}     = sub { $TWiki::cfg{NotifyTopicName} };
    $functionTags{SCRIPTSUFFIX}    = sub { $TWiki::cfg{ScriptSuffix} };
    $functionTags{SITESTATISTICSTOPIC} = sub { $TWiki::cfg{Stats}{SiteStatsTopicName} };
    $functionTags{STATISTICSTOPIC} = sub { $TWiki::cfg{Stats}{TopicName} };
    $functionTags{SYSTEMWEB}       = sub { $TWiki::cfg{SystemWebName} };
    # $functionTags{TRASHWEB}        = sub { $TWiki::cfg{TrashWebName} };
    $functionTags{TWIKIADMINLOGIN} = sub { $TWiki::cfg{AdminUserLogin} };
    $functionTags{USERSWEB}        = sub { $TWiki::cfg{UsersWebName} };
    $functionTags{WEBPREFSTOPIC}   = sub { $TWiki::cfg{WebPrefsTopicName} };
    $functionTags{WIKIPREFSTOPIC}  = sub { $TWiki::cfg{SitePrefsTopicName} };
    $functionTags{WIKIUSERSTOPIC}  = sub { $TWiki::cfg{UsersTopicName} };
    if ( $TWiki::cfg{UserSubwebs}{Enabled} ) {
        $functionTags{USERPREFSTOPIC} =
            sub { $TWiki::cfg{UserSubwebs}{UserPrefsTopicName} };
    }

    # Compatibility synonyms, deprecated in 4.2 but still used throughout
    # the documentation.
    $functionTags{MAINWEB}         = $functionTags{USERSWEB};
    $functionTags{TWIKIWEB}        = $functionTags{SYSTEMWEB};

    # locale setup
    #
    #
    # Note that 'use locale' must be done in BEGIN block for regexes and
    # sorting to work properly, although regexes can still work without
    # this in 'non-locale regexes' mode.

    if ( $TWiki::cfg{UseLocale} ) {
        # Set environment variables for grep 
        $ENV{LC_CTYPE} = $TWiki::cfg{Site}{Locale};

        # Load POSIX for I18N support.
        require POSIX;
        import POSIX qw( locale_h LC_CTYPE LC_COLLATE );

        # SMELL: mod_perl compatibility note: If TWiki is running under Apache,
        # won't this play with the Apache process's locale settings too?
        # What effects would this have?
        setlocale(&LC_CTYPE, $TWiki::cfg{Site}{Locale});
        setlocale(&LC_COLLATE, $TWiki::cfg{Site}{Locale});
    }

    $functionTags{CHARSET}   = sub { $TWiki::cfg{Site}{CharSet} ||
                                       'iso-8859-1' };

    # HTML 4.01 and XML refers to RFC 4646 with language specification.
    # RFC 4646 dictates the delimiter to be a hyphen rather than an underscore.
    my $lang = $TWiki::cfg{Site}{Lang};
    unless ( $lang ) {
        if ( $TWiki::cfg{Site}{Locale} =~ m/^([a-z]+_[a-z]+)/i ) {
            $lang = $1;
            $lang =~ s/_/-/;
        }
        else {
            $lang = 'en-US';
        }
    }
    $functionTags{LANG} = sub { $lang };

    # Set up pre-compiled regexes for use in rendering.  All regexes with
    # unchanging variables in match should use the '/o' option.
    # In the regex hash, all precompiled REs have "Regex" at the
    # end of the name. Anything else is a string, either intended
    # for use as a character class, or as a sub-expression in
    # another compiled RE.

    # Build up character class components for use in regexes.
    # Depends on locale mode and Perl version, and finally on
    # whether locale-based regexes are turned off.
    if ( not $TWiki::cfg{UseLocale} or $] < 5.006
         or not $TWiki::cfg{Site}{LocaleRegexes} ) {

        # No locales needed/working, or Perl 5.005, so just use
        # any additional national characters defined in TWiki.cfg
        $regex{upperAlpha} = 'A-Z'.$TWiki::cfg{UpperNational};
        $regex{lowerAlpha} = 'a-z'.$TWiki::cfg{LowerNational};
        $regex{numeric}    = '\d';
        $regex{mixedAlpha} = $regex{upperAlpha}.$regex{lowerAlpha};
    } else {
        # Perl 5.006 or higher with working locales
        $regex{upperAlpha} = '[:upper:]';
        $regex{lowerAlpha} = '[:lower:]';
        $regex{numeric}    = '[:digit:]';
        $regex{mixedAlpha} = '[:alpha:]';
    }
    $regex{mixedAlphaNum} = $regex{mixedAlpha}.$regex{numeric};
    $regex{lowerAlphaNum} = $regex{lowerAlpha}.$regex{numeric};
    $regex{upperAlphaNum} = $regex{upperAlpha}.$regex{numeric};

    # Compile regexes for efficiency and ease of use
    # Note: qr// locks in regex modes (i.e. '-xism' here) - see Friedl
    # book at http://regex.info/. 

    $regex{linkProtocolPattern} = $TWiki::cfg{LinkProtocolPattern};

    # Header patterns based on '+++'. The '###' are reserved for numbered
    # headers
    # '---++ Header', '---## Header'
    $regex{headerPatternDa} = qr/^---+(\++|\#+)(.*)$/m;
    # '<h6>Header</h6>
    $regex{headerPatternHt} = qr/^<h([1-6])>(.+?)<\/h\1>/mi;
    # '---++!! Header' or '---++ Header %NOTOC% ^top'
    $regex{headerPatternNoTOC} = '(\!\!+|%NOTOC%)';

    # TWiki concept regexes
    $regex{wikiWordRegex} = qr/[$regex{upperAlpha}]+[$regex{lowerAlphaNum}]+[$regex{upperAlpha}]+[$regex{mixedAlphaNum}]*/o;
    $regex{webNameBaseRegex} = qr/[$regex{upperAlpha}]+[$regex{mixedAlphaNum}_]*/o;
    if ($TWiki::cfg{EnableHierarchicalWebs}) {
        $regex{webNameRegex} = qr/$regex{webNameBaseRegex}(?:(?:[\.\/]$regex{webNameBaseRegex})+)*/o;
    } else {
        $regex{webNameRegex} = $regex{webNameBaseRegex};
    }
    $regex{defaultWebNameRegex} = qr/_[$regex{mixedAlphaNum}_]+/o;
    $regex{anchorRegex} = qr/\#[$regex{mixedAlphaNum}_]+/o;
    $regex{abbrevRegex} = qr/[$regex{upperAlpha}]{3,}s?\b/o;
    # used by _fixIncludeLink: (the last OR pattern is for Interwiki link fix Item6463)
    $regex{excludeFixIncludeLinkRegex} =
        qr/($regex{webNameRegex}\.|$regex{defaultWebNameRegex}\.|$regex{linkProtocolPattern}:|\/|[$regex{upperAlpha}][$regex{mixedAlphaNum}]+:)/o;

    # Simplistic email regex, e.g. for WebNotify processing - no i18n
    # characters allowed
    $regex{emailAddrRegex} = qr/([A-Za-z0-9\.\+\-\_\']+\@[A-Za-z0-9\.\-]*[A-Za-z0-9])/;

    # Filename regex to used to match invalid characters in attachments - allow
    # alphanumeric characters, spaces, underscores, etc.
    # TODO: Get this to work with I18N chars - currently used only with UseLocale off
    $regex{filenameInvalidCharRegex} = qr/[^$regex{mixedAlphaNum}\. _-]/o;

    # Multi-character alpha-based regexes
    $regex{mixedAlphaNumRegex} = qr/[$regex{mixedAlphaNum}]*/o;

    # %TAG% name
    $regex{tagNameRegex} = '['.$regex{mixedAlpha}.']['.$regex{mixedAlphaNum}.'_:]*';

    # Set statement in a topic
    $regex{bulletRegex} = '^(?:\t|   )+\*';
    $regex{setRegex} = $regex{bulletRegex}.'\s+(Set|Local)\s+';
    $regex{setVarRegex} = $regex{setRegex}.'('.$regex{tagNameRegex}.')\s*=\s*(.*)$';

    # Character encoding regexes

    # 7-bit ASCII only
    $regex{validAsciiStringRegex} = qr/^[\x00-\x7F]+$/o;

    # Regex to match only a valid UTF-8 character, taking care to avoid
    # security holes due to overlong encodings by excluding the relevant
    # gaps in UTF-8 encoding space - see 'perldoc perlunicode', Unicode
    # Encodings section.  Tested against Markus Kuhn's UTF-8 test file
    # at http://www.cl.cam.ac.uk/~mgk25/ucs/examples/UTF-8-test.txt.
    $regex{validUtf8CharRegex} = qr{
          # Single byte - ASCII
          [\x00-\x7F] 
          |

          # 2 bytes
          [\xC2-\xDF][\x80-\xBF] 
          |

          # 3 bytes

          # Avoid illegal codepoints - negative lookahead
          (?!\xEF\xBF[\xBE\xBF])    

          # Match valid codepoints
          (?:
            ([\xE0][\xA0-\xBF])|
            ([\xE1-\xEC\xEE-\xEF][\x80-\xBF])|
            ([\xED][\x80-\x9F])
          )
          [\x80-\xBF]
          |

          # 4 bytes 
          (?:
            ([\xF0][\x90-\xBF])|
            ([\xF1-\xF3][\x80-\xBF])|
            ([\xF4][\x80-\x8F])
          )
          [\x80-\xBF][\x80-\xBF]
        }xo;

    $regex{validUtf8StringRegex} =
      qr/^ (?: $regex{validUtf8CharRegex} )+ $/xo;

    # Check for unsafe search regex mode (affects filtering in) - default
    # to safe mode
    $TWiki::cfg{ForceUnsafeRegexes} = 0 unless defined $TWiki::cfg{ForceUnsafeRegexes};

    # scripts which cannot work for a slave web
    if ( $TWiki::cfg{ReadOnlyAndMirrorWebs}{ScriptOnMaster} ) {
        for my $script (
            split(/[\s,]+/,
                  $TWiki::cfg{ReadOnlyAndMirrorWebs}{ScriptOnMaster})
        ) {
            $scriptOnMaster{$script} = 1;
        }
    }

    # HTTP header fields not be exposed to users
    if ( $TWiki::cfg{HTTP}{HiddenFields} ) {
        for my $field (
            split(/[\s,]+/,
                  $TWiki::cfg{HTTP}{HiddenFields})
        ) {
            $field = lc $field;
            $field =~ s/_/-/g;
            $httpHiddenField{$field} = 1;
        }
    }

    # initialize lib directory early because of later 'cd's
    getTWikiLibDir();

    # initialize the runtime engine
    if (!defined $TWiki::cfg{Engine}) {
        # Caller did not define an engine; try and work it out (mainly for
        # the benefit of pre-5.0 CGI scripts)
        if ( defined $ENV{GATEWAY_INTERFACE} or defined $ENV{MOD_PERL} ) {
            $TWiki::cfg{Engine} = 'TWiki::Engine::CGI';
            use CGI::Carp qw(fatalsToBrowser);
            $SIG{__DIE__} = \&CGI::Carp::confess;
        } else {
            $TWiki::cfg{Engine} = 'TWiki::Engine::CLI';
            require Carp;
            $SIG{__DIE__} = \&Carp::confess;
        }
    }
    $engine ||= eval qq(use $TWiki::cfg{Engine}; $TWiki::cfg{Engine}->new);
    die $@ if $@;

};

=pod

---++ ObjectMethod UTF82SiteCharSet( $utf8 ) -> $ascii

Auto-detect UTF-8 vs. site charset in string, and convert UTF-8 into site
charset.

=cut

sub UTF82SiteCharSet {
    my( $this, $text ) = @_;

    return $text unless( defined $TWiki::cfg{Site}{CharSet} );

    # Detect character encoding of the full topic name from URL
    return undef if( $text =~ $regex{validAsciiStringRegex} );

    # If not UTF-8 - assume in site character set, no conversion required
    return undef unless( $text =~ $regex{validUtf8StringRegex} );

    # If site charset is already UTF-8, there is no need to convert anything:
    if ( $TWiki::cfg{Site}{CharSet} =~ /^utf-?8$/i ) {
        # warn if using Perl older than 5.8
        if( $] <  5.008 ) {
            $this->writeWarning( 'UTF-8 not remotely supported on Perl '.$].
                                 ' - use Perl 5.8 or higher..' );
        }

        return $text;
    }

    # Convert into ISO-8859-1 if it is the site charset.  This conversion
    # is *not valid for ISO-8859-15*.
    if ( $TWiki::cfg{Site}{CharSet} =~ /^iso-?8859-?1$/i ) {
        # ISO-8859-1 maps onto first 256 codepoints of Unicode
        # (conversion from 'perldoc perluniintro')
        $text =~ s/ ([\xC2\xC3]) ([\x80-\xBF]) / 
          chr( ord($1) << 6 & 0xC0 | ord($2) & 0x3F )
            /egx;
    } else {
        # Convert from UTF-8 into some other site charset
        if( $] >= 5.008 ) {
            require Encode;
            import Encode qw(:fallbacks);
            # Map $TWiki::cfg{Site}{CharSet} into real encoding name
            my $charEncoding =
              Encode::resolve_alias( $TWiki::cfg{Site}{CharSet} );
            if( not $charEncoding ) {
                $this->writeWarning
                  ( 'Conversion to "'.$TWiki::cfg{Site}{CharSet}.
                    '" not supported, or name not recognised - check '.
                    '"perldoc Encode::Supported"' );
            } else {
                # Convert text using Encode:
                # - first, convert from UTF8 bytes into internal
                # (UTF-8) characters
                $text = Encode::decode('utf8', $text);    
                # - then convert into site charset from internal UTF-8,
                # inserting \x{NNNN} for characters that can't be converted
                $text =
                  Encode::encode( $charEncoding, $text,
                                  &FB_PERLQQ() );
            }
        } else {
            require Unicode::MapUTF8;    # Pre-5.8 Perl versions
            my $charEncoding = $TWiki::cfg{Site}{CharSet};
            if( not Unicode::MapUTF8::utf8_supported_charset($charEncoding) ) {
                $this->writeWarning
                  ( 'Conversion to "'.$TWiki::cfg{Site}{CharSet}.
                    '" not supported, or name not recognised - check '.
                    '"perldoc Unicode::MapUTF8"' );
            } else {
                # Convert text
                $text =
                  Unicode::MapUTF8::from_utf8({
                                               -string => $text,
                                               -charset => $charEncoding
                                              });
                # FIXME: Check for failed conversion?
            }
        }
    }
    return $text;
}

=pod

---++ ObjectMethod writeCompletePage( $text, $pageType, $contentType, $status )

Write a complete HTML page with basic header to the browser.
   * =$text= is the text of the page body (&lt;html&gt; to &lt;/html&gt; if it's HTML)
   * =$pageType= - May be "edit", which will cause headers to be generated that force
     caching for 24 hours, to prevent Codev.BackFromPreviewLosesText bug, which caused
     data loss with IE5 and IE6.
   * =$contentType= - page content type | text/html
   * =$status= - page status | 200 OK

This method removes noautolink and nop tags before outputting the page unless
$contentType is text/plain.

=cut

sub writeCompletePage {
    my ( $this, $text, $pageType, $contentType, $status ) = @_;

    # Item7197: Check utf-8 flag
    if( $] >= 5.008 ) {
        require Encode;
        if( Encode::is_utf8( $text ) ) {
            $this->writeWarning("UTF-8 flag is detected in the text (possibly from some plugins?), which should be remediated");
            $text = Encode::encode_utf8($text);
        }
    }

    $contentType ||= 'text/html';

    if( $contentType ne 'text/plain' ) {
        # Remove <nop> and <noautolink> tags
        $text =~ s/([\t ]?)[ \t]*<\/?(nop|noautolink)\/?>/$1/gis;
        $text .= "\n" unless $text =~ /\n$/s;

        # If TWiki is enabled for CryptToken for CSRF kind of 
        # security issues, send all forms for adding token before
        # presenting to the browser
        if ($TWiki::cfg{CryptToken}{Enable}) {
            $text =~  s/(<form.*?<\/form>)/$this->{users}->{loginManager}->addCryptTokeninForm($1)/geos; 
        }

        my $htmlHeader = join(
            "\n",
            map { '<!--'.$_.'-->'.$this->{_HTMLHEADERS}{$_} }
              keys %{$this->{_HTMLHEADERS}} );
        $text =~ s!(</head>)!$htmlHeader$1!i if $htmlHeader;
        chomp($text);
    }

    $this->generateHTTPHeaders( $pageType, $contentType, $status );
    my $hdr;
    foreach my $header ( keys %{ $this->{response}->headers } ) {
        $hdr .= $header . ': ' . $_ . "\x0D0A"
          foreach $this->{response}->getHeader($header);
    }
    $hdr .= "\x0D0A";

    # Call final handler
    $this->{plugins}->dispatch(
        'completePageHandler',$text, $hdr);

    $this->{response}->body($text);
}

=pod

---++ ObjectMethod generateHTTPHeaders ($pageType, $contentType, $status ) -> $header

All parameters are optional.

   * =$pageType= - May be "edit", which will cause headers to be generated that force caching for 24 hours, to prevent Codev.BackFromPreviewLosesText bug, which caused data loss with IE5 and IE6.
   * =$contentType= - page content type | text/html
   * =$status= - page status | 200 OK

Implements the post-Dec2001 release plugin API, which requires the
writeHeaderHandler in plugin to return a string of HTTP headers, CR/LF
delimited. Filters any illegal headers. Plugin headers will override
core settings.

Does *not* add a =Content-length= header.

=cut

sub generateHTTPHeaders {
    my( $this, $pageType, $contentType, $status ) = @_;

    my $query = $this->{request};

    # Handle Edit pages - future versions will extend to caching
    # of other types of page, with expiry time driven by page type.
    my( $pluginHeaders, $coreHeaders );

    my $hopts = {};

    if ($pageType && $pageType eq 'edit') {
        # Get time now in HTTP header format
        my $lastModifiedString =
          TWiki::Time::formatTime(time, '$http', 'gmtime');

        # Expiry time is set high to avoid any data loss.  Each instance of 
        # Edit page has a unique URL with time-string suffix (fix for 
        # RefreshEditPage), so this long expiry time simply means that the 
        # browser Back button always works.  The next Edit on this page 
        # will use another URL and therefore won't use any cached 
        # version of this Edit page.
        my $expireHours = 24;
        my $expireSeconds = $expireHours * 60 * 60;

        # and cache control headers, to ensure edit page 
        # is cached until required expiry time.
        $hopts->{'last-modified'} = $lastModifiedString;
        $hopts->{expires} = "+${expireHours}h";
        $hopts->{'cache-control'} = "max-age=$expireSeconds";
    }

    # DEPRECATED plugins header handler. Plugins should use
    # modifyHeaderHandler instead.
    $pluginHeaders = $this->{plugins}->dispatch(
        'writeHeaderHandler', $query ) || '';
    if( $pluginHeaders ) {
        foreach ( split /\r?\n/, $pluginHeaders ) {
            if ( m/^([\-a-z]+): (.*)$/i ) {
                $hopts->{$1} = $2;
            }
        }
    }

    $contentType = 'text/html' unless $contentType;
    if( defined( $TWiki::cfg{Site}{CharSet} )) {
      $contentType .= '; charset='.$TWiki::cfg{Site}{CharSet};
    }

    # use our version of the content type
    $hopts->{'Content-Type'} = $contentType;

    # Item7193: Disable XSS Protection to make JavaScript work when a topic is
    # saved with JavaScript contained.
    if ( isTrue( $TWiki::cfg{DisableXSSProtection} ) ) {
        $hopts->{'X-XSS-Protection'} = '0';
    }

    if ( $status ) {
        $hopts->{Status} = $status;
    }

    # New (since 1.026)
    $this->{plugins}->dispatch(
        'modifyHeaderHandler', $hopts, $this->{request} );

    # add cookie(s)
    $this->{users}->{loginManager}->modifyHeader( $hopts );

    $this->{response}->setDefaultHeaders( $hopts );
}

=pod

---++ StaticMethod isRedirectSafe($redirect) => $ok

tests if the $redirect is an external URL, returning false if AllowRedirectUrl is denied

=cut

sub isRedirectSafe {
    my $redirect = shift;
    return 1 if ($TWiki::cfg{AllowRedirectUrl}); 
     
    #TODO: this should really use URI
    if ( $redirect =~ m!^([^:]*://[^/]*)/*(.*)?$! ) {
        my $host = $1;
        #remove trailing /'s to match
        $TWiki::cfg{DefaultUrlHost} =~ m!^([^:]*://[^/]*)/*(.*)?$!;
        my $expected = $1;
        return 1 if (uc($host) eq uc($expected));
 
        if (defined($TWiki::cfg{PermittedRedirectHostUrls} ) && $TWiki::cfg{PermittedRedirectHostUrls}  ne '') {
            my @permitted =
                map { s!^([^:]*://[^/]*)/*(.*)?$!$1!; $1 }
                        split(/,\s*/, $TWiki::cfg{PermittedRedirectHostUrls});
            return 1 if ( grep ( { uc($host) eq uc($_) } @permitted));
        }
        return 0;
    }

    return 1;
}

# _getRedirectUrl() => redirectURL set from the parameter
# Reads a redirect url from CGI parameter 'redirectto'.
# This function is used to get and test the 'redirectto' cgi parameter, 
# and then the calling function can set its own reporting if there is a
# problem.
sub _getRedirectUrl {
    my $session = shift;

    my $query = $session->{request};
    my $redirecturl = $query->param( 'redirectto' );
    return '' unless $redirecturl;

    if ( $redirecturl =~ /AUTOINC/ && defined $session->{AUTOINC} ) {
        $redirecturl =~ s//$session->{AUTOINC}/g;
    }
    my $sessionParam = {
        web   => $session->{webName},
        topic => $session->{topicName},
    };
    $redirecturl =~ s/\$\{([^{}]*)\}|\$(\w+)/
        my $v = ($1 || $2);
        urlEncode($query->param($v) || $sessionParam->{$v} || '')/eg;
    if( $redirecturl =~ m#^$regex{linkProtocolPattern}://#o ) {
        # assuming URL
        if (isRedirectSafe($redirecturl)) {
            return $redirecturl;
        } else {
            return '';
        }
    }
    # assuming 'web.topic' or 'topic'
    my $urlParams = '';
    if ( $redirecturl =~ /\?(.*)$/ ) {
        $urlParams = $1;
        $redirecturl =~ s///;
    }
    my ( $w, $t ) = $session->normalizeWebTopicName( $session->{webName}, $redirecturl );
    $redirecturl = $session->getScriptUrl( 1, 'view', $w, $t );
    return $redirecturl . ($urlParams eq '' ? '' : '?' . $urlParams);
}


=pod

---++ ObjectMethod redirect( $url, $passthrough, $action_redirectto, $viaCache )

   * $url - url or twikitopic to redirect to
   * $passthrough - (optional) parameter to **FILLMEIN**
   * $action_redirectto - (optional) redirect to where ?redirectto=
     points to (if it's valid)
   * $viaCache - forcibly cache a redirect CGI query. It cuts off all 
     the params in a GET url and replace with a "?$cache=..." param.

Redirects the request to =$url=, *unless*
   1 It is overridden by a plugin declaring a =redirectCgiQueryHandler=.
   1 =$session->{request}= is =undef= or
   1 $query->param('noredirect') is set to a true value.
Thus a redirect is only generated when in a CGI context.

Normally this method will ignore parameters to the current query. Sometimes,
for example when redirecting to a login page during authentication (and then
again from the login page to the original requested URL), you want to make
sure all parameters are passed on, and for this $passthrough should be set to
true. In this case it will pass all parameters that were passed to the
current query on to the redirect target. If the request_method for the
current query was GET, then all parameters will be passed by encoding them
in the URL (after ?). If the request_method was POST, then there is a risk the
URL would be too big for the receiver, so it caches the form data and passes
over a cache reference in the redirect GET.

NOTE: Passthrough is only meaningful if the redirect target is on the same
server. "$viaCache" is meaningful only if "$action_redirectto" is false and 
"$passthru" is true.

=cut

sub redirect {
    my( $this, $url, $passthru, $action_redirectto, $viaCache ) = @_;

    my $query = $this->{request};
    # if we got here without a query, there's not much more we can do
    return unless $query;

    # SMELL: if noredirect is set, don't generate the redirect, throw an
    # exception instead. This is a HACK used to support TWikiDrawPlugin.
    # It is deprecated and must be replaced by REST handlers in the plugin.
    if( $query->param( 'noredirect' )) {
        die "ERROR: $url";
        return;
    }

    if ($action_redirectto) {
        my $redir = _getRedirectUrl($this);
        $url = $redir if ($redir);
    }

    if ( $passthru && defined $query->request_method() ) {
        my $existing = '';
        if ($url =~ s/\?(.*)$//) {
            $existing = $1;
        }
        if ( $query->request_method() =~ /^POST$/i || $viaCache ) {
            # Redirecting from a post to a get
            my $cache = $this->cacheQuery();
            if ($cache) {
                $url .= "?$cache";
            }
        } else {
            if ($query->query_string()) {
                $url .= '?'.$query->query_string();
            }
            if ($existing) {
                if ($url =~ /\?/) {
                    $url .= ';';
                } else {
                    $url .= '?';
                }
                $url .= $existing;
            }
        }
    }

    # prevent phishing by only allowing redirect to configured host
    # do this check as late as possible to catch _any_ last minute hacks
    # TODO: this should really use URI
    if (!isRedirectSafe($url)) {
         # goto oops if URL is trying to take us somewhere dangerous
         $url = $this->getScriptUrl(
             1, 'oops',
             $this->{web} || $TWiki::cfg{UsersWebName},
             $this->{topic} || $TWiki::cfg{HomeTopicName},
             template => 'oopsaccessdenied',
             def => 'topic_access',
             param1 => 'redirect',
             param2 => 'unsafe redirect to '.$url.
               ': host does not match {DefaultUrlHost} , and is not in {PermittedRedirectHostUrls}"'.
                 $TWiki::cfg{DefaultUrlHost}.'"'
            );
    }


    return if( $this->{plugins}->dispatch(
        'redirectCgiQueryHandler', $this->{response}, $url ));

    # SMELL: this is a bad breaking of encapsulation: the loginManager
    # should just modify the url, then the redirect should only happen here.
    return !$this->{users}->{loginManager}->redirectCgiQuery( $query, $url );
}

=pod

---++ ObjectMethod cacheQuery() -> $queryString

Caches the current query in the params cache, and returns a rewritten
query string for the cache to be picked up again on the other side of a
redirect.

We can't encode post params into a redirect, because they may exceed the
size of the GET request. So we cache the params, and reload them when the
redirect target is reached.

=cut

sub cacheQuery {
    my $this = shift;
    my $query = $this->{request};

    return '' unless (scalar($query->param()));
    # Don't double-cache
    return '' if ($query->param('twiki_redirect_cache'));

    require Digest::MD5;
    my $md5 = new Digest::MD5();
    $md5->add($$, time(), rand(time));
    my $uid = $md5->hexdigest();
    my $passthruFilename = "$TWiki::cfg{WorkingDir}/tmp/passthru_$uid";

    use Fcntl;
    #passthrough file is only written to once, so if it already exists, suspect a security hack (O_EXCL)
    sysopen(F, "$passthruFilename", O_RDWR|O_EXCL|O_CREAT, 0600) ||
      die "Unable to open $TWiki::cfg{WorkingDir}/tmp for write; check the setting of"
        . " {WorkingDir} in configure, and check file permissions: $!";
    $query->save(\*F);
    close(F);
    return 'twiki_redirect_cache='.$uid;
}

=pod

---++ StaticMethod isValidWikiWord( $name ) -> $boolean

Check for a valid WikiWord or WikiName

=cut

sub isValidWikiWord {
    my $name  = shift || '';
    return ( $name =~ m/^$regex{wikiWordRegex}$/o )
}

=pod

---++ StaticMethod isValidTopicName( $name ) -> $boolean

Check for a valid topic name

=cut

sub isValidTopicName {
    my( $name ) = @_;

    return isValidWikiWord( @_ ) || isValidAbbrev( @_ );
}

=pod

---++ StaticMethod isValidAbbrev( $name ) -> $boolean

Check for a valid ABBREV (acronym)

=cut

sub isValidAbbrev {
    my $name = shift || '';
    return ( $name =~ m/^$regex{abbrevRegex}$/o )
}

=pod

---++ StaticMethod isValidWebName( $name, $system ) -> $boolean

STATIC Check for a valid web name. If $system is true, then
system web names are considered valid (names starting with _)
otherwise only user web names are valid

If $TWiki::cfg{EnableHierarchicalWebs} is off, it will also return false
when a nested web name is passed to it.

=cut

sub isValidWebName {
    my $name = shift || '';
    my $sys = shift;
    return 0 if ( $name =~ m/$TWiki::cfg{InvalidWebNameRegex}/o ); # Item7838
    return 1 if ( $sys && $name =~ m/^$regex{defaultWebNameRegex}$/o );
    return ( $name =~ m/^$regex{webNameRegex}$/o )
}

=pod

---++ ObjectMethod modeAndMaster( $web )
Returns the following hash reference such as this:
<verbatim>
('', undef)
</verbatim>

and this:
<verbatim>
('slave', { # master site data
    siteName         => 'na',
    webScriptUrlTmpl => 'http://twiki.example.com/cgi-bin//Web',
    scriptSuffix     => '',
    webViewUrl       => 'http://twiki.example.com/Web',
})
</verbatim>

The first value is the mode of the web: either 'local', 'master', 'slave',
or 'read-only'. The second value is defined only when the master site is
defined for the web.
=cut

sub modeAndMaster {
    my ($this, $web) = @_;
    my $mode = 'local'; # by default a web is local
    if ( !$TWiki::cfg{ReadOnlyAndMirrorWebs}{SiteName} ) {
        return ($mode, undef);
    }
    my $cache = $this->{modeAndMaster} ||= {};
    if ( my $cached = $cache->{$web} ) {
        return @$cached
    }
    my $cacheHereToo;
    my $masterSite;
    my %master;
    if ( my $mdrepo = $this->{mdrepo} ) {
        my $tlweb = topLevelWeb($web);
        if ( my $cached = $cache->{$tlweb} ) {
            $cache->{$web} = $cached if ( $tlweb ne $web );
            return @$cached;
        }
        $cacheHereToo = $tlweb ne $web ? $tlweb : '';
        my $webRec = $mdrepo->getRec('webs', topLevelWeb($web));
        if ( $webRec ) {
            if ( $masterSite = $webRec->{master} ) {
                $master{siteName} = $masterSite;
                my $siteRec = $mdrepo->getRec('sites', $masterSite);
                if ( $siteRec && $siteRec->{scripturl} ) {
                    $master{webScriptUrlTmpl} =
                        $siteRec->{scripturl} . '//' . $web;
                    $master{scriptSuffix} = $siteRec->{scriptsuffix};
                    $master{webViewUrl} = $siteRec->{viewurl} . '/' . $web
                        if ( $siteRec->{viewurl} );
                }
            }
        }
        # If the metadata repository is in use and the web's record
        # doesn't exist or doesn't have the master field, then the web
        # is regarded as 'local'.
        # No fall back to the none metadata repository situation processed
        # below.
    }
    else {
        my $prefs = $this->{prefs};
        $masterSite = $prefs->getWebPreferencesValue('MASTERSITENAME', $web);
        if ( $masterSite ) {
            $master{siteName} = $masterSite;
            $master{webScriptUrlTmpl} =
                $prefs->getWebPreferencesValue('MASTERWEBSCRIPTURLTMPL', $web);
            $master{scriptSuffix} =
                $prefs->getWebPreferencesValue('MASTERSCRIPTSUFFIX', $web);
            $master{webViewUrl} =
                $prefs->getWebPreferencesValue('MASTERWEBVIEWURL', $web);
        }
    }
    if ( $masterSite ) {
        if ( $masterSite eq $TWiki::cfg{ReadOnlyAndMirrorWebs}{SiteName} ) {
            $mode = 'master';
        }
        else {
            if ( $master{webScriptUrlTmpl} ) {
                $mode = 'slave';
            }
            else {
                $mode = 'read-only'
            }
        }
    }
    my $result = $cache->{$web} = [$mode, %master ? \%master : undef];
    $cache->{$cacheHereToo} = $result if ( $cacheHereToo );
    return @$result;
}

=pod

---++ ObjectMethod getSkin () -> $string

Get the currently requested skin path

=cut

sub getSkin {
    my $this = shift;

    my $skinpath = $this->{prefs}->getPreferencesValue( 'SKIN' ) || '';

    if( $this->{request} ) {
        my $resurface = $this->{request}->param( 'skin' );
        $skinpath = $resurface if $resurface;
    }

    my $epidermis = $this->{prefs}->getPreferencesValue( 'COVER' );
    $skinpath = $epidermis.','.$skinpath if $epidermis;

    if( $this->{request} ) {
        $epidermis = $this->{request}->param( 'cover' );
        $skinpath = $epidermis.','.$skinpath if $epidermis;
    }

    # Resolve TWiki variables if needed
    if( $skinpath =~ /\%[A-Z]/ ) {
        $skinpath = $this->handleCommonTags( $skinpath, $this->{webName},
                                             $this->{topicName} );
    }

    # sanitize skin path
    $skinpath =~ s/[^A-Za-z0-9_\-\,\. ]//g;

    return $skinpath;
}

=pod

---++ ObjectMethod getScriptUrl( $absolute, $script, $web, $topic, ... ) -> $scriptURL

Returns the URL to a TWiki script, providing the web and topic as
"path info" parameters.  The result looks something like this:
"http://host/twiki/bin/$script/$web/$topic".
   * =...= - an arbitrary number of name,value parameter pairs that will be
     url-encoded and added to the url. The special parameter name '#' is
     reserved for specifying an anchor. e.g.
     <tt>getScriptUrl('x','y','view','#'=>'XXX',a=>1,b=>2)</tt> will give
     <tt>.../view/x/y?a=1&b=2#XXX</tt> %BR%

If $absolute is set, generates an absolute URL. $absolute is advisory only;
TWiki can decide to generate absolute URLs (for example when run from the
command-line) even when relative URLs have been requested.

The default script url is taken from {ScriptUrlPath}, unless there is
an exception defined for the given script in {ScriptUrlPaths}. Both
{ScriptUrlPath} and {ScriptUrlPaths} may be absolute or relative URIs. If
they are absolute, then they will always generate absolute URLs. if they
are relative, then they will be converted to absolute when required (e.g.
when running from the command line, or when generating rss). If
$script is not given, absolute URLs will always be generated.

If either the web or the topic is defined, will generate a full url
(including web and topic). Otherwise will generate only up to the script 
name. An undefined web will default to the main web name.

The returned URL takes ReadOnlyAndMirrorWebs into account.
If the specified =$web= is slave on this site, with the scripts
=edit=, =save=, =attach=, =upload=, and =rename=, this method returns
the URLs on the master site because it does not make sense to execute
those scripts on the master site of the web.

Even with the other scripts, you may need to get the URLs on the master site.
You can get those URLs by providing =$master =&gt; 1= as a name value pair.
=cut

sub getScriptUrl {
    my( $this, $absolute, $script, $web, $topic, @params ) = @_;

    if( $web || $topic ) {
        if ( !$web && $topic !~ /[.\/]/ ) {
            $web = $this->{webName};
        }
        else {
            ($web, $topic) = $this->normalizeWebTopicName( $web, $topic );
        }
    }
    # the above is needed here because $web is crucial

    # check if $master => X exists in @params and makes @params1 excluding it
    my $ofMaster = 0;
    my @params1;
    my $i = 0;
    while ( $i < @params ) {
        if ( $params[$i] eq '$master' ) {
            $ofMaster = 1 if ( $params[$i + 1] );
        }
        else {
            push(@params1, @params[$i, $i+1]);
        }
        $i += 2;
    }

    # determine if it's of the master and get the information of the master
    my ($contentMode, $master);
    if ( $web ) {
        ($contentMode, $master) = $this->modeAndMaster($web);
        if ( $master && $master->{webScriptUrlTmpl} ) {
            if ( $contentMode eq 'slave' ) {
                if ( $scriptOnMaster{$script} ) {
                    # even if $script is null, no disaster happens
                    $ofMaster = 1;
                }
            }
            else {
                # if not slave, the master URL is yielded regardless
                $ofMaster = 0;
            }
        }
        else {
            $ofMaster = 0;
                # if $master->{webScriptUrlTmpl} is not defined,
                # no way to get the URL for the master site, hence resort to
                # 'not of master'
        }
    }
    else {
        $ofMaster = 0;
    }

    # SMELL: topics and webs that contain spaces?

    my $url;
    if ( $ofMaster ) {
        $script ||= 'view';
            # A web is specified explicitly or implicitly.
            # In that case, a URL having the web cannot be script neutral.
        $url = $master->{webScriptUrlTmpl};
        if ( $script eq 'view' && $master->{webViewUrl} ) {
            $url = $master->{webViewUrl};
        }
        else {
            my $suffix = $master->{scriptSuffix} || '';
            $url =~ s:^(.*)//:$1/$script$suffix/:;
        }
        $url .= urlEncode( '/'.$topic );
        $url .= _make_params(0, @params1);
    }
    else {
        # if $ofMaster is true, the URL needs to be absolute regardless.
        # So absolute checking is done here.
        $absolute ||= ($this->inContext( 'command_line' ) ||
                       $this->inContext( 'rss' ) ||
                       $this->inContext( 'absolute_urls' ));

        if( defined $TWiki::cfg{ScriptUrlPaths} && $script) {
            $url = $TWiki::cfg{ScriptUrlPaths}{$script};
        }
        unless( defined( $url )) {
            $url = $TWiki::cfg{ScriptUrlPath};
            if( $script ) {
                $url .= '/' unless $url =~ /\/$/;
                $url .= $script;
                if ( rindex($url, $TWiki::cfg{ScriptSuffix}) !=
                     ( length($url) - length($TWiki::cfg{ScriptSuffix}) )
                   ) {
                    $url .= $TWiki::cfg{ScriptSuffix} if $script;
                }
            }
        }

        if( $absolute && $url !~ /^[a-z]+:/ ) {
            # See http://www.ietf.org/rfc/rfc2396.txt for the definition of
            # "absolute URI". TWiki bastardises this definition by assuming
            # that all relative URLs lack the <authority> component as well.
            $url = $this->{urlHost}.$url;
        }

        if( $web || $topic ) {
            $url .= urlEncode( '/'.$web.'/'.$topic );
            $url .= _make_params(0, @params1);
        }
    }

    return $url;
}

sub _make_params {
    my ( $notfirst, @args ) = @_;
    my $url = '';
    my $ps = '';
    my $anchor = '';
    while( my $p = shift @args ) {
        if( $p eq '#' ) {
            $anchor .= '#' . shift( @args );
        } else {
            my $arg = shift( @args );
            $arg = '' unless defined( $arg );
            $ps .= ";$p=" . urlEncode( $arg );
        }
    }
    if( $ps ) {
        $ps =~ s/^;/?/ unless $notfirst;
        $url .= $ps;
    }
    $url .= $anchor;
    return $url;
}

=pod

---++ ObjectMethod getDiskInfo($web, $site, $diskID) -> ($dataDir, $pubDir, $diskID)

You can specify either $web or $diskID, not both.

=cut

sub getDiskInfo {
    my( $this, $web, $site, $diskID ) = @_;
    if ( !$web ) {
        if ( $diskID ) {
            $web = '';
        }
        else {
            $web = $this->{webName};
        }
    }
    $site ||= $TWiki::cfg{ReadOnlyAndMirrorWebs}{SiteName} || '';
    return $this->{store}->getDiskInfo($web, $site, $diskID);
}

=pod

---++ ObjectMethod getDiskList() -> ('', 1, 2, ...)

=cut

sub getDiskList {
    # my( $this ) = @_;
    return $_[0]->{store}->getDiskList();
}

=pod

---++ ObjectMethod getDataDir($web, $diskID) -> $dataDir

You can specify either $web or $diskID, not both.

=cut

sub getDataDir {
    # my( $this, $web, $diskID ) = @_;
    return
        $TWiki::cfg{MultipleDisks} ? (getDiskInfo($_[0], $_[1], '', $_[2]))[0]
                                   : $TWiki::cfg{DataDir};
}

=pod

---++ ObjectMethod getPubDir($web, $diskID) -> $pubDir

You can specify either $web or $diskID, not both.

=cut

sub getPubDir {
    # my( $this, $web, $diskID ) = @_;
    return
        $TWiki::cfg{MultipleDisks} ? (getDiskInfo($_[0], $_[1], '', $_[2]))[1]
                                   : $TWiki::cfg{PubDir};
}

=pod

---++ ObjectMethod getPubUrl($absolute, $web, $topic, $attachment) -> $url

Composes a pub url. If $absolute is set, returns an absolute URL.
If $absolute is set, generates an absolute URL. $absolute is advisory only;
TWiki can decide to generate absolute URLs (for example when run from the
command-line) even when relative URLs have been requested.

$web, $topic and $attachment are optional. A partial URL path will be
generated if one or all is not given.

=cut

sub getPubUrl {
    my( $this, $absolute, $web, $topic, $attachment ) = @_;

    $absolute ||= ($this->inContext( 'command_line' ) ||
                   $this->inContext( 'rss' ) ||
                   $this->inContext( 'absolute_urls' ));

    my $url = '';
    $url .= $TWiki::cfg{PubUrlPath};
    if( $absolute && $url !~ /^[a-z]+:/ ) {
        # See http://www.ietf.org/rfc/rfc2396.txt for the definition of
        # "absolute URI". TWiki bastardises this definition by assuming
        # that all relative URLs lack the <authority> component as well.
        $url = $this->{urlHost}.$url;
    }
    if( $web || $topic || $attachment ) {
        ( $web, $topic ) = $this->normalizeWebTopicName( $web, $topic );

        my $path = '/'.$web.'/'.$topic;
        if( $attachment ) {
            $path .= '/'.$attachment;
            # Attachments are served directly by web server, need to handle
            # URL encoding specially
            $url .= urlEncodeAttachment ( $path );
        } else {
            $url .= urlEncode( $path );
        }
    }

    return $url;
}

=pod

---++ ObjectMethod cacheIconData( $action )

Cache icon data based on action:
   * 'delete' - delete cache file
   * 'read'   - read cache file
   * 'expire' - expire (invalidate) cache if needed
   * 'save'   - save cache file

=cut

sub cacheIconData {
    my( $this, $action, $web, $topic ) = @_;

    my $cacheFile = $this->{store}->getWorkArea( 'VarICON' ) . '/icon_cache.txt';

    if( $action eq 'save' ) {
        if( open( FILE, ">$cacheFile" ) )  {
            print FILE "# Cached icon data; do not edit. See TWiki.TWikiDocGraphics\n";
            my %seen;
            my %refs;
            foreach my $icn (sort keys %{ $this->{_ICONDATA} } ) {
                my $line = "$icn: ";
                if( $seen{ $this->{_ICONDATA}{$icn}{name} } ) {
                    $refs{$icn} = $seen{ $this->{_ICONDATA}{$icn}{name} };
                } else {
                    $seen{ $this->{_ICONDATA}{$icn}{name} } = $icn;
                    $line .= "$this->{_ICONDATA}{$icn}{name}, "
                           . "$this->{_ICONDATA}{$icn}{web}, "
                           . "$this->{_ICONDATA}{$icn}{topic}, "
                           . "$this->{_ICONDATA}{$icn}{type}, "
                           . "$this->{_ICONDATA}{$icn}{width}, "
                           . "$this->{_ICONDATA}{$icn}{height}, "
                           . "$this->{_ICONDATA}{$icn}{description}";
                    print FILE "$line\n";
                }
            }
            # add hash aliases
            foreach my $icn (sort keys %refs ) {
                my $line = "$icn => $refs{$icn}";
                print FILE "$line\n";
            }
            print FILE "# EOF\n";
            close( FILE);
        }

    } elsif( $action eq 'read' ) {
        if( -e $cacheFile && open( FILE, "<$cacheFile" ) ) {
            local $_;
            my $icn;
            while( <FILE> ) {
                if( /^([^\:]+)\: ([^,]+), ([^,]+), ([^,]+), ([^,]+), ([^,]+), ([^,]+), ([^\n\r]+)/ ) {
                    # icon record as hash
                    $icn->{$1} = {
                        name => $2,
                        web => $3,
                        topic => $4,
                        type => $5,
                        width => $6,
                        height => $7,
                        description => $8
                    };
                } elsif( /^([^ ]+) \=> *([^\n\r]+)/ ) {
                    # icon as alias
                    $icn->{$1} = $icn->{$2};
                }
            }
            close( FILE );
            $this->{_ICONDATA} = $icn if( $icn );
        }

    } elsif( $action eq 'expire' ) {
        # invoked by TWiki::Store::saveTopic after afterSaveHandler callback

        if( $topic =~ /^(TWikiPreferences|WebPreferences)$/ ) {
            # Remove icon cache if preferences changed on site level or web level
            unlink( $cacheFile );

        } else {
            # Remove icon cache if any topic in the ICONTOPIC list changed
            my $topics = $this->{prefs}->getPreferencesValue( 'ICONTOPIC' );
            if( $topics ) {
                foreach my $iconTopic ( split( / *, */, $topics ) ) {
                    my( $iWeb, $iTopic ) = $this->normalizeWebTopicName( $this->{webName}, $iconTopic );
                    if( ( $web eq $iWeb ) && ( $topic eq $iTopic ) ) {
                        unlink( $cacheFile );
                    }
                }
            }
        }

    } elsif( $action eq 'delete' ) {
        unlink( $cacheFile );

    }
}

=pod

---++ ObjectMethod formatIcon( $iconName, $format, $default ) -> $icon

Format an icon based on name and format parameter. The format parameter handles 
these variables (with example):
   * $name: Name of icon ('home')
   * $type: Type of icon ('gif')
   * $filename: Icon filename ('home.gif')
   * $web: Web where icon is located ('TWiki')
   * $topic: Topic where icon is located ('TWikiDocGraphics')
   * $description: Icon description ('Home')
   * $width: Width of icon ('16')
   * $height: Height of icon ('16')
   * $img: Full img tag of icon ('<img src="/pub/TWiki/TWikiDocGraphics/home.gif" ... />')
   * $url: URL of icon ('http://example.com/pub/TWiki/TWikiDocGraphics/home.gif')
   * $urlpath: URL path of icon ('/pub/TWiki/TWikiDocGraphics/home.gif')

The optional default parameter specifies the icon name in case the icon is not defined. 
Leave empty if you assume icon files exist in the default location.

=cut

sub formatIcon {
    my( $this, $iconName, $format, $default ) = @_;

    if( $iconName eq 'action:refresh-cache' ) {
        $this->cacheIconData( 'delete' );
        my $text = $format ||
                   "ICON cache is refreshed. "
                 . "[[$this->{SESSION_TAGS}{BASEWEB}.$this->{SESSION_TAGS}{BASETOPIC}][OK]].";
        return $text;
    }

    unless( $this->{_ICONDATA} ) {
        # try to read cache
        $this->cacheIconData( 'read' );
    }

    unless( $this->{_ICONDATA} ) {
        # cache does not exist, so let's create it

        # create one dummy entry in case icon info cannot be read
        # to void repeated retries
        $this->{_ICONDATA}->{_default} = {
            name => '_default',
            web => $TWiki::cfg{SystemWebName},
            topic => 'TWikiDocGraphics',
            description => 'Default',
            type => 'gif',
            width => '16',
            height => '16',
        };
        # read icon info
        my $i = 0;
        foreach my $iconTopic (split(/ *, */, $this->{prefs}->getPreferencesValue( 'ICONTOPIC' ))) {
            my( $web, $topic ) = $this->normalizeWebTopicName( $this->{webName}, $iconTopic );
            my $text = $this->{store}->readTopicRaw( undef, $web, $topic );
            if( $text ) {
                foreach my $line (split(/[\n\r]+/, $text)) {
                    # sample line:
                    # | %ICON{help}% | =%<nop>ICON{help}%=, =%<nop>H%= | Help | gif | 16x16 | info |
                    if( $line =~ / %ICON\{[ "']*([^ "'}]+)[^\|]*\|[^\|]*\| *(.*?) *\| *(.*?) *\| *([0-9]+)x([0-9]+)([^\|]*\| *(.*?) *\|)?/ ) {
                        my $name = $1;
                        $this->{_ICONDATA}->{$name} = {
                            name => $name,
                            web => $web,
                            topic => $topic,
                            description => $2,
                            type => $3,
                            width => $4,
                            height => $5,
                        };
                        my $aliases = $7;
                        if( $aliases ) {
                            foreach my $alias (split(/[ ,]+/, $aliases)) {
                                $this->{_ICONDATA}->{$alias} = $this->{_ICONDATA}->{$name};
                            }
                        }
                    }
                }
                if( $i++ < 2 ) {
                    $this->{_ICONDATA}->{_default}{web} = $web;
                    $this->{_ICONDATA}->{_default}{topic} = $topic;
                }
            }
        }

        # cache icon info
        $this->cacheIconData( 'save' );
    }

    # cut file path/name, if any, and lowercase the file type
    $default  =~ s/^.*\.(.*?)$/lc($1)/e;
    if( $iconName =~ s/^.*\.(.*?)$/lc($1)/e ) {
        # file icon path identified, set default unless defined
        $default = 'else' unless( $default );
    }
    $iconName = 'empty' unless( $iconName );

    if( $iconName =~ /^list:/ ) {
        my @icons = ();
        if( $iconName =~ /all/ ) {
            @icons = sort grep { !/_default/ } keys %{ $this->{_ICONDATA} };
        } else { # unique
            @icons = sort
                     grep { !/_default/ }
                     grep { /$this->{_ICONDATA}->{$_}->{name}/ }
                     keys %{ $this->{_ICONDATA} };
        }
        if( $iconName =~ /names/ ) {
            return join( ', ', @icons );
        } elsif( $iconName =~ /icons/ ) {
            return join( ' ', map { '%ICON{'.$_.'}%' } @icons );
        } elsif( $iconName =~ /info/ ) {
            return join( ' ', map { '%ICON{"'.$_.'" format="$info"}%' } @icons );
        } else { # /table/
            my $text = '| *&nbsp;* | *Name* | *Description* | *Type* | *Size* | *Defined in* |' . "\n";
            my $i = 0;
            for my $icn ( @icons ) {
                $i++;
                $text .= "| \%ICON{$icn}\% | $icn ";
                $text .= "=> $this->{_ICONDATA}->{$icn}->{name} " if( $this->{_ICONDATA}->{$icn}->{name} ne $icn );
                $text .= "| $this->{_ICONDATA}->{$icn}->{description} | $this->{_ICONDATA}->{$icn}->{type} "
                       . "| $this->{_ICONDATA}->{$icn}->{width}x$this->{_ICONDATA}->{$icn}->{height} "
                       . "| [[$this->{_ICONDATA}->{$icn}->{web}.$this->{_ICONDATA}->{$icn}->{topic}]] |\n";
            }
            $text .= "| Total: | $i icons |||||\n";
            return $text;
        }
    }

    # determine icon
    my $icn = $this->{_ICONDATA}->{$iconName} || $this->{_ICONDATA}->{$default};
    unless( $icn ) {
        # assume default location (attached to second topic in ICONTOPIC list)
        $icn = $this->{_ICONDATA}->{_default};
        $icn->{name} = $iconName;
        $icn->{description} = $iconName;
        $icn->{description} =~ s/^(.)/uc($1)/eo;
    }

    # format icon tag/url
    my $iconTag  = '<img src="$urlpath" width="$width" height="$height" '
                 . 'alt="$description" title="$description" border="0" />';
    my $iconInfo = '<img src="$urlpath" width="$width" height="$height" '
                 . 'alt="$name" title="%<nop>ICON{$name}% - <nop>$description, '
                 . 'defined in <nop>$web.$topic" border="0" />';
    $format = '$img' unless( $format );
    $format =~ s/\$img\b/$iconTag/go;
    $format =~ s/\$info\b/$iconInfo/go;
    $format =~ s/\$url\b/$this->getPubUrl( 1, $icn->{web}, $icn->{topic}, "$icn->{name}.$icn->{type}" )/geo;
    $format =~ s/\$urlpath\b/$this->getPubUrl( 0, $icn->{web}, $icn->{topic}, "$icn->{name}.$icn->{type}" )/geo;
    $format =~ s/\$name\b/$icn->{name}/go;
    $format =~ s/\$type\b/$icn->{type}/go;
    $format =~ s/\$filename\b/$icn->{name}.$icn->{type}/go;
    $format =~ s/\$web\b/$icn->{web}/go;
    $format =~ s/\$topic\b/$icn->{topic}/go;
    $format =~ s/\$description\b/$icn->{description}/go;
    $format =~ s/\$width\b/$icn->{width}/go;
    $format =~ s/\$height\b/$icn->{height}/go;

    return $format;
}

=pod

---++ ObjectMethod normalizeWebTopicName( $theWeb, $theTopic ) -> ( $theWeb, $theTopic )

Normalize a Web<nop>.<nop>TopicName

See TWikiFuncDotPm for a full specification of the expansion (not duplicated
here)

*WARNING* if there is no web specification (in the web or topic parameters)
the web defaults to $TWiki::cfg{UsersWebName}. If there is no topic
specification, or the topic is '0', the topic defaults to the web home topic
name.

=cut

sub normalizeWebTopicName {
    my( $this, $web, $topic ) = @_;

    ASSERT(defined $topic) if DEBUG;

    if( $topic =~ m|^(.*)[./](.*?)$| ) {
        $web = $1;
        $topic = $2;
    }
    $web ||= $cfg{UsersWebName};
    $topic ||= $cfg{HomeTopicName};
    while( $web =~ s/%((MAIN|TWIKI|USERS|SYSTEM|DOC)WEB)%/_expandTagOnTopicRendering( $this,$1)||''/e ) {
    }
    $web =~ s#\.#/#go;
    return( $web, $topic );
}

sub _readUserPreferences {
    my ($this) = @_;
    # User preferences only available if we can get to a valid wikiname,
    # which depends on the user mapper.
    my $wn = $this->{users}->getWikiName( $this->{user} );
    if( $wn ) {
        my $prefs = $this->{prefs};
        my $userWeb = $TWiki::cfg{UsersWebName}.'/'.$wn;
        if ( $TWiki::cfg{UserSubwebs}{Enabled} &&
             $this->{store}->topicExists($userWeb,
                                  $TWiki::cfg{UserSubwebs}{UserPrefsTopicName})
        ) {
            $prefs->pushPreferences( $userWeb,
                                   $TWiki::cfg{UserSubwebs}{UserPrefsTopicName},
                                     'USER ' . $wn );
        }
        else {
            $prefs->pushPreferences( $TWiki::cfg{UsersWebName}, $wn,
                                     'USER ' . $wn );
        }
    }
}

sub _readExtraPreferences {
    my ($this) = @_;
    my $prefs = $this->{prefs};
    my $topics = $prefs->getPreferencesValue( 'EXTRAPREFERENCES' );
        # It's somewhat better to use getWebPreferencesValue() than
        # getPreferencesValue().
        # But getWebPreferencesValue() causes re-processing of WebPreferences 
        # of the current and parent webs.
        # The cost is too much for the marginal benefit of not picking
        # prefernces from an unitended place.
    if ( $topics ) {
	for my $topic ( split(/[,\s]+/, $topics) ) {
	    my ($epWeb, $epTopic) =
		normalizeWebTopicName($this, $this->{webName}, $topic);
	    $prefs->pushPreferences($epWeb, $epTopic, 'EXTRA');
	}
    }
}

=pod

---++ ObjectMethod determineWebTopic($pathInfo, $web, $topic) -> ($web, $topic, $requestedWeb)

Determine the web and topic names from PATH_INFO and web and topic names
explicitly provided.
And then sanitize them.

=cut

sub determineWebTopic {
    my ($this, $pathInfo, $web, $topic) = @_;
    if( $pathInfo =~ /\/((?:.*[\.\/])+)(.*)/ ) {
        # is 'bin/script/Webname/SomeTopic' or 'bin/script/Webname/'
        $web   = $1 unless $web;
        $topic = $2 unless $topic;
        $web =~ s/\./\//go;
        $web =~ s/\/$//o;
    } elsif( $pathInfo =~ /\/(.*)/ ) {
        # is 'bin/script/Webname' or 'bin/script/'
        $web = $1 unless $web;
    }
    # All roads lead to WebHome
    $topic = $TWiki::cfg{HomeTopicName} if ( $topic =~ /\.\./ );
    $topic =~ s/$TWiki::cfg{NameFilter}//go;
    $topic = $TWiki::cfg{HomeTopicName} unless $topic;
    $topic = TWiki::Sandbox::untaintUnchecked( $topic );

    $web   =~ s/$TWiki::cfg{NameFilter}//go;
    my $requestedWeb = TWiki::Sandbox::untaintUnchecked( $web ); #can be an empty string
    $web = $TWiki::cfg{UsersWebName} unless $web;
    $web = TWiki::Sandbox::untaintUnchecked( $web );

    # Convert UTF-8 web and topic name from URL into site charset if necessary 
    # SMELL: merge these two cases, browsers just don't mix two encodings in one URL
    # - can also simplify into 2 lines by making function return unprocessed text if no conversion
    my $webNameTemp = $this->UTF82SiteCharSet( $web );
    if ( $webNameTemp ) {
        $web = $webNameTemp;
    }

    my $topicNameTemp = $this->UTF82SiteCharSet( $topic );
    if ( $topicNameTemp ) {
        $topic = $topicNameTemp;
    }
    return ($web, $topic, $requestedWeb);
}

=pod

---++ ClassMethod new( $loginName, $query, \%initialContext )

Constructs a new TWiki object. Parameters are taken from the query object.

   * =$loginName= is the login username (*not* the wikiname) of the user you
     want to be logged-in if none is available from a session or browser.
     Used mainly for side scripts and debugging.
   * =$query= the TWiki::Request query (may be undef, in which case an empty query
     is used)
   * =\%initialContext= - reference to a hash containing context
     name=value pairs to be pre-installed in the context hash

=cut

sub new {
    my( $class, $login, $query, $initialContext ) = @_;
    ASSERT(!$query || UNIVERSAL::isa($query, 'TWiki::Request'));

    # Compatibility; not used except maybe in plugins
    $TWiki::cfg{TempfileDir} = "$TWiki::cfg{WorkingDir}/tmp"
      unless defined($TWiki::cfg{TempfileDir});

    # Set command_line context if there is no query
    $initialContext ||= defined( $query ) ? {} : { command_line => 1 };

    $query ||= new TWiki::Request();
    my $this = bless( {}, $class );
    $this->{request} = $query;
    $this->{response} = new TWiki::Response();

    # Tell TWiki::Response which charset we are using if not default
    if( defined $TWiki::cfg{Site}{CharSet} && $TWiki::cfg{Site}{CharSet} !~ /^iso-?8859-?1$/io ) {
        $this->{response}->charset( $TWiki::cfg{Site}{CharSet} );
    }

    $this->{_HTMLHEADERS} = {};
    $this->{context} = $initialContext;

    # create the various sub-objects
    unless ($sandbox) {
        # "shared" between mod_perl instances
        $sandbox = new TWiki::Sandbox( $TWiki::cfg{OS}, $TWiki::cfg{DetailedOS} );
    }
    require TWiki::Plugins;
    $this->{plugins} = new TWiki::Plugins( $this );
    require TWiki::Store;
    $this->{store} = new TWiki::Store( $this );

    if( $TWiki::cfg{Mdrepo}{Store} && $TWiki::cfg{Mdrepo}{Dir} &&
        $TWiki::cfg{Mdrepo}{Tables}
    ) {
	require TWiki::Mdrepo;
	$this->{mdrepo} = new TWiki::Mdrepo( $this );
    }

    $this->{remoteUser} = $login;    #use login as a default (set when running from cmd line)
    require TWiki::Users;
    $this->{users} = new TWiki::Users( $this );
    $this->{remoteUser} = $this->{users}->{remoteUser};

    # Make %ENV safer, preventing hijack of the search path
    # SMELL: can this be done in a BEGIN block? Or is the environment
    # set per-query?
    # Item4382: Default $ENV{PATH} must be untainted because TWiki runs
    # with use strict and calling external programs that writes on the disk
    # will fail unless Perl seens it as set to safe value.
    if( $TWiki::cfg{SafeEnvPath} ) {
        $ENV{PATH} = $TWiki::cfg{SafeEnvPath};
    } else {
        $ENV{PATH} = TWiki::Sandbox::untaintUnchecked( $ENV{PATH} );
    }
    delete $ENV{IFS};
    delete $ENV{CDPATH};
    delete $ENV{ENV};
    delete $ENV{BASH_ENV};

    my $url = $query->url();
    if( $url && $url =~ m{^([^:]*://[^/]*).*$} ) {
        $this->{urlHost} = $1;
        # If the urlHost in the url is localhost, this is a lot less
        # useful than the default url host. This is because new CGI("")
        # assigns this host by default - it's a default setting, used
        # when there is nothing better available.
        if( $this->{urlHost} eq 'http://localhost' ) {
            $this->{urlHost} = $TWiki::cfg{DefaultUrlHost};
        } elsif( $TWiki::cfg{RemovePortNumber} ) {
            $this->{urlHost} =~ s/\:[0-9]+$//;
        }
    } else {
        $this->{urlHost} = $TWiki::cfg{DefaultUrlHost};
    }
    if (   $TWiki::cfg{GetScriptUrlFromCgi}
        && $url
        && $url =~ m{^[^:]*://[^/]*(.*)/.*$}
        && $1 )
    {

        # SMELL: this is a really dangerous hack. It will fail
        # spectacularly with mod_perl.
        # SMELL: why not just use $query->script_name?
        $this->{scriptUrlPath} = $1;
    }

    my $web = '';
    my $topic = $query->param( 'topic' );
    if( $topic ) {
        if( $topic =~ m#^$regex{linkProtocolPattern}://#o &&
            $this->{request} ) {
            # redirect to URI
            $this->{webName} = '';
            $this->redirect( $topic );
            return $this;
        } elsif( $topic =~ /((?:.*[\.\/])+)(.*)/ ) {
            # is 'bin/script?topic=Webname.SomeTopic'
            $web   = $1;
            $topic = $2;
            $web =~ s/\./\//go;
            $web =~ s/\/$//o;
            # jump to WebHome if 'bin/script?topic=Webname.'
            $topic = $TWiki::cfg{HomeTopicName} if( $web && ! $topic );
        }
        # otherwise assume 'bin/script/Webname?topic=SomeTopic'
    } else {
        $topic = '';
    }

    my $pathInfo = $query->path_info();

    # Save the path info with tilde for a later process.
    # A login name may contain dots hence the entire pathInfo needs to be saved
    # before being processed.
    if ( $pathInfo =~ m:^/~: ) {
        $this->{pathInfoWithTilde} = $pathInfo;
    }

    @$this{'webName', 'topicName', 'requestedWebName'} =
        $this->determineWebTopic($pathInfo, $web, $topic);

    # Item3270 - here's the appropriate place to enforce TWiki spec:
    # All topic name sources are evaluated, site charset applied
    # SMELL: This untaint unchecked is duplicate of one just above
    $this->{topicName} = TWiki::Sandbox::untaintUnchecked(ucfirst $this->{topicName});

    $this->{scriptUrlPath} = $TWiki::cfg{ScriptUrlPath};

    require TWiki::Prefs;
    my $prefs = new TWiki::Prefs( $this );
    $this->{prefs} = $prefs;

    # Form definition cache
    $this->{forms} = {};

    # Push global preferences from TWiki.TWikiPreferences
    $prefs->pushGlobalPreferences();

    # SMELL: what happens if we move this into the TWiki::User::new?
    $this->{user} = $this->{users}->initialiseUser($this->{remoteUser});

    # Static session variables that can be expanded in topics when they
    # are enclosed in % signs
    # SMELL: should collapse these into one. The duplication is pretty
    # pointless. Could get rid of the SESSION_TAGS hash, might be
    # the easiest thing to do, but then that would allow other
    # upper-case named fields in the object to be accessed as well...
    $this->{SESSION_TAGS}{BASEWEB}        = $this->{webName};
    $this->{SESSION_TAGS}{BASETOPIC}      = $this->{topicName};
    $this->{SESSION_TAGS}{INCLUDINGTOPIC} = $this->{topicName};
    $this->{SESSION_TAGS}{INCLUDINGWEB}   = $this->{webName};
    $this->{SESSION_TAGS}{SITENAME}       =
        $TWiki::cfg{ReadOnlyAndMirrorWebs}{SiteName} || '';

    # Push plugin settings
    $this->{plugins}->settings();

    # Now the rest of the preferences
    $prefs->pushGlobalPreferencesSiteSpecific();
    $this->_readUserPreferences() unless ( $TWiki::cfg{DemoteUserPreferences} );
    $prefs->pushWebPreferences( $this->{webName} );
    $this->_readExtraPreferences();
    $prefs->pushPreferences( $this->{webName}, $this->{topicName}, 'TOPIC' );

    $prefs->pushPreferenceValues( 'SESSION',
                                  $this->{users}->{loginManager}->getSessionValues() );

    $this->_readUserPreferences() if ( $TWiki::cfg{DemoteUserPreferences} );

    # Finish plugin initialization - register handlers
    $this->{plugins}->enable();

    # SMELL: Every place should localize it before use, so it's not necessary here.
    $TWiki::Plugins::SESSION = $this;

    my ($mode, $master) = $this->modeAndMaster($this->{webName});
    $this->{contentMode} = $mode;
    if ( $master ) {
        $this->{master} = $master;
    }

    return $this;
}

=begin twiki

---++ ObjectMethod renderer()
Get a reference to the renderer object. Done lazily because not everyone
needs the renderer.

=cut

sub renderer {
    my( $this ) = @_;

    unless( $this->{renderer} ) {
        require TWiki::Render;
        # requires preferences (such as LINKTOOLTIPINFO)
        $this->{renderer} = new TWiki::Render( $this );
    }
    return $this->{renderer};
}

=begin twiki

---++ ObjectMethod attach()
Get a reference to the attach object. Done lazily because not everyone
needs the attach.

=cut

sub attach {
    my( $this ) = @_;

    unless( $this->{attach} ) {
        require TWiki::Attach;
        $this->{attach} = new TWiki::Attach( $this );
    }
    return $this->{attach};
}

=begin twiki

---++ ObjectMethod templates()
Get a reference to the templates object. Done lazily because not everyone
needs the templates.

=cut

sub templates {
    my( $this ) = @_;

    unless( $this->{templates} ) {
        require TWiki::Templates;
        $this->{templates} = new TWiki::Templates( $this );
    }
    return $this->{templates};
}

=begin twiki

---++ ObjectMethod i18n()
Get a reference to the i18n object. Done lazily because not everyone
needs the i18ner.

=cut

sub i18n {
    my( $this ) = @_;

    unless( $this->{i18n} ) {
        require TWiki::I18N;
        # language information; must be loaded after
        # *all possible preferences sources* are available
        $this->{i18n} = new TWiki::I18N( $this );
    }
    return $this->{i18n};
}

=begin twiki

---++ ObjectMethod search()
Get a reference to the search object. Done lazily because not everyone
needs the searcher.

=cut

sub search {
    my( $this ) = @_;

    unless( $this->{search} ) {
        require TWiki::Search;
        $this->{search} = new TWiki::Search( $this );
    }
    return $this->{search};
}

=begin twiki

---++ ObjectMethod security()
Get a reference to the security object. Done lazily because not everyone
needs the security.

=cut

sub security {
    my( $this ) = @_;

    unless( $this->{security} ) {
        require TWiki::Access;
        $this->{security} = new TWiki::Access( $this );
    }
    return $this->{security};
}

=begin twiki

---++ ObjectMethod net()
Get a reference to the net object. Done lazily because not everyone
needs the net.

=cut

sub net {
    my( $this ) = @_;

    unless( $this->{net} ) {
        require TWiki::Net;
        $this->{net} = new TWiki::Net( $this );
    }
    return $this->{net};
}

=begin twiki

---++ ObjectMethod finish()
Break circular references.

=cut

# Note to developers; please undef *all* fields in the object explicitly,
# whether they are references or not. That way this method is "golden
# documentation" of the live fields in the object.
sub finish {
    my $this = shift;

    $_->finish() foreach values %{$this->{forms}};
    $this->{plugins}->finish() if $this->{plugins};
    $this->{users}->finish() if $this->{users};
    $this->{prefs}->finish() if $this->{prefs};
    $this->{templates}->finish() if $this->{templates};
    $this->{renderer}->finish() if $this->{renderer};
    $this->{net}->finish() if $this->{net};
    $this->{store}->finish() if $this->{store};
    $this->{mdrepo}->finish() if $this->{mdrepo};
    $this->{search}->finish() if $this->{search};
    $this->{attach}->finish() if $this->{attach};
    $this->{security}->finish() if $this->{security};
    $this->{i18n}->finish() if $this->{i18n};

    undef $this->{_HTMLHEADERS};
    undef $this->{request};
    undef $this->{urlHost};
    undef $this->{web};
    undef $this->{topic};
    undef $this->{webName};
    undef $this->{topicName};
    undef $this->{_ICONMAP};
    undef $this->{context};
    undef $this->{remoteUser};
    undef $this->{requestedWebName}; # Web name before renaming
    undef $this->{scriptUrlPath};
    undef $this->{user};
    undef $this->{SESSION_TAGS};
    undef $this->{_INCLUDES};
    undef $this->{ignoreTOC};
    undef $this->{response};
    undef $this->{evaluating_if};
    undef $this->{contentMode};
    undef $this->{master};
    undef $this->{modeAndMaster};
}

=pod

---++ ObjectMethod writeLog( $action, $webTopic, $extra, $user )

   * =$action= - what happened, e.g. view, save, rename
   * =$wbTopic= - what it happened to
   * =$extra= - extra info, such as minor flag
   * =$user= - user who did the saving (user id)
Write the log for an event to the logfile

=cut

sub writeLog {
    my $this = shift;

    my $action = shift || '';
    my $webTopic = shift || '';
    my $extra = shift || '';
    my $user = shift || $this->{user};

    my $login = $user;
    if( $this->{users} ) {
        $login = $this->{users}->getLoginName( $user )             # fast
              || $this->{users}->getLoginName(
                     $this->{users}->getCanonicalUserID( $user ) ) # slower
              || 'unknown';
    }

    my $cgiQuery = $this->{request};
    if( $cgiQuery && $action eq 'view' ) {
        my $agent = $cgiQuery->user_agent();
        if( $agent && $agent =~ m/([\w]+)/ ) {
            $extra = "$1 $extra";
            $extra =~ s/ +$//;
        }
    }

    my $remoteAddr = $this->{request}->remoteAddress() || '';
    my $text = "$login | $action | $webTopic | $extra | $remoteAddr |";

    _writeReport( $this, $TWiki::cfg{LogFileName}, $text );
}

=pod

---++ ObjectMethod writeWarning( $text )

Prints date, time, and contents $text to $TWiki::cfg{WarningFileName}, typically
'warnings.txt'. Use for warnings and errors that may require admin
intervention. Use this for defensive programming warnings (e.g. assertions).

=cut

sub writeWarning {
    my $this = shift;
    my $text = shift;
    $text =~ s/[\r\n]+$//s;
    _writeReport( $this, $TWiki::cfg{WarningFileName}, "$text |" );
}

=pod

---++ ObjectMethod writeDebug( $text )

Prints date, time, and contents of $text to $TWiki::cfg{DebugFileName}, typically
'debug.txt'.  Use for debugging messages.

=cut

sub writeDebug {
    my $this = shift;
    my $text = shift;
    _writeReport( $this, $TWiki::cfg{DebugFileName}, "$text |" );
}

# resolve %DATE% (and maybe other things in the future) in a "file name" config
# parameter
sub _fileNameToPath {
    my $path = shift;
    if ( $path =~ /%DATE%/ ) {
        $path =~ s//TWiki::Time::formatTime( time(), '$year$mo', 'gmtime')/ge;
    }
    return $path;
}

# Concatenates date, time, and $text to a log file.
# The logfilename can optionally use a %DATE% variable to support
# logs that are rotated once a month.
# | =$log= | Base filename for log file |
# | =$message= | Message to print |
sub _writeReport {
    my ( $this, $log, $message ) = @_;

    if ( $log ) {
        $log = _fileNameToPath( $log );
        my $time = TWiki::Time::formatTime( time(), '$year-$mo-$day - $hour:$min:$sec' );
        # ommitting the third argument ($outputTimeZone) to resort to $TWiki::cfg{DisplayTimeValues} as per Item7811

        if( open( FILE, ">>$log" ) ) {
            print FILE "| $time | $message\n";
            close( FILE );
        } else {
            print STDERR 'Could not write "'.$message.'" to '."$log: $!\n";
        }
    }
}

sub _removeNewlines {
    my( $theTag ) = @_;
    $theTag =~ s/[\r\n]+/ /gs;
    return $theTag;
}

# Convert relative URLs to absolute URIs
sub _rewriteURLInInclude {
    my( $theHost, $theAbsPath, $url ) = @_;

    # leave out an eventual final non-directory component from the absolute path
    $theAbsPath =~ s/(.*?)[^\/]*$/$1/;

    if( $url =~ /^\// ) {
        # fix absolute URL
        $url = $theHost.$url;
    } elsif( $url =~ /^\./ ) {
        # fix relative URL
        $url = $theHost.$theAbsPath.'/'.$url;
    } elsif( $url =~ /^$regex{linkProtocolPattern}:/o ) {
        # full qualified URL, do nothing
    } elsif( $url =~ /^#/ ) {
        # anchor. This needs to be left relative to the including topic
        # so do nothing
    } elsif( $url ) {
        # FIXME: is this test enough to detect relative URLs?
        $url = $theHost.$theAbsPath.'/'.$url;
    }

    return $url;
}

# Add a web reference to a [[...][...]] link in an included topic
sub _fixIncludeLink {
    my( $web, $link, $label ) = @_;

    # Detect absolute and relative URLs, web-qualified wikinames and Interwiki links
    if( $link =~ m/^$regex{excludeFixIncludeLinkRegex}/o ) {
        if( $label ) {
            return "[[$link][$label]]";
        } else {
            return "[[$link]]";
        }
    } elsif( !$label ) {
        # Must be wikiword or spaced-out wikiword (or illegal link :-/)
        $label = $link;
    }
    return "[[$web.$link][$label]]";
}

# Replace web references in a topic. Called from forEachLine, applying to
# each non-verbatim and non-literal line.
sub _fixupIncludedTopic {
    my( $text, $options ) = @_;

    my $fromWeb = $options->{web};

    unless( $options->{in_noautolink} || $options->{force_noautolink} ) {
        # Prefix web name to WikiWord to make links work, such as:
        # 'TopicName' to 'Web.TopicName'
        # TWikibug:Item6840: Exclude 'WikiWordWeb.TopicName' using translation token
        $text =~ s/(?:^|(?<=[\s(]))($regex{webNameRegex}\.($regex{wikiWordRegex}|$regex{abbrevRegex}))/-$TranslationToken$1/go;
        $text =~ s#(?:^|(?<=[\s(]))($regex{wikiWordRegex})#$fromWeb.$1#go;
        $text =~ s/-$TranslationToken//go;
    }

    # Handle explicit [[]] everywhere
    # '[[TopicName][...]]' to '[[Web.TopicName][...]]'
    $text =~ s/\[\[([^]]+)\](?:\[([^]]+)\])?\]/
      _fixIncludeLink( $fromWeb, $1, $2 )/geo;

    return $text;
}

# Clean-up HTML text so that it can be shown embedded in a topic
sub _cleanupIncludedHTML {
    my( $text, $host, $path, $options ) = @_;

    # FIXME: Make aware of <base> tag

    $text =~ s/^.*?<\/head>//is
      unless ( $options->{disableremoveheaders} );   # remove all HEAD
    $text =~ s/<script.*?<\/script>//gis
      unless ( $options->{disableremovescript} );    # remove all SCRIPTs
    $text =~ s/^.*?<body[^>]*>//is
      unless ( $options->{disableremovebody} );      # remove all to <BODY>
    $text =~ s/(?:\n)<\/body>.*//is
      unless ( $options->{disableremovebody} );      # remove </BODY>
    $text =~ s/(?:\n)<\/html>.*//is
      unless ( $options->{disableremoveheaders} );   # remove </HTML>
    $text =~ s/(<[^>]*>)/_removeNewlines($1)/ges
      unless ( $options->{disablecompresstags} );    # replace newlines in html tags with space
    $text =~ s/(\s(?:href|src|action)=(["']))(.*?)\2/$1._rewriteURLInInclude( $host, $path, $3 ).$2/geois
      unless ( $options->{disablerewriteurls} );

    return $text;
}

=pod

---++ StaticMethod applyPatternToIncludedText( $text, $pattern ) -> $text

Apply a pattern on included text to extract a subset

=cut

sub applyPatternToIncludedText {
    my( $theText, $thePattern ) = @_;
    $thePattern =~ s/([^\\])([\$\@\%\&\#\'\`\/])/$1\\$2/g;  # escape some special chars
    $thePattern = TWiki::Sandbox::untaintUnchecked( $thePattern );
    $theText = '' unless( $theText =~ s/$thePattern/$1/is );
    return $theText;
}

# This is actually for encoding conversion rather than chararacter set.
# But following the usual terminology, 'charset' is used.
sub _convertCharsets {
    my ($this, $srcCharset, $dstCharset, $textRef) = @_;
    if ( $] >= 5.008 ) { # Perl 5.8 or later
        require Encode;
        my $srcCanonical = Encode::resolve_alias($srcCharset);
        my $dstCanonical = Encode::resolve_alias($dstCharset);
        if ( $srcCanonical && $dstCanonical ) {
            if ( $srcCanonical ne $dstCanonical ) {
                $$textRef = Encode::encode($dstCanonical,
                                    Encode::decode($srcCanonical, $$textRef));
            }
        }
        else {
            $this->writeWarning(
                ($srcCanonical ? '' : "charset $srcCharset not supported. ") .
                ($dstCanonical ? '' : "charset $dstCharset not supported. "));
        }
    }
    else { # Pre-5.8 Perl versions
        require Unicode::MapUTF8;
        my $srcOK = Unicode::MapUTF8::utf8_supported_charset($srcCharset);
        my $dstOK = Unicode::MapUTF8::utf8_supported_charset($dstCharset);
        if ( $srcOK && $dstOK ) {
            my $text = Unicode::MapUTF8::to_utf8(
                {-string => $$textRef, -charset => $srcCharset});
            $$textRef = Unicode::MapUTF8::from_utf8(
                {-string => $text, -charset => $dstCharset});
        }
        else {
            $this->writeWarning(
                ($srcOK ? '' : "charset $srcCharset not supported. ") .
                ($dstOK ? '' : "charset $dstCharset not supported. "));
        }
    }
}

# newline, encode, and nofinalnewline parameters
sub _includePostProcessing {
    my ($this, $textRef, $params) = @_;
    my $newLine = $params->{newline};
    if( defined $newLine ) {
        $newLine =~ s/\$br\b/\0-br-\0/go;
        $newLine =~ s/\$n\b/\0-n-\0/go;
        $$textRef =~ s/\r?\n/$newLine/go;
    }
    if( my $encode = $params->{encode} ) {
        $$textRef = $this->ENCODE( { _DEFAULT => $$textRef, type => $encode } );
    }
    if( defined $newLine ) {
        $$textRef =~ s/\0-br-\0/<br \/>/go;
        $$textRef =~ s/\0-n-\0/\n/go;
    }
    $$textRef =~ s/(\r?\n)+$// if ( isTrue($params->{nofinalnewline}) );
}

# Fetch content from a URL for inclusion by an INCLUDE
sub _includeUrl {
    my( $this, $url, $pattern, $web, $topic, $raw, $options, $warn,
        $allowAnyType, $charSetParam ) = @_;
    my $text = '';

    # For speed, read file directly if URL matches an attachment directory
    my $urlHostRegex = $TWiki::cfg{UrlHostRegex} || $this->{urlHost};
    if( $url =~ /^$urlHostRegex$TWiki::cfg{PubUrlPath}\/($regex{webNameRegex})\/([^\/\.]+)\/([^\/]+)$/o ) {
        my $incWeb = $1;
        my $incTopic = $2;
        my $incAtt = $3;
        my $mimeType = suffixToMimeType($incAtt);
        if( $allowAnyType || $mimeType =~ /^text\/(html|plain|css)/ ) {
            unless( $this->{store}->attachmentExists(
                $incWeb, $incTopic, $incAtt )) {
                return _includeWarning( $this, $warn, 'bad_attachment', $url );
            }
            if( $incWeb ne $web || $incTopic ne $topic ) {
                # CODE_SMELL: Does not account for not yet authenticated user
                unless( $this->security->checkAccessPermission(
                    'VIEW', $this->{user}, undef, undef, $incTopic, $incWeb ) ) {
                    return _includeWarning( $this, $warn, 'access_denied',
                                                   "$incWeb.$incTopic" );
                }
            }
            $text = $this->{store}->readAttachment( undef, $incWeb, $incTopic,
                                                    $incAtt );
            $text = _cleanupIncludedHTML( $text, $this->{urlHost},
                                          $TWiki::cfg{PubUrlPath}, $options )
              unless $raw;
            $text = applyPatternToIncludedText( $text, $pattern )
              if( $pattern );
            $text = "<literal>\n" . $text . "\n</literal>" if ( $options->{literal} );
            return $text;
        }
        else {
            return _includeWarning( $this, $warn, 'bad_content', $mimeType );
        }
    }

    return _includeWarning( $this, $warn, 'urls_not_allowed' )
      unless $TWiki::cfg{INCLUDE}{AllowURLs};

    # SMELL: should use the URI module from CPAN to parse the URL
    # SMELL: but additional CPAN adds to code bloat
    unless ($url =~ m!^https?:!) {
        $text = _includeWarning( $this, $warn, 'bad_protocol', $url );
        return $text;
    }

    # Item7570. This causes both false positive and false negative
    if ( $url =~ /^$urlHostRegex/o ) {
        if ( $topic eq $cfg{HomeTopicName} ) {
            if ( $url =~ m:/$web\b: ) {
                return _includeWarning( $this, $warn, 'recursive_include', $url );
            }
        }
        else {
            if ( $url =~ m:/$web[./]$topic\b: ) {
                return _includeWarning( $this, $warn, 'recursive_include', $url );
            }
        }
    }

    my $response = $this->net->getExternalResource( $url );
    if( !$response->is_error()) {
        my $contentType = $response->header('content-type') ||
            'application/octet-stream'; # RFC2616 section 7.2.1
        $text = $response->content();
        # converting character encodings
        my $siteCharset = $TWiki::cfg{Site}{CharSet} || 'iso-8859-1';
        my $includedCharset = '';
        if ( $charSetParam ) {
            $includedCharset = $charSetParam;
        }
        else {
            if ( $contentType =~ /charset=([\w-]+)/i ) {
                $includedCharset = $1;
            }
            elsif ( $text =~
                    /<meta\s+http-equiv=[^>]+content-type[^>]+charset=([-\w]+)/i
            ) {
                $includedCharset = $1;
            }
            else {
                $includedCharset = 'iso-8859-1';
            }
        }
        $this->_convertCharsets($includedCharset, $siteCharset, \$text);
        if( $contentType =~ /^text\/html/ ) {
            if (!$raw) {
                $url =~ m!^([a-z]+:/*[^/]*)(/[^#?]*)!;
                $text = _cleanupIncludedHTML( $text, $1, $2, $options );
            }
        } elsif( $contentType =~ /^text\/(plain|css)/ ) {
            # do nothing
        } else {
            unless ( $allowAnyType ) {
                $text = _includeWarning( $this, $warn, 'bad_content',
                                         $contentType );
            }
        }
        $text = applyPatternToIncludedText( $text, $pattern ) if( $pattern );
        $text = "<literal>\n" . $text . "\n</literal>" if ( $options->{literal} );
        $this->_includePostProcessing(\$text, $options);
    } else {
        $text = _includeWarning( $this, $warn, 'geturl_failed',
                                 $url.' '.$response->message() );
    }

    return $text;
}

#
# SMELL: this is _not_ a tag handler in the sense of other builtin tags,
# because it requires far more context information (the text of the topic)
# than any handler.
# SMELL: as a tag handler that also semi-renders the topic to extract the
# headings, this handler would be much better as a preRenderingHandler in
# a plugin (where head, script and verbatim sections are already protected)
#
#    * $text  : ref to the text of the current topic
#    * $topic : the topic we are in
#    * $web   : the web we are in
#    * $args  : 'Topic' [web='Web'] [depth='N']
# Return value: $tableOfContents
# Handles %<nop>TOC{...}% syntax.  Creates a table of contents
# using TWiki bulleted
# list markup, linked to the section headings of a topic. A section heading is
# entered in one of the following forms:
#    * $headingPatternSp : \t++... spaces section heading
#    * $headingPatternDa : ---++... dashes section heading
#    * $headingPatternHt : &lt;h[1-6]> HTML section heading &lt;/h[1-6]>
sub _TOC {
    my ( $this, $text, $defaultTopic, $defaultWeb, $args ) = @_;

    return '' if( $this->{ignoreTOC} ); # prevent infinite recursion

    require TWiki::Attrs;

    my $params = new TWiki::Attrs( $args );
    # get the topic name attribute
    my $topic = $params->{_DEFAULT} || $defaultTopic;

    # get the web name attribute
    $defaultWeb =~ s#/#.#g;
    my $web = $params->{web} || $defaultWeb;

    my $isSameTopic = $web eq $defaultWeb  &&  $topic eq $defaultTopic;

    $web =~ s#/#\.#g;
    my $webPath = $web;
    $webPath =~ s/\./\//g;

    # get the depth limit attribute
    my $maxDepth = $params->{depth} || $this->{prefs}->getPreferencesValue('TOC_MAX_DEPTH') || 6;
    my $minDepth = $params->{mindepth} || $this->{prefs}->getPreferencesValue('TOC_MIN_DEPTH') || 1;
    
    # get the title attribute
    my $title = $params->{title} || $this->{prefs}->getPreferencesValue('TOC_TITLE') || '';
    $title = CGI::span( { class => 'twikiTocTitle' }, $title ) if( $title );

    # get the style attribute
    my $style = $params->{style} || $this->{prefs}->getPreferencesValue('TOC_STYLE') || '';

    # Item7286: Load topic text if TOC is built for another topic,
    # or if in skin context of the current topic
    unless( $isSameTopic && $this->inContext( 'body_text' ) ) {
        unless( $this->security->checkAccessPermission
                ( 'VIEW', $this->{user}, undef, undef, $topic, $web ) ) {
            return $this->inlineAlert( 'alerts', 'access_denied', $web, $topic );
        }
        my $meta;
        ( $meta, $text ) = $this->{store}->readTopic( $this->{user}, $web, $topic );
        # prevent infinite recursion - could happen if there is a TOC in the text or in INCLUDE
        $this->{ignoreTOC} = 1;
        # Item6864: 2012-03-29 TWiki:Main.GertjanVanOosten, gertjan at west dot nl:
        #   Handle common tags, as the text may contain variables etc. that need
        #   to be expanded before generating the TOC for another topic.
        $text = $this->handleCommonTags( $text, $web, $topic, $meta );
        $this->{ignoreTOC} = undef;
    }

    my $insidePre = 0;
    my $insideVerbatim = 0;
    my $highest = 99;
    my $result  = '';
    my $verbatim = {};
    $text = $this->renderer->takeOutBlocks( $text, 'verbatim', $verbatim);
    $text = $this->renderer->takeOutBlocks( $text, 'pre', $verbatim);

    # Find URL parameters
    my $query = $this->{request};
    my @qparams = ();
    foreach my $name ( $query->param ) {
        next if ($name eq 'keywords');
        next if ($name eq 'topic');
        next if ($name eq 'text');
        push @qparams, $name => $query->param($name);
    }

    # clear the set of unique anchornames in order to inhibit the 'relabeling' of
    # anchor names if the same topic is processed more than once, cf. explanation
    # in handleCommonTags()
    $this->renderer->_eraseAnchorNameMemory();

    # NB: While we're processing $text line by line here,
    # $this->renderer->getRendereredVersion() 'allocates' unique anchor names by
    # first replacing '#WikiWord', followed by regex{headerPatternHt} and
    # regex{headerPatternDa}. In order to stay in sync and not 'clutter'/slow
    # down the renderer code, we have to adhere to this order here as well
    my @regexps = ('^(\#)('.$regex{wikiWordRegex}.')',
                   $regex{headerPatternHt},
                   $regex{headerPatternDa});
    my @lines = split( /\r?\n/, $text );
    my %anchors = ();
    my %headings = ();
    my %levels = ();
    for my $i (0 .. $#regexps) {
        my $lineno = 0;
        # SMELL: use forEachLine
        foreach my $line (@lines) {
            $lineno++;
            if ($line =~ m/$regexps[$i]/) {
                my ($level, $heading) = ($1, $2);
                my $anchor = $this->renderer->makeUniqueAnchorName($web, $topic, $heading);

                if ($i > 0) {
                    # SMELL: needed only because Render::_makeAnchorHeading uses it
                    my $compatAnchor = $this->renderer->makeAnchorName($anchor, 1);
                    $compatAnchor = $this->renderer->makeUniqueAnchorName($web, $topic, $anchor, 1)
                        if ($compatAnchor ne $anchor);

                    $heading =~ s/\s*$regex{headerPatternNoTOC}.+$//go;
                    next unless $heading;

                    $level = length $level if ($i == 2);
                    if( ($level >= $minDepth) && ($level <= $maxDepth) ) {
                        $anchors{$lineno} = $anchor;
                        $headings{$lineno} = $heading;
                        $levels{$lineno} = $level;
                    }
                }
            }
        }
    }

    # SMELL: this handling of <pre> is archaic.
    foreach my $lineno (sort{$a <=> $b}(keys %headings)) {
        my ($level, $line, $anchor) = ($levels{$lineno}, $headings{$lineno}, $anchors{$lineno});
        $highest = $level if( $level < $highest );
        my $tabs = "\t" x $level;
        # Remove *bold*, _italic_ and =fixed= formatting
        $line =~ s/(^|[\s\(])\*([^\s]+?|[^\s].*?[^\s])\*($|[\s\,\.\;\:\!\?\)])/$1$2$3/g;
        $line =~ s/(^|[\s\(])_+([^\s]+?|[^\s].*?[^\s])_+($|[\s\,\.\;\:\!\?\)])/$1$2$3/g;
        $line =~ s/(^|[\s\(])=+([^\s]+?|[^\s].*?[^\s])=+($|[\s\,\.\;\:\!\?\)])/$1$2$3/g;
        # Prevent WikiLinks
        $line =~ s/\[\[.*?\]\[(.*?)\]\]/$1/g;  # '[[...][...]]'
        $line =~ s/\[\[(.*?)\]\]/$1/ge;        # '[[...]]'
        $line =~ s/([\s\(])($regex{webNameRegex})\.($regex{wikiWordRegex})/$1<nop>$3/go;  # 'Web.TopicName'
        $line =~ s/([\s\(])($regex{wikiWordRegex})/$1<nop>$2/go;  # 'TopicName'
        $line =~ s/([\s\(])($regex{abbrevRegex})/$1<nop>$2/go;    # 'TLA'
        $line =~ s/([\s\-\*\(])([$regex{mixedAlphaNum}]+\:)/$1<nop>$2/go; # 'Site:page' Interwiki link
        # Prevent manual links
        $line =~ s/<[\/]?a\b[^>]*>//gi;
        # create linked bullet item, using a relative link to anchor
        my $target = $isSameTopic ?
                     _make_params(0, '#'=>$anchor,@qparams) :
                     $this->getScriptUrl(0,'view',$web,$topic,'#'=>$anchor,@qparams);
        $line = $tabs.'* ' .  CGI::a({href=>$target},$line);
        $result .= "\n".$line;
    }

    if( $result ) {
        if( $highest > 1 ) {
            # left shift TOC
            $highest--;
            $result =~ s/^\t{$highest}//gm;
        }
        my $args;
        $args->{class} = 'twikiToc';
        $args->{style} = $style if( $style );
        return CGI::div( $args, "$title$result\n" );
    } else {
        return '';
    }
}

=pod

---++ ObjectMethod inlineAlert($template, $def, ... ) -> $string

Format an error for inline inclusion in rendered output. The message string
is obtained from the template 'oops'.$template, and the DEF $def is
selected. The parameters (...) are used to populate %PARAM1%..%PARAMn%

=cut

sub inlineAlert {
    my $this = shift;
    my $template = shift;
    my $def = shift;

    my $text = $this->templates->readTemplate( 'oops'.$template,
                                                 $this->getSkin() );
    if( $text ) {
        my $blah = $this->templates->expandTemplate( $def );
        $text =~ s/%INSTANTIATE%/$blah/;
        # web and topic can be anything; they are not used
        $text = $this->handleCommonTags( $text, $this->{webName},
                                         $this->{topicName} );
        my $n = 1;
        while( defined( my $param = shift )) {
            $text =~ s/%PARAM$n%/$param/g;
            $n++;
        }

    } else {
        $text = CGI::h1('TWiki Installation Error')
              . 'Template "'.$template.'" not found.'.CGI::p()
              . 'Check your configuration settings for {TemplateDir} and {TemplatePath}';
    }

    $text =~ s/^\s+//s;
    $text =~ s/\s+$//s;

    return $text;
}

=pod

---++ StaticMethod parseSections($text) -> ($string,$sectionlistref)

Generic parser for sections within a topic. Sections are delimited
by STARTSECTION and ENDSECTION, which may be nested, overlapped or
otherwise abused. The parser builds an array of sections, which is
ordered by the order of the STARTSECTION within the topic. It also
removes all the SECTION tags from the text, and returns the text
and the array of sections.

Each section is a =TWiki::Attrs= object, which contains the attributes
{type, name, start, end}
where start and end are character offsets in the
string *after all section tags have been removed*. All sections
are required to be uniquely named; if a section is unnamed, it
will be given a generated name. Sections may overlap or nest.

See test/unit/Fn_SECTION.pm for detailed testcases that
round out the spec.

=cut

sub parseSections {
    #my( $text _ = @_;
    my %sections;
    my @list = ();

    my $seq = 0;
    my $ntext = '';
    my $offset = 0;
    foreach my $bit (split(/(%(?:START|END)SECTION(?:{.*?})?%)/, $_[0] )) {
        if( $bit =~ /^%STARTSECTION(?:{(.*)})?%$/) {
            require TWiki::Attrs;
            my $attrs = new TWiki::Attrs( $1 );
            $attrs->{type} ||= 'section';
            $attrs->{name} = $attrs->{_DEFAULT} || $attrs->{name} || '_SECTION'.$seq++;
            delete $attrs->{_DEFAULT};
            my $id = $attrs->{type}.':'.$attrs->{name};
            if( $sections{$id} ) {
                # error, this named section already defined, ignore
                next;
            }
            # close open unnamed sections of the same type
            foreach my $s ( @list ) {
                if( $s->{end} < 0 && $s->{type} eq $attrs->{type} &&
                      $s->{name} =~ /^_SECTION\d+$/ ) {
                    $s->{end} = $offset;
                }
            }
            $attrs->{start} = $offset;
            $attrs->{end} = -1; # open section
            $sections{$id} = $attrs;
            push( @list, $attrs );
        } elsif( $bit =~ /^%ENDSECTION(?:{(.*)})?%$/ ) {
            require TWiki::Attrs;
            my $attrs = new TWiki::Attrs( $1 );
            $attrs->{type} ||= 'section';
            $attrs->{name} = $attrs->{_DEFAULT} || $attrs->{name} || '';
            delete $attrs->{_DEFAULT};
            unless( $attrs->{name} ) {
                # find the last open unnamed section of this type
                foreach my $s ( reverse @list ) {
                    if( $s->{end} == -1 &&
                          $s->{type} eq $attrs->{type} &&
                         $s->{name} =~ /^_SECTION\d+$/ ) {
                        $attrs->{name} = $s->{name};
                        last;
                    }
                }
                # ignore it if no matching START found
                next unless $attrs->{name};
            }
            my $id = $attrs->{type}.':'.$attrs->{name};
            if( !$sections{$id} || $sections{$id}->{end} >= 0 ) {
                # error, no such open section, ignore
                next;
            }
            $sections{$id}->{end} = $offset;
        } else {
            $ntext .= $bit;
            $offset = length( $ntext );
        }
    }

    # close open sections
    foreach my $s ( @list ) {
        $s->{end} = $offset if $s->{end} < 0;
    }

    return( $ntext, \@list );
}

=pod

---++ ObjectMethod expandVariablesOnTopicCreation ( $text, $user, $web, $topic ) -> $text

   * =$text= - text to expand
   * =$user= - This is the user expanded in e.g. %USERNAME. Optional, defaults to logged-in user.
   * =$web= - name of web, optional
   * =$topic= - name of topic, optional

Expand limited set of variables during topic creation. These are variables
expected in templates that must be statically expanded in new content.

# SMELL: no plugin handler

=cut

sub expandVariablesOnTopicCreation {
    my ( $this, $text, $user, $theWeb, $theTopic ) = @_;

    $user     ||= $this->{user};
    $theWeb   ||= $this->{SESSION_TAGS}{WEB}   || $this->{SESSION_TAGS}{BASEWEB};
    $theTopic ||= $this->{SESSION_TAGS}{TOPIC} || $this->{SESSION_TAGS}{BASETOPIC};

    # Chop out templateonly sections
    my( $ntext, $sections ) = parseSections( $text );
    if( scalar( @$sections )) {
        # Note that if named templateonly sections overlap, the behaviour is undefined.
        foreach my $s ( reverse @$sections ) {
            if( $s->{type} eq 'templateonly' ) {
                $ntext = substr($ntext, 0, $s->{start})
                       . substr($ntext, $s->{end}, length($ntext));
            } else {
                # put back non-templateonly sections
                my $start = $s->remove('start');
                my $end = $s->remove('end');
                $ntext = substr($ntext, 0, $start)
                       . '%STARTSECTION{'.$s->stringify() . '}%'
                       . substr($ntext, $start, $end - $start)
                       . '%ENDSECTION{' . $s->stringify().'}%'
                       . substr($ntext, $end, length($ntext));
            }
        }
        $text = $ntext;
    }

    # Make sure func works, for registered tag handlers
    $TWiki::Plugins::SESSION = $this;

    # Note: it may look dangerous to override the user this way, but
    # it's actually quite safe, because only a subset of tags are
    # expanded during topic creation. if the set of tags expanded is
    # extended, then the impact has to be considered.
    my $safe = $this->{user};
    $this->{user} = $user;
    $text = _processTags( $this, $text, \&_expandTagOnTopicCreation, 16 );

    # expand all variables for type="expandvariables" sections
    ( $ntext, $sections ) = parseSections( $text );
    if( scalar( @$sections )) {
        $theWeb   ||= $this->{session}->{webName};
        $theTopic ||= $this->{session}->{topicName};
        foreach my $s ( reverse @$sections ) {
            if( $s->{type} eq 'expandvariables' ) {
                my $etext = substr( $ntext, $s->{start}, $s->{end} - $s->{start} );
                expandAllTags( $this, \$etext, $theTopic, $theWeb );
                $ntext = substr( $ntext, 0, $s->{start})
                       . $etext
                       . substr( $ntext, $s->{end}, length($ntext) );
            } else {
                # put back non-expandvariables sections
                my $start = $s->remove('start');
                my $end = $s->remove('end');
                $ntext = substr($ntext, 0, $start)
                       . '%STARTSECTION{' . $s->stringify().'}%'
                       . substr($ntext, $start, $end - $start)
                       . '%ENDSECTION{' . $s->stringify().'}%'
                       . substr($ntext, $end, length($ntext));
            }
        }
        $text = $ntext;
    }

    # kill markers used to prevent variable expansion
    $text =~ s/%NOP%//g;
    $this->{user} = $safe;
    return $text;
}

=pod

---++ StaticMethod entityEncode( $text, $extras ) -> $encodedText

Escape special characters to HTML numeric entities. This is *not* a generic
encoding, it is tuned specifically for use in TWiki.

HTML4.0 spec:
"Certain characters in HTML are reserved for use as markup and must be
escaped to appear literally. The "&lt;" character may be represented with
an <em>entity</em>, <strong class=html>&amp;lt;</strong>. Similarly, "&gt;"
is escaped as <strong class=html>&amp;gt;</strong>, and "&amp;" is escaped
as <strong class=html>&amp;amp;</strong>. If an attribute value contains a
double quotation mark and is delimited by double quotation marks, then the
quote should be escaped as <strong class=html>&amp;quot;</strong>.</p>

Other entities exist for special characters that cannot easily be entered
with some keyboards..."

This method encodes HTML special and any non-printable ascii
characters (except for \n and \r) using numeric entities.

FURTHER this method also encodes characters that are special in TWiki
meta-language.

$extras is an optional param that may be used to include *additional*
characters in the set of encoded characters. It should be a string
containing the additional chars.

=cut

sub entityEncode {
    my( $text, $extra) = @_;
    $extra ||= '';

    # encode all non-printable 7-bit chars (< \x1f),
    # except \n (\xa) and \r (\xd)
    # encode HTML special characters '>', '<', '&', ''' and '"'.
    # encode TML special characters '%', '|', '[', ']', '@', '_',
    # '*', and '='
    $text =~ s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|$extra])/'&#'.ord($1).';'/ge;
    return $text;
}

=pod

---++ StaticMethod entityDecode ( $encodedText ) -> $text

Decodes all numeric entities (e.g. &amp;#123;). _Does not_ decode
named entities such as &amp;amp; (use HTML::Entities for that)

=cut

sub entityDecode {
    my $text = shift;

    $text =~ s/&#(\d+);/chr($1)/ge;
    return $text;
}

=pod

---++ StaticMethod urlEncodeAttachment ( $text )

For attachments, URL-encode specially to 'freeze' any characters >127 in the
site charset (e.g. ISO-8859-1 or KOI8-R), by doing URL encoding into native
charset ($siteCharset) - used when generating attachment URLs, to enable the
web server to serve attachments, including images, directly.  

This encoding is required to handle the cases of:

    - browsers that generate UTF-8 URLs automatically from site charset URLs - now quite common
    - web servers that directly serve attachments, using the site charset for
      filenames, and cannot convert UTF-8 URLs into site charset filenames

The aim is to prevent the browser from converting a site charset URL in the web
page to a UTF-8 URL, which is the default.  Hence we 'freeze' the URL into the
site character set through URL encoding. 

In two cases, no URL encoding is needed:  For EBCDIC mainframes, we assume that 
site charset URLs will be translated (outbound and inbound) by the web server to/from an
EBCDIC character set. For sites running in UTF-8, there's no need for TWiki to
do anything since all URLs and attachment filenames are already in UTF-8.

=cut

sub urlEncodeAttachment {
    my( $text ) = @_;

    my $usingEBCDIC = ( 'A' eq chr(193) );     # Only true on EBCDIC mainframes

    if( (defined($TWiki::cfg{Site}{CharSet}) and $TWiki::cfg{Site}{CharSet} =~ /^utf-?8$/i ) or $usingEBCDIC ) {
        # Just let browser do UTF-8 URL encoding
        return $text;
    }

    # Freeze into site charset through URL encoding
    return urlEncode( $text );
}


=pod

---++ StaticMethod urlEncode( $string ) -> encoded string

Encode by converting characters that are illegal in URLs to
their %NN equivalents. This method is used for encoding
strings that must be embedded _verbatim_ in URLs; it cannot
be applied to URLs themselves, as it escapes reserved
characters such as = and ?.

RFC 1738, Dec. '94:
    <verbatim>
    ...Only alphanumerics [0-9a-zA-Z], the special
    characters $-_.+!*'(), and reserved characters used for their
    reserved purposes may be used unencoded within a URL.
    </verbatim>

Reserved characters are $&+,/:;=?@ - these are _also_ encoded by
this method.

This URL-encoding handles all character encodings including ISO-8859-*,
KOI8-R, EUC-* and UTF-8. 

This may not handle EBCDIC properly, as it generates an EBCDIC URL-encoded
URL, but mainframe web servers seem to translate this outbound before it hits browser
- see CGI::Util::escape for another approach.

=cut

sub urlEncode {
    my $text = shift;

    $text =~ s/([^0-9a-zA-Z-_.:~!*\/])/'%'.sprintf('%02x',ord($1))/ge;

    return $text;
}

=pod

---++ StaticMethod urlDecode( $string ) -> decoded string

Reverses the encoding done in urlEncode.

=cut

sub urlDecode {
    my $text = shift;

    $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;

    return $text;
}

=pod

---++ StaticMethod isTrue( $value, $default ) -> $boolean

Returns 1 if =$value= is true, and 0 otherwise. "true" means set to
something with a Perl true value, with the special cases that "off",
"false" and "no" (case insensitive) are forced to false. Leading and
trailing spaces in =$value= are ignored.

If the value is undef, then =$default= is returned. If =$default= is
not specified it is taken as 0.

=cut

sub isTrue {
    my( $value, $default ) = @_;

    $default ||= 0;

    return $default unless defined( $value );

    $value =~ s/^\s*(.*?)\s*$/$1/gi;
    $value =~ s/off//gi;
    $value =~ s/no//gi;
    $value =~ s/false//gi;
    return ( $value ) ? 1 : 0;
}

=pod

---++ StaticMethod topLevelWeb( $web ) -> top level web of $web

If $web is a top level web, it returns $web.
If $web is a subweb, it returns the top level web of $web.

=cut

sub topLevelWeb {
    my( $web ) = @_;
    return '' if ( !defined($web) );
    $web =~ /^(\w*)/;
    return $1;
}

=pod

---++ StaticMethod spaceOutWikiWord( $word, $sep ) -> $string

Spaces out a wiki word by inserting a string between each word component.
Word component boundaries are transitions from lowercase to uppercase or numeric, 
from numeric to uppercase or lowercase, and from uppercase to numeric characters.

Parameter $sep defines the separator between the word components, the default is a space.

Example: "ABC2015ProjectCharter" results in "ABC 2015 Project Charter"

=cut

sub spaceOutWikiWord {
    my $word = shift || '';
    my $sep = shift || ' ';
    $word =~ s/([$regex{lowerAlpha}])([$regex{upperAlpha}$regex{numeric}])/$1$sep$2/go;
    $word =~ s/([$regex{numeric}])([$regex{upperAlpha}$regex{lowerAlpha}])/$1$sep$2/go;
    $word =~ s/([$regex{upperAlpha}])([$regex{numeric}])/$1$sep$2/go;
    return $word;
}

=pod

---++ ObjectMethod expandAllTags(\$text, $topic, $web, $meta)
Expands variables by replacing the variables with their
values. Some example variables: %<nop>TOPIC%, %<nop>SCRIPTURL%,
%<nop>WIKINAME%, etc.
$web and $incs are passed in for recursive include expansion. They can
safely be undef.
The rules for tag expansion are:
   1 Tags are expanded left to right, in the order they are encountered.
   1 Tags are recursively expanded as soon as they are encountered -
     the algorithm is inherently single-pass
   1 A tag is not "encountered" until the matching }% has been seen, by
     which time all tags in parameters will have been expanded
   1 Tag expansions that create new tags recursively are limited to a
     set number of hierarchical levels of expansion

=cut

sub expandAllTags {
    my $this = shift;
    my $textRef = shift; # reference
    my ( $topic, $web, $meta ) = @_;
    $web =~ s#\.#/#go;

    # push current context
    my $memTopic = $this->{SESSION_TAGS}{TOPIC};
    my $memWeb   = $this->{SESSION_TAGS}{WEB};

    $this->{SESSION_TAGS}{TOPIC}   = $topic;
    $this->{SESSION_TAGS}{WEB}     = $web;

    # Escape ' !%VARIABLE%'
    $$textRef =~ s/(?<=\s)!%($regex{tagNameRegex})/&#37;$1/g;

    # Make sure func works, for registered tag handlers
    $TWiki::Plugins::SESSION = $this;

    # NOTE TO DEBUGGERS
    # The depth parameter in the following call controls the maximum number
    # of levels of expansion. If it is set to 1 then only tags in the
    # topic will be expanded; tags that they in turn generate will be
    # left unexpanded. If it is set to 2 then the expansion will stop after
    # the first recursive inclusion, and so on. This is incredible useful
    # when debugging. The default is set to 16
    # to match the original limit on search expansion, though this of
    # course applies to _all_ tags and not just search.
    $$textRef = _processTags( $this, $$textRef, \&_expandTagOnTopicRendering,
                                  16, $topic, $web, $meta, $textRef );

    # restore previous context
    $this->{SESSION_TAGS}{TOPIC}   = $memTopic;
    $this->{SESSION_TAGS}{WEB}     = $memWeb;
}

# Process TWiki %TAGS{}% by parsing the input tokenised into
# % separated sections. The parser is a simple stack-based parse,
# sufficient to ensure nesting of tags is correct, but no more
# than that.
# $depth limits the number of recursive expansion steps that
# can be performed on expanded tags.
sub _processTags {
    my $this = shift;
    my $text = shift;
    my $tagFunction = shift;
    # my ( $topic, $web, $meta, $fullTextRef ) = @_;

    my $tell = 0;

    return '' if (
                   (!defined( $text )) || 
                   ($text eq '')
                 );

    #no tags to process
    return $text unless ($text =~ /(%)/);

    my $depth = shift;

    unless ( $depth ) {
        my $loc = '';
        if ( defined($_[0]) && defined($_[1]) ) {
            $loc = " at $_[1].$_[0]"
        }
        my $mess = "Max recursive depth reached$loc: $text";
        $this->writeWarning( $mess );
        # prevent recursive expansion that just has been detected
        # from happening in the error message
        $text =~ s/%(.*?)%/$1/go;
        return $text;
    }

    my $verbatim = {};
    $text = $this->renderer->takeOutBlocks( $text, 'verbatim', $verbatim);

    # See Item1442
    #my $percent = ($TranslationToken x 3).'%'.($TranslationToken x 3);

    my @queue = split( /(%)/, $text );
    my @stack;
    my $stackTop = ''; # the top stack entry. Done this way instead of
    # referring to the top of the stack for efficiency. This var
    # should be considered to be $stack[$#stack]

    while ( scalar( @queue )) {
        my $token = shift( @queue );
        #print STDERR ' ' x $tell,"PROCESSING $token \n";

        # each % sign either closes an existing stacked context, or
        # opens a new context.
        if ( $token eq '%' ) {
            #print STDERR ' ' x $tell,"CONSIDER $stackTop\n";
            # If this is a closing }%, try to rejoin the previous
            # tokens until we get to a valid tag construct. This is
            # a bit of a hack, but it's hard to think of a better
            # way to do this without a full parse that takes % signs
            # in tag parameters into account.
            if ( $stackTop =~ /}$/s ) {
                while ( scalar( @stack) && $stackTop !~ /^%($regex{tagNameRegex})\{.*}$/so ) {
                    my $top = $stackTop;
                    #print STDERR ' ' x $tell,"COLLAPSE $top \n";
                    $stackTop = pop( @stack ) . $top;
                }
            }
            # /s so you can have newlines in parameters
            if ( $stackTop =~ m/^%(($regex{tagNameRegex})(?:{(.*)})?)$/so ) {
                my( $expr, $tag, $args ) = ( $1, $2, $3 );
                #print STDERR ' ' x $tell,"POP $tag\n";

                # Call tag function. @_ is( $topic, $web, $meta, $fullTextRef ),
                # values may be undef. $meta and $text are passed along so that
                # they can be referenced by tag handlers. $fullTextRef is a
                # reference to the full text, it cannot be updated because text
                # is reconstructed via $stackTop.
                my $e = &$tagFunction( $this, $tag, $args, @_ );

                if ( defined( $e )) {
                    #print STDERR ' ' x $tell--,"EXPANDED $tag -> $e\n";
                    $stackTop = pop( @stack );
                    unless ($e =~ /(%)/) {
                        #SMELL: this is a profiler speedup found by Sven on the last day of 4.2.1
                        #TODO: I don't think this parser should be in this section - re-analysis desired.
                        #print STDERR "no tags to recurse\n";
                        $stackTop .= $e;
                        next;
                    }
                    # Recursively expand tags in the expansion of $tag
                    $stackTop .= _processTags($this, $e, $tagFunction, $depth-1, @_ );

                } else { # expansion failed
                    #print STDERR ' ' x $tell++,"EXPAND $tag FAILED\n";
                    # To handle %NOP
                    # correctly, we have to handle the %VAR% case differently
                    # to the %VAR{}% case when a variable expansion fails.
                    # This is so that recursively define variables e.g.
                    # %A%B%D% expand correctly, but at the same time we ensure
                    # that a mismatched }% can't accidentally close a context
                    # that was left open when a tag expansion failed.
                    # However Cairo didn't do this, so for compatibility
                    # we have to accept that %NOP can never be fixed. if it
                    # could, then we could uncomment the following:

                    #if( $stackTop =~ /}$/ ) {
                    #    # %VAR{...}% case
                    #    # We need to push the unexpanded expression back
                    #    # onto the stack, but we don't want it to match the
                    #    # tag expression again. So we protect the %'s
                    #    $stackTop = $percent.$expr.$percent;
                    #} else
                    {
                        # %VAR% case.
                        # In this case we *do* want to match the tag expression
                        # again, as an embedded %VAR% may have expanded to
                        # create a valid outer expression. This is directly
                        # at odds with the %VAR{...}% case.
                        push( @stack, $stackTop );
                        $stackTop = '%'; # open new context
                    }
                }

            } else {
                push( @stack, $stackTop );
                $stackTop = '%'; # push a new context
                #$tell++;
            }

        } else {
            $stackTop .= $token;
        }
    }

    # Run out of input. Gather up everything in the stack.
    while ( scalar( @stack )) {
        my $expr = $stackTop;
        $stackTop = pop( @stack );
        $stackTop .= $expr;
    }

    #$stackTop =~ s/$percent/%/go;

    $this->renderer->putBackBlocks( \$stackTop, $verbatim, 'verbatim' );

    #print STDERR "FINAL $stackTop\n";

    return $stackTop;
}

# Handle expansion of a tag during topic rendering
# $tag is the tag name
# $args is the bit in the {} (if there are any)
# $topic and $web should be passed for dynamic tags (not needed for
# session or constant tags
sub _expandTagOnTopicRendering {
    my $this = shift;
    my $tag = shift;
    my $args = shift;
    # my( $topic, $web, $meta ) = @_;
    require TWiki::Attrs;

    my $opv = $this->{prefs}->getPreferencesValue(
        'OVERRIDABLEPREDEFINEDVARIABLES');
    $opv = 'all' unless ( defined($opv) ); # for backward compatibility
    unless ( $opv =~ /\ball\b/i ) {
        my %p = map { $_ => 1 } split(/[,\s]+/, $opv);
        if ( !$p{$tag} && defined( $functionTags{$tag} ) ) {
            return &{$functionTags{$tag}}
                ( $this,
                  new TWiki::Attrs( $args, $contextFreeSyntax{$tag} ),
                  @_ );
        }
    }
    my $e = $this->{prefs}->getPreferencesValue( $tag );
    if( defined( $e ) ) {
        if( $args ) {
            # Codev.ParameterizedVariables feature
            my $attrs = new TWiki::Attrs( $args, $contextFreeSyntax{$tag} );
            # Not possible to define a _DEFAULT setting, so use DEFAULT:
            if( ! defined $attrs->{DEFAULT} && defined $attrs->{_DEFAULT} ) {
                $attrs->{DEFAULT} = $attrs->{_DEFAULT};
            }
            while( my ( $key, $value ) = each( %$attrs ) ) {
                $e =~ s/%${key}(\{ *default="(.*?[^\\]?)" *})?%/_unescapeQuotes( $value )/ge;
            }
        }
        # In parameterized variables, expand %ALL_UNUSED_TAGS{ default="..." }% to defaults
        # FIXME: Quick hack; do proper variable parsing
        $e =~ s/%($regex{tagNameRegex})\{ *default="(.*?[^\\]?)" *}%/_unescapeQuotes( $2 )/ge;

    } else {
        $e = $this->{SESSION_TAGS}{$tag} unless( $args );
        if( !defined( $e ) && defined( $functionTags{$tag} )) {
            $e = &{$functionTags{$tag}}
              ( $this, new TWiki::Attrs(
                  $args, $contextFreeSyntax{$tag} ), @_ );
        }
    }
    return $e;
}

sub _unescapeQuotes {
    my $text = shift;
    $text =~ s/\\(["'])/$1/g;
    return $text;
}

# Handle expansion of a tag during new topic creation. When creating a
# new topic from a template we only expand a subset of the available legal
# tags, and we expand %NOP% differently.
sub _expandTagOnTopicCreation {
    my $this = shift;
    # my( $tag, $args, $topic, $web ) = @_;

    # Required for Cairo compatibility. Ignore %NOP{...}%
    # %NOP% is *not* ignored until all variable expansion is complete,
    # otherwise them inside-out rule would remove it too early e.g.
    # %GM%NOP%TIME -> %GMTIME -> 12:00. So we ignore it here and scrape it
    # out later. We *have* to remove %NOP{...}% because it can foul up
    # brace-matching.
    return '' if $_[0] eq 'NOP' && defined $_[1];

    # You may want to expand arbitrary tags on topic creation.
    # By prepending EOTC__ (EOTC stands for Expand On Topic Creation), you
    # can achieve that.
    if ( $_[0] =~ /^EOTC__(\w+)$/ ) {
	$_[0] = $1;
	return _expandTagOnTopicRendering( $this, @_ );
    }

    # Only expand a subset of legal tags. Warning: $this->{user} may be
    # overridden during this call, when a new user topic is being created.
    # This is what we want to make sure new user templates are populated
    # correctly, but you need to think about this if you extend the set of
    # tags expanded here.
    return undef unless $_[0] =~ /^(URLPARAM|DATE|(SERVER|GM)TIME|(USER|WIKI)NAME|WIKIUSERNAME|USERINFO)$/;

    return _expandTagOnTopicRendering( $this, @_ );
}

=pod

---++ ObjectMethod enterContext( $id, $val )

Add the context id $id into the set of active contexts. The $val
can be anything you like, but should always evaluate to boolean
TRUE.

An example of the use of contexts is in the use of tag
expansion. The commonTagsHandler in plugins is called every
time tags need to be expanded, and the context of that expansion
is signalled by the expanding module using a context id. So the
forms module adds the context id "form" before invoking common
tags expansion.

Contexts are not just useful for tag expansion; they are also
relevant when rendering.

Contexts are intended for use mainly by plugins. Core modules can
use $session->inContext( $id ) to determine if a context is active.

=cut

sub enterContext {
    my( $this, $id, $val ) = @_;
    $val ||= 1;
    $this->{context}->{$id} = $val;
}

=pod

---++ ObjectMethod leaveContext( $id )

Remove the context id $id from the set of active contexts.
(see =enterContext= for more information on contexts)

=cut

sub leaveContext {
    my( $this, $id ) = @_;
    my $res = $this->{context}->{$id};
    delete $this->{context}->{$id};
    return $res;
}

=pod

---++ ObjectMethod inContext( $id )

Return the value for the given context id
(see =enterContext= for more information on contexts)

=cut

sub inContext {
    my( $this, $id ) = @_;
    return $this->{context}->{$id};
}

=pod

---++ StaticMethod registerTagHandler( $tag, $fnref )

STATIC Add a tag handler to the function tag handlers.
   * =$tag= name of the tag e.g. MYTAG
   * =$fnref= Function to execute. Will be passed ($session, \%params, $web, $topic )

=cut

sub registerTagHandler {
    my ( $tag, $fnref, $syntax ) = @_;
    $functionTags{$tag} = \&$fnref;
    if( $syntax && $syntax eq 'context-free' ) {
        $contextFreeSyntax{$tag} = 1;
    }
}

=pod=

---++ StaticMethod registerRESTHandler( $subject, $verb, \&fn )

Adds a function to the dispatch table of the REST interface 
for a given subject. See TWikiScripts#rest for more info.

   * =$subject= - The subject under which the function will be registered.
   * =$verb= - The verb under which the function will be registered.
   * =\&fn= - Reference to the function.

The handler function must be of the form:
<verbatim>
sub handler(\%session,$subject,$verb) -> $text
</verbatim>
where:
   * =\%session= - a reference to the TWiki session object (may be ignored)
   * =$subject= - The invoked subject (may be ignored)
   * =$verb= - The invoked verb (may be ignored)

*Since:* TWiki::Plugins::VERSION 1.1

=cut=

sub registerRESTHandler {
   my ( $subject, $verb, $fnref) = @_;
   $restDispatch{$subject}{$verb} = \&$fnref;
}

=pod

---++ ObjectMethod handleCommonTags( $text, $web, $topic, $meta ) -> $text

Processes %<nop>VARIABLE%, and %<nop>TOC% syntax; also includes
'commonTagsHandler' plugin hook.

Returns the text of the topic, after file inclusion, variable substitution,
table-of-contents generation, and any plugin changes from commonTagsHandler.

$meta may be undef when, for example, expanding templates, or one-off strings
at a time when meta isn't available.

=cut

sub handleCommonTags {
    my( $this, $text, $theWeb, $theTopic, $meta ) = @_;

    ASSERT($theWeb) if DEBUG;
    ASSERT($theTopic) if DEBUG;

    return $text unless $text;

    my $verbatim={};
    # Plugin Hook (for cache Plugins only)
    $this->{plugins}->dispatch( 'beforeCommonTagsHandler', $text, $theTopic, $theWeb, $meta );

    #use a "global var", so included topics can extract and putback 
    #their verbatim blocks safetly.
    $text = $this->renderer->takeOutBlocks( $text, 'verbatim', $verbatim);

    my $memW = $this->{SESSION_TAGS}{INCLUDINGWEB};
    my $memT = $this->{SESSION_TAGS}{INCLUDINGTOPIC};
    $this->{SESSION_TAGS}{INCLUDINGWEB} = $theWeb;
    $this->{SESSION_TAGS}{INCLUDINGTOPIC} = $theTopic;

    expandAllTags( $this, \$text, $theTopic, $theWeb, $meta );

    $text = $this->renderer->takeOutBlocks( $text, 'verbatim', $verbatim);

    # Plugin Hook
    $this->{plugins}->dispatch( 'commonTagsHandler', $text, $theTopic, $theWeb, 0, $meta );

    # process tags again because plugin hook may have added more in
    expandAllTags( $this, \$text, $theTopic, $theWeb, $meta );

    $this->{SESSION_TAGS}{INCLUDINGWEB} = $memW;
    $this->{SESSION_TAGS}{INCLUDINGTOPIC} = $memT;

    # 'Special plugin tag' TOC hack, must be done after all other expansions
    # are complete, and has to reprocess the entire topic.

    # We need to keep track of the 'TOC topics' here in order to ensure that each 
    # of these topics is only processed once (this is due to the fact that the
    # renaming of ambiguous anchors has to work context-less and cannot recognize
    # whether a particular heading has been converted before)--alternatively, we
    # could just clear the 'anchorname memory' and keep reprocessing topics
    # (the latter solution is slower if th same TOC is included multiple times)
    # current solution: let _TOC() clear the hash which holds the anchornames
    $text =~ s/%TOC(?:{(.*?)})?%/$this->_TOC($text, $theTopic, $theWeb, $1)/ge;

    # Codev.FormattedSearchWithConditionalOutput: remove <nop> lines,
    # possibly introduced by SEARCHes with conditional CALC. This needs
    # to be done after CALC and before table rendering in order to join
    # table rows properly
    $text =~ s/^<nop>\r?\n//gm;

    $this->renderer->putBackBlocks( \$text, $verbatim, 'verbatim' );

    # TWiki Plugin Hook (for cache Plugins only)
    $this->{plugins}->dispatch( 'afterCommonTagsHandler', $text, $theTopic, $theWeb, $meta );

    return $text;
}

=pod

---++ ObjectMethod ADDTOHEAD( $args )

Add =$html= to the HEAD tag of the page currently being generated.

Note that TWiki variables may be used in the HEAD. They will be expanded
according to normal variable expansion rules.

---+++ =%<nop>ADDTOHEAD%=
You can write =%ADDTOHEAD{...}%= in a topic or template. This variable accepts the following parameters:
   * =_DEFAULT= optional, id of the head block. Used to generate a comment in the output HTML.
   * =text= optional, text to use for the head block. Mutually exclusive with =topic=.
   * =topic= optional, full TWiki path name of a topic that contains the full text to use for the head block. Mutually exclusive with =text=. Example: =topic="%WEB%.MyTopic"=.
   * =requires= optional, comma-separated list of id's of other head blocks this one depends on.
=%<nop>ADDTOHEAD%= expands in-place to the empty string, unless there is an error in which case the variable expands to an error string.

Use =%<nop>RENDERHEAD%= to generate the sorted head tags.

=cut

sub ADDTOHEAD {
    my ($this, $args, $topic, $web) = @_;

    my $_DEFAULT = $args->{_DEFAULT};
    my $text     = $args->{text};
    $topic       = $args->{topic};
    my $section  = $args->{section}  || '';
    my $requires = $args->{requires};
    if( defined $topic ) {
        ( $web, $topic ) = $this->normalizeWebTopicName( $web, $topic );

        # generate TML only and delay expansion until this is rendered
        $text = '%INCLUDE{"' . $web . '.' . $topic . '"';
        $text .= ' section="' . $section . '"' if( $section );
        $text .= ' warn="off"}%';
    }
    $text = $_DEFAULT unless defined $text;
    $text = '' unless defined $text;

    $this->addToHEAD($_DEFAULT, $text, $requires);
    return '';
}

sub addToHEAD {
    my( $this, $tag, $header, $requires ) = @_;

    # Expand TWiki variables in the header
    $header = $this->handleCommonTags( $header, $this->{webName}, $this->{topicName} );
    
    $this->{_SORTEDHEADS} ||= {};
    $tag ||= '';

    $requires ||= '';
    my $debug = '';

    # Resolve to references to build DAG
    my @requires;
    foreach my $req (split(/,\s*/, $requires)) {
        unless ($this->{_SORTEDHEADS}->{$req}) {
            $this->{_SORTEDHEADS}->{$req} = {
                tag => $req,
                requires => [],
                header => '',
            };
        }
        push(@requires, $this->{_SORTEDHEADS}->{$req});
    }
    my $record = $this->{_SORTEDHEADS}->{$tag};
    unless ($record) {
        $record = { tag => $tag };
        $this->{_SORTEDHEADS}->{$tag} = $record;
    }
    $record->{requires} = \@requires;
    $record->{header} = $header;

    # Temporary, for compatibility until %RENDERHEAD% is embedded
    # in the skins
    $this->{_HTMLHEADERS}{GENERATED_HEADERS} = _genHeaders($this);
}

sub _visit {
    my ($v, $visited, $list) = @_;
    return if $visited->{$v};
    foreach my $r (@{$v->{requires}}) {
        _visit($r, $visited, $list);
    }
    push(@$list, $v);
    $visited->{$v} = 1;
}

sub _genHeaders {
    my ($this) = @_;
    return '' unless $this->{_SORTEDHEADS};

    # Loop through the vertices of the graph, in any order, initiating
    # a depth-first search for any vertex that has not already been
    # visited by a previous search. The desired topological sorting is
    # the reverse postorder of these searches. That is, we can construct
    # the ordering as a list of vertices, by adding each vertex to the
    # start of the list at the time when the depth-first search is
    # processing that vertex and has returned from processing all children
    # of that vertex. Since each edge and vertex is visited once, the
    # algorithm runs in linear time.
    my %visited;
    my @total;
    foreach my $v (values %{$this->{_SORTEDHEADS}}) {
        _visit($v, \%visited, \@total);
    }

    return join(
          "\n",
          map { "<!-- $_->{tag} --> $_->{header}" }
          @total
        );
}

=pod

---+++ %<nop>RENDERHEAD%
=%RENDERHEAD%= should be written where you want the sorted head tags to be generated. This will normally be in a template. The variable expands to a sorted list of the head blocks added up to the point the RENDERHEAD variable is expanded. Each expanded head block is preceded by an HTML comment that records the ID of the head block.

Head blocks are sorted to satisfy all their =requires= constraints.
The output order of blocks with no =requires= value is undefined. If cycles
exist in the dependency order, the cycles will be broken but the resulting
order of blocks in the cycle is undefined.

=cut

sub RENDERHEAD {
    my $this = shift;
    return _genHeaders($this);
}

=pod

---++ StaticMethod initialize( $pathInfo, $remoteUser, $topic, $url, $query ) -> ($topicName, $webName, $scriptUrlPath, $userName, $dataDir)

Return value: ( $topicName, $webName, $TWiki::cfg{ScriptUrlPath}, $userName, $TWiki::cfg{DataDir} )

Static method to construct a new singleton session instance.
It creates a new TWiki and sets the Plugins $SESSION variable to
point to it, so that TWiki::Func methods will work.

This method is *DEPRECATED* but is maintained for script compatibility.

Note that $theUrl, if specified, must be identical to $query->url()

=cut

sub initialize {
    my ( $pathInfo, $theRemoteUser, $topic, $theUrl, $query ) = @_;

    if( !$query ) {
        $query = new TWiki::Request( {} );
    }
    if( $query->path_info() ne $pathInfo ) {
        $query->path_info( "/$0/" . $pathInfo );
    }
    if( $topic ) {
        $query->param( -name => 'topic', -value => '' );
    }
    # can't do much if $theUrl is specified and it is inconsistent with
    # the query. We are trying to get to all parameters passed in the
    # query.
    if( $theUrl && $theUrl ne $query->url()) {
        die 'Sorry, this version of TWiki does not support the url parameter to'
          . ' TWiki::initialize being different to the url in the query';
    }
    my $twiki = new TWiki( $theRemoteUser, $query );

    # Force the new session into the plugins context.
    $TWiki::Plugins::SESSION = $twiki;

    return ( $twiki->{topicName}, $twiki->{webName}, $twiki->{scriptUrlPath},
             $twiki->{userName}, $twiki->getDatadir );
}

=pod

---++ StaticMethod readFile( $filename ) -> $text

Returns the entire contents of the given file, which can be specified in any
format acceptable to the Perl open() function. Fast, but inherently unsafe.

WARNING: Never, ever use this for accessing topics or attachments! Use the
Store API for that. This is for global control files only, and should be
used *only* if there is *absolutely no alternative*.

=cut

sub readFile {
    my $name = shift;
    open( IN_FILE, "<$name" ) || return '';
    local $/ = undef;
    my $data = <IN_FILE>;
    close( IN_FILE );
    $data = '' unless( defined( $data ));
    return $data;
}

=pod

---++ StaticMethod suffixToMimeType( $filename ) -> $mimeType

Returns the MIME type corresponding to the extension of the $filename based on
the file specified by {MimeTypesFileName}. If there is no extension or the
extension is not found in the {MimeTypesFileName} file, 'text/plain' is
returned.

=cut

sub suffixToMimeType {
    my( $theFilename ) = @_;

    my $mimeType = 'text/plain';
    if( $theFilename =~ /\.([^.]+)$/ ) {
        my $suffix = $1;
        my @types = grep{ s/^\s*([^\s]+).*?\s$suffix\s.*$/$1/i }
            map { $_.' ' }
                split( /[\n\r]/, readFile( $TWiki::cfg{MimeTypesFileName} ) );
        $mimeType = $types[0] if( @types );
    }
    return $mimeType;
}

=pod

---++ StaticMethod expandStandardEscapes($str) -> $unescapedStr

Expands standard escapes used in parameter values to block evaluation. The following escapes
are handled:

| *Escape:* | *Expands To:* |
| =$n= or =$n()= | New line. Use =$n()= if followed by alphanumeric character, e.g. write =Foo$n()Bar= instead of =Foo$nBar= |
| =$nop= or =$nop()= | Is a "no operation". |
| =$quot= | Double quote (="=) |
| =$aquot= | Apostrophe quote (='=) |
| =$percnt= | Percent sign (=%=) |
| =$dollar= | Dollar sign (=$=) |
| =$lt= | Less than sign (=<=) |
| =$gt= | Greater than sign (=>=) |

=cut

sub expandStandardEscapes {
    my $text = shift;
    $text =~ s/\$n\(\)/\n/gos;         # expand '$n()' to new line
    $text =~ s/\$n([^$regex{mixedAlpha}]|$)/\n$1/gos; # expand '$n' to new line
    $text =~ s/\$nop(\(\))?//gos;      # remove filler, useful for nested search
    $text =~ s/\$quot(\(\))?/\"/gos;   # expand double quote
    $text =~ s/\$aquot(\(\))?/\'/gos;  # expand apostrophe quote
    $text =~ s/\$percnt(\(\))?/\%/gos; # expand percent
    $text =~ s/\$dollar(\(\))?/\$/gos; # expand dollar
    $text =~ s/\$lt\b(\(\))?/\</gos;   # expand less than sign
    $text =~ s/\$gt\b(\(\))?/\>/gos;   # expand greater than sign
    return $text;
}

# generate an include warning
# SMELL: varying number of parameters idiotic to handle for customized $warn
sub _includeWarning {
    my $this = shift;
    my $warn = shift;
    my $message = shift;

    if( $warn eq 'on' ) {
        return $this->inlineAlert( 'alerts', $message, @_ );
    } elsif( isTrue( $warn )) {
        # different inlineAlerts need different argument counts
        my $argument = '';
        if ($message  eq  'topic_not_found') {
            my ($web,$topic)  =  @_;
            $argument = "$web.$topic";

        } else {
            $argument = shift;
        }
        $warn =~ s/\$topic/$argument/go if $argument;
        return $warn;
    } # else fail silently
    return '';
}

#-------------------------------------------------------------------
# Tag Handlers
#-------------------------------------------------------------------

sub BASETOPIC {
    my $this = shift;
    return $this->{SESSION_TAGS}{BASETOPIC};
}

sub BASEWEB {
    my ( $this, $params ) = @_;
    return _handleWebTag( $this->{SESSION_TAGS}{BASEWEB}, $params );
}

sub INCLUDINGTOPIC {
    my $this = shift;
    return $this->{SESSION_TAGS}{INCLUDINGTOPIC};
}

sub INCLUDINGWEB {
    my ( $this, $params ) = @_;
    return _handleWebTag( $this->{SESSION_TAGS}{INCLUDINGWEB}, $params );
}

sub TOPIC {
    my $this = shift;
    return $this->{SESSION_TAGS}{TOPIC};
}

sub WEB {
    my ( $this, $params ) = @_;
    return _handleWebTag( $this->{SESSION_TAGS}{WEB}, $params );
}

sub _handleWebTag {
    my( $theWeb, $params ) = @_;
    my $format = $params->{format} || $params->{_DEFAULT};
    if( $format ) {
        my $web = $theWeb;
        my @w = split( /[\/\.]/, $theWeb );
        my $size = scalar( @w );
        my $parents = '';
        if( $size > 1 && $web =~ /^(.*)[\/\.]/ ) {
            $parents = $1;
        }
        $theWeb = $format;
        $theWeb =~ s/\$web/$web/go;
        $theWeb =~ s/\$parents?/$parents/go;
        $theWeb =~ s/\$current/$w[-1]/go;
        $theWeb =~ s/\$(item|last)\(0\)//go;
        $theWeb =~ s/\$item\(([0-9]+)\)/$1 > $size ? '' : $w[$1-1]/geo;
        $theWeb =~ s/\$last\(([0-9]+)\)/my @t = @w; join('\/', splice( @t, ($1 > $size ? -$size : -$1), 99))/geo;
        $theWeb =~ s/\$top\(([0-9]+)\)/my @t = @w; join( '\/', splice( @t, 0, $1 ) )/geo;
        $theWeb =~ s/\$top/$w[0]/go;
        $theWeb =~ s/\$list/join( ', ', @w)/geo;
        $theWeb =~ s/\$size/$size/go;
    }
    return $theWeb;
}

sub TOPICTITLE {
    my ( $this, $params, $topic, $web ) = @_;
    # optional $params->{topic} can be "TopicName" or "Web.TopicName"
    $topic = $params->{topic} || $params->{_DEFAULT} || $topic;
    # normalize web and topic name
    ( $web, $topic ) = $this->normalizeWebTopicName( $web, $topic );
    my $text = $topic;
    if( $this->{store}->topicExists( $web, $topic )) {
        my $meta = $this->inContext( 'can_render_meta' );
        if( $meta && $web eq $this->{SESSION_TAGS}{BASEWEB} &&
                $topic eq $this->{SESSION_TAGS}{BASETOPIC} ) {
            # use meta data of base topic
            $text = $meta->topicTitle();
        } else {
            # not base topic, need to read meta data to get topic title
            try {
                my $dummyText;
                ( $meta, $dummyText ) = $this->{store}->readTopic(
                      $this->{session}->{user}, $web, $topic );
                $text = $meta->topicTitle() if( $meta );
            } catch TWiki::AccessControlException with {
                # Ignore access exceptions
            };
        }
    }
    if( $params->{encode} ) {
        $text = $this->ENCODE( { _DEFAULT => $text, type => $params->{encode} } );
    }
    return $text;
}

sub FORM {
    my ( $this, $params, $topic, $web ) = @_;
    my $cgiQuery = $this->{request};
    my $cgiRev = $cgiQuery->param('rev') if( $cgiQuery );
    $params->{rev} = $cgiRev unless( defined $params->{rev} );
    return $this->renderer->renderFORM( $params, $topic, $web );
}

sub FORMFIELD {
    my ( $this, $params, $topic, $web ) = @_;    
    my $cgiQuery = $this->{request};
    my $cgiRev = $cgiQuery->param('rev') if( $cgiQuery );
    $params->{rev} = $cgiRev unless( defined $params->{rev} );
    return $this->renderer->renderFORMFIELD( $params, $topic, $web );
}

sub EDITFORM {
    my ( $this, $params, $topic, $web ) = @_;
    return $this->renderer->renderEDITFORM( $params, $topic, $web );
}

sub EDITFORMFIELD {
    my ( $this, $params, $topic, $web ) = @_;
    return $this->renderer->renderEDITFORMFIELD( $params, $topic, $web );
}

sub TMPLP {
    my( $this, $params ) = @_;
    return $this->templates->tmplP( $params );
}

sub VAR {
    my( $this, $params, $intopic, $inweb ) = @_;
    my $key = $params->{_DEFAULT};
    my $default = $params->{default};
    $default = '' unless ( defined($default) );
    return $default unless $key;
    my $ignoreNull = TWiki::Func::isTrue($params->{ignorenull});
    my $web = $params->{web};
    my $topic = $params->{topic};
    my $val;
    # always return a value, even when the key isn't defined
    if ( $topic ) {
        ( $web, $topic ) = $this->normalizeWebTopicName( $web || $inweb,
                                                         $topic );
        $val = $this->{prefs}->getTopicPreferencesValue( $key, $web, $topic );
    }
    elsif ( $web ) {
        # handle %USERSWEB%-type cases
        ( $web, $topic ) = $this->normalizeWebTopicName( $web, $intopic );
        $val = $this->{prefs}->getWebPreferencesValue( $key, $web );
    }
    else {
	$val = $this->{prefs}->getPreferencesValue($key);
	return $val if ( defined($val) && ($val ne '' || !$ignoreNull) );
	$val = $this->{SESSION_TAGS}{$key};
    }
    return $val if ( defined($val) && ($val ne '' || !$ignoreNull) );
    return $default;
}

sub PLUGINVERSION {
    my( $this, $params ) = @_;
    $this->{plugins}->getPluginVersion( $params->{_DEFAULT} );
}

sub IF {
    my ( $this, $params, $topic, $web, $meta ) = @_;

    unless( $ifParser ) {
        require TWiki::If::Parser;
        $ifParser = new TWiki::If::Parser();
    }

    my $texpr = $params->{_DEFAULT};
    my $expr;
    my $result;

    if ( defined($texpr) && ($texpr =~ /^\s*$/ || $texpr =~ /^\s*0\s*$/) ) {
        # shortcut for a null string or 0 condition - compatibility with
        # TWiki 4.1 and consistency with a "1" condition.
        $params->{else} = '' unless defined $params->{else};
        return expandStandardEscapes( $params->{else} );
    }

    # Recursion block.
    $this->{evaluating_if} ||= {};
    # Block after 5 levels.
    if ($this->{evaluating_if}->{$texpr} &&
          $this->{evaluating_if}->{$texpr} > 5) {
        delete $this->{evaluating_if}->{$texpr};
        return '';
    }
    $this->{evaluating_if}->{$texpr}++;

    try {
        $expr = $ifParser->parse( $texpr );
        unless( $meta ) {
            require TWiki::Meta;
            $meta = new TWiki::Meta( $this, $web, $topic );
        }
        if( $expr->evaluate( tom=>$meta, data=>$meta )) {
            $params->{then} = '' unless defined $params->{then};
            $result = expandStandardEscapes( $params->{then} );
        } else {
            $params->{else} = '' unless defined $params->{else};
            $result = expandStandardEscapes( $params->{else} );
        }
    } catch TWiki::Infix::Error with {
        my $e = shift;
        $result = $this->inlineAlert(
            'alerts', 'generic', 'IF{', $params->stringify(), '}:',
            $e->{-text} );
    } finally {
        delete $this->{evaluating_if}->{$texpr};
    };
    return $result;
}

sub HIDE {
    # return empty string
    return '';
}

sub HIDEINPRINT {
    # enclose content in div to hide when printing
    my ( $this, $params ) = @_;
    return '<div class="hideInPrint"> ' . $params->{_DEFAULT} . ' </div>';
}

sub _fixHeadingOffset
{
    my ( $prefix, $level, $offset ) = @_;
    $level += $offset;
    $level = 1 if( $level < 1);
    $level = 6 if( $level > 6);
    return $prefix . '+' x $level;
}

# Processes a specific instance %<nop>INCLUDE{...}% syntax.
# Returns the text to be inserted in place of the INCLUDE command.
# $topic and $web should be for the immediate parent topic in the
# include hierarchy. Works for both URLs and absolute server paths.
sub INCLUDE {
    my ( $this, $params, $includingTopic, $includingWeb ) = @_;

    # remember args for the key before mangling the params
    my $args = $params->stringify();

    # Remove params, so they don't get expanded in the included page
    my $path = $params->remove('_DEFAULT') || '';
    my $attachment = $params->remove('attachment') || '';
    my $pattern = $params->remove('pattern');
    my $headingoffset = $params->remove('headingoffset') || '';
    my $hidetoc = isTrue( $params->remove('hidetoc') )
      || isTrue( $this->{prefs}->getPreferencesValue( 'TOC_HIDE_IF_INCLUDED' ) );
    my $rev = $params->remove('rev');
    my $section = $params->remove('section');
    my $disableFixLinks = $params->remove('disablefixlinks') || '';

    # no sense in considering an empty string as an unfindable section:
    undef $section if (defined($section) && $section eq '');

    my $raw = $params->remove('raw') || '';
    my $warn = $params->remove('warn')
      || $this->{prefs}->getPreferencesValue( 'INCLUDEWARNING' );
    my $allowAnyType = isTrue( $params->remove('allowanytype') );
    my $charSet = $params->remove('charset') || '';

    if( $path =~ /^https?\:/ ) {
        # include web page
        return _includeUrl(
            $this, $path, $pattern, $includingWeb, $includingTopic,
            $raw, $params, $warn, $allowAnyType, $charSet );
    }

    if ( $path eq '' && $attachment ne '' ) {
        $path = $includingTopic;
    }
    $path =~ s/$TWiki::cfg{NameFilter}//go;    # zap anything suspicious
    if( $TWiki::cfg{DenyDotDotInclude} ) {
        # Filter out '..' from filename, this is to
        # prevent includes of '../../file'
        $path =~ s/\.+/\./g;
    } else {
        # danger, could include .htpasswd with relative path
        $path =~ s/passwd//gi;    # filter out passwd filename
    }

    # make sure we have something to include. If we don't do this, then
    # normalizeWebTopicName will default to WebHome. Item2209.
    unless( $path ) {
        # SMELL: could do with a different message here, but don't want to
        # add one right now because translators are already working
        return _includeWarning( $this, $warn, 'topic_not_found', '""','""' );
    }

    my $text = '';
    my $meta = '';
    my $includedWeb;
    my $includedTopic = $path;
    $includedTopic =~ s/\.txt$//; # strip optional (undocumented) .txt

    ($includedWeb, $includedTopic) =
      $this->normalizeWebTopicName($includingWeb, $includedTopic);

    # See Codev.FailedIncludeWarning for the history.
    unless( $this->{store}->topicExists($includedWeb, $includedTopic)) {
        return _includeWarning( $this, $warn, 'topic_not_found',
                                       $includedWeb, $includedTopic );
    }

    # prevent recursive includes. Note that the inclusion of a topic into
    # itself is not blocked; however subsequent attempts to include the
    # topic will fail. There is a hard block of 99 on any recursive include.
    my $key = $includingWeb.'.'.$includingTopic;
    my $count = keys %{$this->{_INCLUDES}};
    $key .= $args;
    if( $this->{_INCLUDES}->{$key} || $count > 99) {
        return _includeWarning( $this, $warn, 'already_included',
                                       "$includedWeb.$includedTopic", '' );
    }

    my %saveTags = %{$this->{SESSION_TAGS}};
    my $prefsMark = $this->{prefs}->mark();

    $this->{_INCLUDES}->{$key} = 1;
    $this->{SESSION_TAGS}{INCLUDINGWEB} = $includingWeb;
    $this->{SESSION_TAGS}{INCLUDINGTOPIC} = $includingTopic;

    ( $meta, $text ) =
      $this->{store}->readTopic( undef, $includedWeb, $includedTopic, $rev );

    # Simplify leading, and remove trailing, newlines. If we don't remove
    # trailing, it becomes impossible to %INCLUDE a topic into a table.
    $text =~ s/^[\r\n]+/\n/;
    $text =~ s/[\r\n]+$//;

    unless(
        ($includingTopic eq $includedTopic && $includingWeb eq $includedWeb) ||
        # you may include itself, in which case permission check needs to be
        # omitted for efficiency
        $this->security->checkAccessPermission(
            'VIEW', $this->{user}, $text, $meta, $includedTopic, $includedWeb )
    ) {
        if( isTrue( $warn )) {
            return $this->inlineAlert( 'alerts', 'access_denied',
                                       "[[$includedWeb.$includedTopic]]" );
        } # else fail silently
        return '';
    }

    if ( $attachment ne '' ) {
        my $mimeType = suffixToMimeType($attachment);
        if( $allowAnyType || $mimeType =~ /^text\/(html|plain|css)/ ) {
            unless( $this->{store}->attachmentExists(
                $includedWeb, $includedTopic, $attachment )) {
                return _includeWarning( $this, $warn, 'bad_attachment',
                                        $attachment);
            }
            $text = $this->{store}->readAttachment(
                undef, $includedWeb, $includedTopic, $attachment, $rev );
        }
        else {
            return _includeWarning( $this, $warn, 'bad_content', $mimeType );
        }
    }
    if ( $charSet ) {
        my $siteCharset = $TWiki::cfg{Site}{CharSet} || 'iso-8859-1';
        $this->_convertCharsets($charSet, $siteCharset, \$text);
    }

    return $text if ( $raw );

    # remove everything before and after the default include block unless
    # a section is explicitly defined
    if( !$section ) {
       $text =~ s/.*?%STARTINCLUDE%//s;
       $text =~ s/%STOPINCLUDE%.*//s;
    }

    # handle sections
    my( $ntext, $sections ) = parseSections( $text );

    my $interesting = ( defined $section );
    if( $interesting || scalar( @$sections )) {
        # Rebuild the text from the interesting sections
        $text = '';
        foreach my $s ( @$sections ) {
            if( $section && $s->{type} eq 'section' && $s->{name} eq $section) {
                $text .= substr( $ntext, $s->{start}, $s->{end}-$s->{start} );
                $disableFixLinks = 1 if( $s->{disablefixlinks} );
                $interesting = 1;
                last;
            } elsif( $s->{type} eq 'include' && !$section ) {
                $text .= substr( $ntext, $s->{start}, $s->{end}-$s->{start} );
                $interesting = 1;
            }
        }
    }
    # If there were no interesting sections, restore the whole text
    $text = $ntext unless $interesting;

    $text = applyPatternToIncludedText( $text, $pattern ) if( $pattern );

    # Do not show TOC in included topic if hidetoc parameter or
    # TOC_HIDE_IF_INCLUDED preference setting has been set
    if( $hidetoc ) {
        $text =~ s/%TOC(?:{(.*?)})?%//g;
    }

    # Codev.IncludeParametersWithDefault feature:
    # Change %ALLTAGS{ default="..." }% to %ALLTAGS% and capture tags with defaults
    # FIXME: Quick hack; do proper variable parsing
    my $verbatim = {};
    $text = $this->renderer->takeOutBlocks( $text, 'verbatim', $verbatim );
    my $tagsWithDefault = undef;
    $text =~ s/(%)($regex{tagNameRegex})(\{ *default=")(.*?[^\\]?)(" *\})(%)/
               $tagsWithDefault->{$2} = _unescapeQuotes( $4 );
               "$1$2$6"/ge;
    $this->renderer->putBackBlocks( \$text, $verbatim, 'verbatim' );

    foreach my $k ( keys %$params ) {
        next if( $k eq '_RAW' );
        # copy params into session tags
        $this->{SESSION_TAGS}{$k} = $params->{$k};
        # remove captured tag with default
        delete $tagsWithDefault->{$k};
    }
    foreach my $k ( keys %$tagsWithDefault ) {
        # copy left over captured tags with default into session tags
        $this->{SESSION_TAGS}{$k} = $tagsWithDefault->{$k}; 
    }

    expandAllTags( $this, \$text, $includedTopic, $includedWeb, $meta );

    # 4th parameter tells plugin that its called for an included file
    $this->{plugins}->dispatch(
        'commonTagsHandler', $text, $includedTopic, $includedWeb, 1, $meta );

    # We have to expand tags again, because a plugin may have inserted additional
    # tags.
    expandAllTags( $this, \$text, $includedTopic, $includedWeb, $meta );

    # If needed, fix all 'TopicNames' to 'Web.TopicNames' to get the
    # right context so that links continue to work properly
    if( $includedWeb ne $includingWeb && !$disableFixLinks ) {
        my $removed = {};
        my $noautolink = isTrue( $this->{prefs}->getPreferencesValue( 'NOAUTOLINK' ) );

        $text = $this->renderer->forEachLine(
            $text, \&_fixupIncludedTopic, { web => $includedWeb,
                                            force_noautolink => $noautolink, # TWikibug:Item7188
                                            pre => 1,
                                            noautolink => 1} );
        # handle tags again because of plugin hook
        expandAllTags( $this, \$text, $includedTopic, $includedWeb, $meta );
    }

    if( $headingoffset =~ s/.*?([-+]?[0-9]).*/$1/ ) {
        $text =~ s/^(---*)(\++)/_fixHeadingOffset( $1, length( $2 ), $headingoffset )/gem;
    }

    $this->_includePostProcessing(\$text, $params);

    # restore the tags
    delete $this->{_INCLUDES}->{$key};
    %{$this->{SESSION_TAGS}} = %saveTags;

    $this->{prefs}->restore( $prefsMark );

    return $text;
}

sub _http {
    my( $this, $params, $https ) = @_;
    my $res;
    my $field = $params->{_DEFAULT};
    if ( $field ) {
        my $f = lc $field;
        $f =~ s/_/-/g;
        return '' if $httpHiddenField{$f};
        $res = $https ? $this->{request}->https( $field )
                      : $this->{request}->http( $field );
    }
    $res = '' unless defined( $res );
    return $res;
}

sub HTTP {
    return _http($_[0], $_[1], 0);
}

sub HTTPS {
    return _http($_[0], $_[1], 1);
}

#deprecated functionality, now implemented using %ENV%
#move to compatibility plugin in TWiki5
sub HTTP_HOST_deprecated {
    return $_[0]->{request}->header('Host') || '';
}

#deprecated functionality, now implemented using %ENV%
#move to compatibility plugin in TWiki5
sub REMOTE_ADDR_deprecated {
    return $_[0]->{request}->remoteAddress() || '';
}

#deprecated functionality, now implemented using %ENV%
#move to compatibility plugin in TWiki5
sub REMOTE_PORT_deprecated {
# CGI/1.1 (RFC 3875) doesn't specify REMOTE_PORT,
# but some webservers implement it. However, since
# it's not RFC compliant, TWiki should not rely on 
# it. So we get more portability. 
    return '';
}

#deprecated functionality, now implemented using %ENV%
#move to compatibility plugin in TWiki5
sub REMOTE_USER_deprecated {
    return $_[0]->{request}->remoteUser() || '';
}

# Only does simple search for topicmoved at present, can be expanded when required
# SMELL: this violates encapsulation of Store and Meta, by exporting
# the assumption that meta-data is stored embedded inside topic
# text.
sub METASEARCH {
    my( $this, $params ) = @_;

    return $this->{store}->searchMetaData( $params );
}

sub DATE {
    my $this = shift;
    return TWiki::Time::formatTime(time(), $TWiki::cfg{DefaultDateFormat}, $TWiki::cfg{DisplayTimeValues});
}

sub GMTIME {
    my( $this, $params ) = @_;
    return TWiki::Time::formatTime( time(), $params->{_DEFAULT} || '', 'gmtime' );
}

sub SERVERTIME {
    my( $this, $params ) = @_;
    return TWiki::Time::formatTime( time(), $params->{_DEFAULT} || '', 'servertime' );
}

sub DISPLAYTIME {
    my( $this, $params ) = @_;
    return TWiki::Time::formatTime( time(), $params->{_DEFAULT} || '', $TWiki::cfg{DisplayTimeValues} );
}

#| $web | web and  |
#| $topic | topic to display the name for |
#| $formatString | twiki format string (like in search) |
sub REVINFO {
    my ( $this, $params, $theTopic, $theWeb ) = @_;
    my $format = $params->{_DEFAULT} || $params->{format};
    my $web    = $params->{web} || $theWeb;
    my $topic  = $params->{topic} || $theTopic;
    my $cgiQuery = $this->{request};
    my $cgiRev = '';
    $cgiRev = $cgiQuery->param('rev') if( $cgiQuery );
    my $rev = $params->{rev} || $cgiRev || '';

    return $this->renderer->renderRevisionInfo( $web, $topic, undef,
                                                  $rev, $format );
}

sub REVTITLE {
    my ( $this, $params, $theTopic, $theWeb ) = @_;
    my $request = $this->{request};
    my $out = '';
    if( $request ) {
        my $rev = $this->{store}->cleanUpRevID( $request->param( 'rev' ) );
        $out = '(r'.$rev.')' if ($rev);
    }
    return $out;
}

sub REVARG {
    my ( $this, $params, $theTopic, $theWeb ) = @_;
    my $request = $this->{request};
    my $out = '';
    if( $request ) {
        my $rev = $this->{store}->cleanUpRevID( $request->param( 'rev' ) );
        $out = '&rev='.$rev if ($rev);
    }
    return $out;
}

sub ENCODE {
    my( $this, $params ) = @_;
    my $type  = $params->{type}  || 'url';
    my $extra = $params->{extra} || '';
    my $text  = $params->{_DEFAULT};
    $text = '' unless( defined $text && $text ne '' );
    my $newLine = $params->{newline};
    if( defined $newLine ) {
        $newLine =~ s/\$br\b/\0-br-\0/go;
        $newLine =~ s/\$n\b/\0-n-\0/go;
        $text =~ s/\r?\n/$newLine/go;
    }
    my $encoded = _encode( $type, $text, expandStandardEscapes( $extra ) );
    if( defined $newLine ) {
        $encoded =~ s/\0-br-\0/<br \/>/go;
        $encoded =~ s/\0-n-\0/\n/go;
    }
    return $encoded;
}

sub ENTITY {
    my( $this, $params ) = @_;
    my $text = $params->{_DEFAULT};
    $text = '' unless( defined $text && $text ne '' );
    return _encode( 'html', $text );
}

sub _encode {
    my( $type, $text, $extra ) = @_;

    if ( $type =~ /^entit(y|ies)$/i ) {
        # entity encode
        return entityEncode( $text, $extra );
    } elsif ( $type =~ /^html$/i ) {
        # entity encode, encode also space, newline and linefeed
        return entityEncode( $text, " \n\r" );
    } elsif ( $type =~ /^quotes?$/i ) {
        # escape quotes with backslash (Item3383)
        $text =~ s/\"/\\"/go;
        return $text;
    } elsif ( $type =~ /^search$/i ) {
        # substitue % with \x1a (Item7847), also escape quotes with backslash
        $text =~ s/\"/\\"/go;
        $text =~ s/%/$percentSubstitute/go;
        return $text;
    } elsif ($type =~ /^url$/i) {
        # legacy
        $text =~ s/\r*\n\r*/<br \/>/g;
        return urlEncode( $text );
    } elsif ( $type =~ /^(off|none)$/i ) {
        # no encoding
        return $text;
    } elsif ($type =~ /^moderate$/i) {
        # entity encode ' " < and >
        $text =~ s/([<>'"])/'&#'.ord($1).';'/ge;
        return $text;
    } elsif ($type =~ /^csv$/i) {
        # escape for CSV use: Repeat ' and "
        $text =~ s/(['"])/$1$1/g;
        return $text;
    } elsif ($type =~ /^json$/i) {
        # escape for JSON string use: Double quotes, backslashes and non-printable chars
        $text =~ s/(["\\])/\\$1/go;
        $text =~ s/[\b]/\\b/go;
        $text =~ s/\f/\\f/go;
        $text =~ s/\n/\\n/go;
        $text =~ s/\r/\\r/go;
        $text =~ s/\t/\\t/go;
        $text =~ s/([\x00-\x1F])/sprintf( '\u%04x', ord($1) )/geo;
        return $text;
    } else { # safe or default
        # entity encode ' " < > and %
        $text =~ s/([<>%'"])/'&#'.ord($1).';'/ge;
        return $text;
    }
}

sub ENV {
    my ($this, $params) = @_;
    
    my $key = $params->{_DEFAULT};
    return '' unless $key && defined $TWiki::cfg{AccessibleENV} && $key =~ /$TWiki::cfg{AccessibleENV}/o;
    my $val;
    if ( $key =~ /^HTTPS?_(.*)/ ) {
        $val = $this->{request}->header($1);
    }
    elsif ( $key eq 'REQUEST_METHOD' ) {
        $val = $this->{request}->request_method;
    }
    elsif ( $key eq 'REMOTE_USER' ) {
        $val = $this->{request}->remoteUser;
    }
    elsif ( $key eq 'REMOTE_ADDR' ) {
        $val = $this->{request}->remoteAddress;
    }
    else {
        # TSA SMELL: TWiki::Request doesn't support 
        # SERVER_\w+, REMOTE_HOST and REMOTE_IDENT.
        # Use %ENV as fallback, but for ones above
        # wil probably not behave as expected if
        # running with non-CGI engine.
        $val = $ENV{$key};
    }
    return defined $val ? $val : 'not set';
}

sub SEARCH {
    my ( $this, $params, $topic, $web ) = @_;
    # pass on all attrs, and add some more
    #$params->{_callback} = undef;
    $params->{inline} = 1;
    $params->{baseweb} = $web;
    $params->{basetopic} = $topic;
    $params->{search} = $params->{_DEFAULT} if( $params->{_DEFAULT} );
    $params->{type} = $this->{prefs}->getPreferencesValue( 'SEARCHVARDEFAULTTYPE' ) unless( $params->{type} );
    my $s;
    try {
        $s = $this->search->searchWeb( %$params );
        if( my $encode = $params->{encode} ) {
            $s = $this->ENCODE( { _DEFAULT => $s, type => $encode } );
        }
    } catch Error::Simple with {
        my $message = (DEBUG) ? shift->stringify() : shift->{-text};
        # Block recursions kicked off by the text being repeated in the
        # error message
        $message =~ s/%([A-Z]*[{%])/%<nop>$1/g;
        $s = $this->inlineAlert( 'alerts', 'bad_search', $message );
    };
    return $s;
}

sub WEBLIST {
    my( $this, $params ) = @_;
    my $format    = $params->{_DEFAULT} || $params->{'format'} || '$name';
    my $separator = expandStandardEscapes($params->{separator} || "\n");
    my $web       = $params->{web} || '';
    my $webs      = $params->{webs} || 'public';
    my $exclude   = $params->{exclude} || '';
    my $selection = $params->{selection} || '';
    $selection =~ s/\,/ /g;
    $selection = " $selection ";
    my $showWeb   = $params->{subwebs} || '';
    my $limit     = $params->{limit} || '32000';
    my $overlimit = $params->{overlimit} || '';
    my $depth     = $params->{depth};
    my $reverse   = isTrue($params->{reverse});
    if ( defined($depth) ) {
        if ( $depth =~ /^(\d+)/ ) {
            $depth = $1;
        }
        else {
            $depth = undef;
        }
    }
    my $marker = $params->{marker} || 'selected="selected"';
    $web =~ s#\.#/#go;

    my @list = ();
    my @webslist = split( /,\s*/, $webs );
    foreach my $aweb ( @webslist ) {
        if( $aweb eq 'public' ) {
            push( @list, $this->{store}->getListOfWebs( 'user,public,allowed', $showWeb, $depth ) );
        } elsif ( $aweb eq 'canmoveto' ) {
            push( @list, $this->{store}->getListOfWebs( 'user,public,allowed,canmoveto', $showWeb, $depth ) );
        } elsif ( $aweb eq 'cancopyto' ) {
            push( @list, $this->{store}->getListOfWebs( 'user,public,allowed,cancopyto', $showWeb, $depth ) );
        } elsif( $aweb eq 'webtemplate' ) {
            push( @list, $this->{store}->getListOfWebs( 'template,allowed', $showWeb, $depth ));
        } else {
            push( @list, $aweb ) if( $this->{store}->webExists( $aweb ) );
        }
    }

    if( $exclude ) {
        # turn exclude into a regex:
        $exclude =~ s/,\s*/|/g;                               # change comma list to regex "or"
        $exclude =~ s/[^$regex{mixedAlphaNum}\_\.\/\*\|]//g;  # filter out illegal chars
        $exclude =~ s/\*/.*/g;                                # change wildcard to regex
    }
    my @items;
    my $indent = CGI::span({class=>'twikiWebIndent'},'');
    my $i = 0;
    @list = reverse @list if ( $reverse );
    foreach my $item ( @list ) {
        if( $exclude && $item =~ /^($exclude)$/ ) {
            next;
        }
        if( $i++ >= $limit ) {
            push( @items, $overlimit ) if $overlimit;
            last;
        }
        my $line = $format;
        $line =~ s/\$web\b/$web/g;
        $line =~ s/\$name\b/$item/g;
        $line =~ s/\$qname/"$item"/g;
        my $indenteditem = $item;
        $indenteditem =~ s#/$##g;
        $indenteditem =~ s#\w+/#$indent#g;
        $line =~ s/\$indentedname/$indenteditem/g;
        my $listindent = '   ' x
            (($item =~ tr:/::) -
             ($showWeb eq '' ? 0 : ($showWeb =~ tr:/::) + 1));
            # $s =~ tr:/:: doesn't modify $s
        $line =~ s/\$listindent\b/$listindent/g;
        my $mark = ( $selection =~ / \Q$item\E / ) ? $marker : '';
        $line =~ s/\$marker/$mark/g;
        $line = expandStandardEscapes($line);
        push( @items, $line );
    }
    return join( $separator, @items);
}

sub TOPICLIST {
    my( $this, $params ) = @_;
    my $format = $params->{_DEFAULT} || $params->{'format'} || '$topic';
    my $separator = $params->{separator} || "\n";
    $separator =~ s/\$n/\n/;
    my $web = $params->{web} || $this->{webName};
    my $selection = $params->{selection} || '';
    $selection =~ s/\,/ /g;
    $selection = " $selection ";
    my $marker = $params->{marker} || 'selected="selected"';
    $web =~ s#\.#/#go;

    return '' if
      $web ne $this->{webName} &&
      $this->{prefs}->getWebPreferencesValue( 'NOSEARCHALL', $web );

    my @items;
    foreach my $item ( $this->{store}->getTopicNames( $web ) ) {
        my $line = $format;
        $line =~ s/\$web\b/$web/g;
        $line =~ s/\$topic\b/$item/g;
        $line =~ s/\$name\b/$item/g; # Undocumented, DO NOT REMOVE
        $line =~ s/\$qname/"$item"/g; # Undocumented, DO NOT REMOVE
        my $mark = ( $selection =~ / \Q$item\E / ) ? $marker : '';
        $line =~ s/\$marker/$mark/g;
        $line = expandStandardEscapes( $line );
        push( @items, $line );
    }
    return join( $separator, @items);
}

sub QUERYSTRING {
    my $this = shift;
    my $qs = $this->{request}->queryString();
    # Item7595: Sanitize QUERYSTRING to counter XSS exploits
    $qs =~ s/(['\/<>])/'%'.sprintf('%02x', ord($1))/ge;
    return $qs;
}

sub QUERYPARAMS {
    my ( $this, $params ) = @_;
    return '' unless $this->{request};

    my $format = defined $params->{format} ? $params->{format} : '$name=$value';
    my $separator = defined $params->{separator} ? $params->{separator} : "\n";
    # Item6621: Deprecate encoding="", add encode="". Do NOT remove encoding=""!
    my $encoding = $params->{encode} || $params->{encoding} || '';

    my @list;
    foreach my $name ( $this->{request}->param() ) {
        # clean parameter names of illegal characters
        $name =~ s/['"<>].*//;
        # Issues multi-valued parameters as separate hiddens
        if( $name ) {
            foreach my $value ( $this->{request}->param( $name ) ) {
                $value = '' unless defined $value;
                $value = _encode( $encoding, $value ) if( $encoding );
                my $entry = $format;
                $entry =~ s/\$name/$name/g;
                $entry =~ s/\$value/$value/;
                push( @list, $entry );
            }
        }
    }
    return expandStandardEscapes(join($separator, @list));
}

sub URLPARAM {
    my( $this, $params ) = @_;
    my $param     = $params->{_DEFAULT} || '';
    my $newLine   = $params->{newline};
    my $encode    = $params->{encode} || 'safe';
    my $multiple  = $params->{multiple};
    my $format    = $params->{format} || '$value';
    my $separator = $params->{separator};
    $separator="\n" unless (defined $separator);

    my $value;
    if( $this->{request} ) {
        if( TWiki::isTrue( $multiple )) {
            my @valueArray = $this->{request}->param( $param );
            if( @valueArray ) {
                # join multiple values properly
                unless( $multiple =~ m/^on$/i ) {
                    my $item = '';
                    @valueArray = map {
                        $item = $_;
                        $_ = $multiple;
                        $_ .= $item unless( s/\$item/$item/go );
                        $_
                    } @valueArray;
                }
                $value = join ( $separator, @valueArray );
            }
        } else {
            $value = $this->{request}->param( $param );
        }
    }
    if( defined $value ) {
        $format =~ s/\$value/$value/go;
        $value = $format;
        if( defined $newLine ) {
            $newLine =~ s/\$br\b/\0-br-\0/go;
            $newLine =~ s/\$n\b/\0-n-\0/go;
            $value =~ s/\r?\n/$newLine/go;
            $value = _encode( $encode, $value );
            $value =~ s/\0-br-\0/<br \/>/go;
            $value =~ s/\0-n-\0/\n/go;
        } else {
            $value = _encode( $encode, $value );
        }
    }
    unless( defined $value && $value ne '' ) {
        $value = $params->{default};
        $value = '' unless defined $value;
    }
    # Block expansion of %URLPARAM in the value to prevent recursion
    $value =~ s/%URLPARAM\{/%<nop>URLPARAM{/g;
    return $value;
}

# This routine was introduced to URL encode Mozilla UTF-8 POST URLs in the
# TWiki Feb2003 release - encoding is no longer needed since UTF-URLs are now
# directly supported, but it is provided for backward compatibility with
# skins that may still be using the deprecated %INTURLENCODE%.
sub INTURLENCODE_deprecated {
    my( $this, $params ) = @_;
    # Just strip double quotes, no URL encoding - Mozilla UTF-8 URLs
    # directly supported now
    return $params->{_DEFAULT} || '';
}

# This routine is deprecated as of DakarRelease,
# and is maintained only for backward compatibility.
# Spacing of WikiWords is now done with %SPACEOUT%
# (and the private routine _SPACEOUT).
# Move to compatibility module in TWiki5
sub SPACEDTOPIC_deprecated {
    my ( $this, $params, $theTopic ) = @_;
    my $topic = spaceOutWikiWord( $theTopic );
    $topic =~ s/ / */g;
    return urlEncode( $topic );
}

sub SPACEOUT {
    my ( $this, $params ) = @_;
    my $spaceOutTopic = $params->{_DEFAULT};
    my $sep = $params->{'separator'};
    $spaceOutTopic = spaceOutWikiWord( $spaceOutTopic, $sep );
    return $spaceOutTopic;
}

sub ICON {
    my( $this, $params ) = @_;
    my $iconName = $params->{_DEFAULT} || '';
    my $format   = $params->{format} || '$img';
    my $default  = $params->{default} || '';

    return $this->formatIcon( $iconName, $format, $default );
}

sub ICONURL {
    my( $this, $params ) = @_;
    my $iconName = ( $params->{_DEFAULT} || '' );
    my $default  = $params->{default} || '';

    return $this->formatIcon( $iconName, '$url', $default );
}

sub ICONURLPATH {
    my( $this, $params ) = @_;
    my $iconName = ( $params->{_DEFAULT} || '' );
    my $default  = $params->{default} || '';

    return $this->formatIcon( $iconName, '$urlpath', $default );
}

sub RELATIVETOPICPATH {
    my ( $this, $params, $theTopic, $web ) = @_;
    my $topic = $params->{_DEFAULT};

    return '' unless $topic;

    my $theRelativePath;
    # if there is no dot in $topic, no web has been specified
    if ( index( $topic, '.' ) == -1 ) {
        # add local web
        $theRelativePath = $web . '/' . $topic;
    } else {
        $theRelativePath = $topic; #including dot
    }
    # replace dot by slash is not necessary; TWiki.MyTopic is a valid url
    # add ../ if not already present to make a relative file reference
    if ( $theRelativePath !~ m!^../! ) {
        $theRelativePath = "../$theRelativePath";
    }
    return $theRelativePath;
}

sub ATTACHURLPATH {
    my ( $this, $params, $topic, $web ) = @_;
    return $this->getPubUrl(0, $web, $topic);
}

sub ATTACHURL {
    my ( $this, $params, $topic, $web ) = @_;
    return $this->getPubUrl(1, $web, $topic);
}

sub LANGUAGE {
    my $this = shift;
    return $this->i18n->language();
}

sub LANGUAGES {
    my ( $this , $params ) = @_;
    my $format = $params->{format} || "   * \$langname";
    my $separator = $params->{separator} || "\n";
    $separator =~ s/\\n/\n/g;
    my $selection = $params->{selection} || '';
    $selection =~ s/\,/ /g;
    $selection = " $selection ";
    my $marker = $params->{marker} || 'selected="selected"';

    # $languages is a hash reference:
    my $languages = $this->i18n->enabled_languages();

    my @tags = sort(keys(%{$languages}));

    my $result = '';
    my $i = 0; 
    foreach my $lang (@tags) {
         my $item = $format;
         my $name = ${$languages}{$lang};
         $item =~ s/\$langname/$name/g;
         $item =~ s/\$langtag/$lang/g;
         my $mark = ( $selection =~ / \Q$lang\E / ) ? $marker : '';
         $item =~ s/\$marker/$mark/g;
         $result .= $separator if $i;
         $result .= $item;
         $i++;
    }

    return $result;
}

sub MAKETEXT {
    my( $this, $params ) = @_;

    my $str = $params->{_DEFAULT} || $params->{string} || "";
    return "" unless $str;

    # escape everything:
    $str =~ s/\[/~[/g;
    $str =~ s/\]/~]/g;

    # restore already escaped stuff:
    $str =~ s/~~+\[/~[/g;
    $str =~ s/~~+\]/~]/g;

    # unescape parameters and calculate highest parameter number:
    my $max = 0;
    my $min = 1;
    $str =~ s/~\[(\_(\d+))~\]/
              $max = $2 if ($2 > $max);
              $min = $2 if ($2 < $min);
              "[$1]"/ge;
    $str =~ s/~\[(\*,\_(\d+),[^,]+(,([^,]+))?)~\]/
              $max = $2 if ($2 > $max);
              $min = $2 if ($2 < $min);
              "[$1]"/ge;

    # Item7080: Sanitize MAKETEXT variable:
    return "MAKETEXT error: No more than 32 parameters are allowed" if( $max > 32 );
    return "MAKETEXT error: Parameter 0 is not allowed" if( $min < 1 );
    if( $TWiki::cfg{UserInterfaceInternationalisation} ) {
        eval { require Locale::Maketext; };
        no warnings('numeric');
        $str =~ s#\\#\\\\#g if( $@ || !$@ && $Locale::Maketext::VERSION < 1.23 );
    }

    # get the args to be interpolated.
    my $argsStr = $params->{args} || "";

    my @args = split (/\s*,\s*/, $argsStr) ;
    # fill omitted args with zeros
    while ((scalar @args) < $max) {
        push(@args, 0);
    }

    # do the magic:
    my $result = $this->i18n->maketext($str, @args);

    # replace accesskeys:
    $result =~ s#(^|[^&])&([a-zA-Z])#$1<span class='twikiAccessKey'>$2</span>#g;

    # replace escaped amperstands:
    $result =~ s/&&/\&/g;

    return $result;
}

sub SCRIPTNAME {
    return $_[0]->{request}->action;
}

sub scriptUrlSub {
    my ( $this, $params, $absolute ) = @_;
    my $script = $params->{_DEFAULT} || '';
    my $web = $params->{web};
    my $topic = $params->{topic};
    $topic = '' if ( !defined($topic) );
    my @optParams;
    if ( isTrue($params->{master}) ) {
        push(@optParams, '$master', 1);
    }
    my $url = $this->getScriptUrl($absolute, $script, $web, $topic, @optParams);
    if ( $web && !$topic ) {
        $url = substr($url, 0, -length($cfg{HomeTopicName})-1);
    }
    return $url;
}

sub SCRIPTURL {
#    my ( $this, $params, $topic, $web ) = @_;
    return scriptUrlSub($_[0], $_[1], 1);
}

sub SCRIPTURLPATH {
#    my ( $this, $params, $topic, $web ) = @_;
    return scriptUrlSub($_[0], $_[1], 0);
}

sub PUBURL {
    my $this = shift;
    return $this->getPubUrl(1);
}

sub PUBURLPATH {
    my $this = shift;
    return $this->getPubUrl(0);
}

sub getContentMode {
    my ( $this, $web ) = @_;
    if ( !defined($web) || $web eq '' || $web eq $this->{webName} ) {
        return $this->{contentMode};
    }
    else {
        return ($this->modeAndMaster($web))[0];
    }
}

sub webWritable {
    my ( $this, $web ) = @_;
    my $mode = $this->getContentMode($web);
    return ($mode eq 'slave' || $mode eq 'read-only') ? 0 : 1;
}

sub CONTENTMODE {
    #my ( $this, $params ) = @_;
    return $_[0]->getContentMode($_[1]->{web});
}

sub ALLVARIABLES {
    return shift->{prefs}->stringify();
}

sub META {
    my ( $this, $params, $topic, $web ) = @_;


    # TWikibug:Item6438: %META uses current web.topic scope, but base topic's meta data.
    # ==> Quirky spec for compatibility with pre 5.0 releases where base topic is used
    # by default instead of current topic because meta data is pulled from base topic.
    $web   = $this->{SESSION_TAGS}{BASEWEB}   || $web;
    $topic = $this->{SESSION_TAGS}{BASETOPIC} || $topic;
    my $meta  = $this->inContext( 'can_render_meta' );

    my $paramTopic = $params->{topic}; 
    if( $paramTopic ) {
        ( $web, $topic ) = $this->normalizeWebTopicName( $web, $paramTopic );
        try {
            my $dummyText;
            ( $meta, $dummyText ) = $this->{store}->readTopic(
                  $this->{session}->{user}, $web, $topic );
        } catch TWiki::AccessControlException with {
            # Ignore access exceptions
            return '';
        };
    }
    return '' unless $meta;

    my $result = '';
    my $option = $params->{_DEFAULT} || '';
    if( $option eq 'form' ) {
        # META:FORM and META:FIELD
        $result = $meta->renderFormForDisplay( $this->templates );
    } elsif ( $option eq 'formfield' ) {
        # a formfield from within topic text
        $result = $meta->renderFormFieldForDisplay( $params->get('name'), '$value', $params );
    } elsif( $option eq 'attachments' ) {
        # renders attachment tables
        $result = $this->attach->renderMetaData( $web, $topic, $meta, $params );
    } elsif( $option eq 'moved' ) {
        $result = $this->renderer->renderMoved( $web, $topic, $meta, $params );
    } elsif( $option eq 'parent' ) {
        $result = $this->renderer->renderParent( $web, $topic, $meta, $params );
    }

    return expandStandardEscapes($result);
}

sub PARENTTOPIC {
    my ( $this, $params, $topic, $web ) = @_;
    my $metaParams = {
        _DEFAULT    => 'parent',
        format      => $params->{format} || '$topic',
        topic       => $params->{topic}  || "$web.$topic",
        dontrecurse => 'on',
      };
    return $this->META( $metaParams, $topic, $web );
}

# Remove NOP tag in template topics but show content. Used in template
# _topics_ (not templates, per se, but topics used as templates for new
# topics)
sub NOP {
    my ( $this, $params, $topic, $web ) = @_;

    return '<nop>' unless $params->{_RAW};

    return $params->{_RAW};
}

# Shortcut to %TMPL:P{"sep"}%
sub SEP {
    my $this = shift;
    return $this->templates->expandTemplate('sep');
}

#deprecated functionality, now implemented using %USERINFO%
#move to compatibility plugin in TWiki5
sub WIKINAME_deprecated {
    my ( $this, $params ) = @_;

    $params->{format} = $this->{prefs}->getPreferencesValue( 'WIKINAME' ) || '$wikiname';

    return $this->USERINFO($params);
}

#deprecated functionality, now implemented using %USERINFO%
#move to compatibility plugin in TWiki5
sub USERNAME_deprecated {
    my ( $this, $params ) = @_;

    $params->{format} = $this->{prefs}->getPreferencesValue( 'USERNAME' ) || '$username';

    return $this->USERINFO($params);
}

#deprecated functionality, now implemented using %USERINFO%
#move to compatibility plugin in TWiki5
sub WIKIUSERNAME_deprecated {
    my ( $this, $params ) = @_;

    $params->{format} =
      $this->{prefs}->getPreferencesValue( 'WIKIUSERNAME' ) || '$wikiusername';

    return $this->USERINFO($params);
}

sub USERINFO {
    my ( $this, $params ) = @_;
    my $format = $params->{format} || '$username, $wikiusername, $emails';

    my $user = $this->{user};

    if( $params->{_DEFAULT} ) {
        $user = $params->{_DEFAULT};
        return '' if !$user;
        # map wikiname to a login name
        $user = $this->{users}->getCanonicalUserID($user);
        return '' unless $user;
        return '' if( $TWiki::cfg{AntiSpam}{HideUserDetails} &&
                        !$this->{users}->isAdmin( $this->{user} ) &&
                          $user ne $this->{user} );
    }

    return '' unless $user;

    my $info = $format;

    if ($info =~ /\$username/) {
        my $username = $this->{users}->getLoginName($user);
        $username = 'unknown' unless defined $username;
        $info =~ s/\$username/$username/g;
    }
    if ($info =~ /\$wikiname/) {
        my $wikiname = $this->{users}->getWikiName( $user );
        $wikiname = 'UnknownUser' unless defined $wikiname;
        $info =~ s/\$wikiname/$wikiname/g;
    }
    if ($info =~ /\$wikiusername/) {
        my $wikiusername = $this->{users}->webDotWikiName($user);
        $wikiusername = "$TWiki::cfg{UsersWebName}.UnknownUser" unless defined $wikiusername;
        $info =~ s/\$wikiusername/$wikiusername/g;
    }
    if ($info =~ /\$emails/) {
        my $emails = join(', ', $this->{users}->getEmails($user));
        $info =~ s/\$emails/$emails/g;
    }
    if ($info =~ /\$groups/) {
        my @groupNames;
        my $it = $this->{users}->eachMembership( $user );
        while( $it->hasNext()) {
            my $group = $it->next();
            push( @groupNames, $group);
        }
        my $groups = join(', ', @groupNames);
        $info =~ s/\$groups/$groups/g;
    }
    if ($info =~ /\$cUID/) {
        my $cUID = $user;
        $info =~ s/\$cUID/$cUID/g;
    }
    if ($info =~ /\$admin/) {
        my $admin = $this->{users}->isAdmin($user) ? 'true' : 'false';
        $info =~ s/\$admin/$admin/g;
    }

    return $info;
}

sub GROUPS {
    my ( $this, $params ) = @_;

    my $format = $params->{format} || '| $grouplink | $members |';
    my $separator = expandStandardEscapes( $params->{separator} || "\n" );
    my $memberSeparator = expandStandardEscapes( $params->{memberseparator} || ", " );
    my $memberFormat = $params->{memberformat} || '[[$wikiusername][$wikiname]]';
    my $limit_output = $params->{memberlimit} || 32;
    $limit_output = 32000 if( $limit_output eq 'all' );
    my $header = $params->{header};
    $header = '| *' . $this->i18n->maketext( 'Group' )
          . '* | *' . $this->i18n->maketext( 'Members' ) . '* |' unless( defined $header );
    $header = '' if( $header eq 'none' );
    $header = expandStandardEscapes( $header );
    $header .= $separator unless( $header eq '' );
    my $groups = $this->{users}->eachGroup();
    my @table = ();
    while( $groups->hasNext() ) {
        my $group = $groups->next();
        # Nop it to prevent wikiname expansion unless the topic exists.
        my $groupLink = "<nop>$group";
        if( $this->{store}->topicExists( $TWiki::cfg{UsersWebName}, $group ) ) {
           $groupLink = '[['.$TWiki::cfg{UsersWebName}.".$group][$group]]";
        }
        my $it = $this->{users}->eachGroupMember( $group );
        my @members = ();
        my $i = 0;
        while( $it->hasNext() ) {
            $i++;
            last if( $i > $limit_output );
            push( @members, $it->next() );
        }
        @members = map {
            my $user = $_;
            $_ = $memberFormat;
            s/\$cuid/$user/go;
            s/\$wikiname/$this->{users}->getWikiName( $user )/geo;
            s/\$wikiusername/$this->{users}->webDotWikiName( $user )/geo;
            $_;
        } @members;
        @members = sort @members if ( isTrue($params->{sort}) );
        my $members = join( $memberSeparator, @members );
        $members .= $memberSeparator . '...' if( $i > $limit_output );
        my $line = $format;
        $line =~ s/\$grouplink/$groupLink/go;
        $line =~ s/\$group/$group/go;
        $line =~ s/\$members/$members/go;
        $line = expandStandardEscapes( $line );
        push( @table, $line );
    }

    # add hardcoded AllUsersGroup
    my $line = $format;
    my $group = 'AllUsersGroup';
    my $groupLink = '[['.$TWiki::cfg{UsersWebName}.".$group][$group]]";
    my $members = $this->i18n->maketext( 'All users including unauthenticated users.' );
    $line =~ s/\$grouplink/$groupLink/go;
    $line =~ s/\$group/$group/go;
    $line =~ s/\$members/$members/go;
    $line = expandStandardEscapes( $line );
    push( @table, $line );
    # add hardcoded AllAuthUsersGroup
    $line = $format;
    $group = 'AllAuthUsersGroup';
    $groupLink = '[['.$TWiki::cfg{UsersWebName}.".$group][$group]]";
    $members = $this->i18n->maketext( 'All authenticated users.' );
    $line =~ s/\$grouplink/$groupLink/go;
    $line =~ s/\$group/$group/go;
    $line =~ s/\$members/$members/go;
    $line = expandStandardEscapes( $line );
    push( @table, $line );

    return $header . join( $separator, sort @table );
}

sub CRYPTTOKEN {
    my ($this ) = @_;
    return $this->{users}->{loginManager}->createCryptToken();
}

sub _getMdrepoField {
    my ($rec, $recId, $fieldName) = @_;
    if ( $fieldName eq '' ) {
	return $recId;
    }
    elsif ( $fieldName eq '_' ) {
	return join(" ", map { "$_=$rec->{$_}" } sort keys %$rec);
    }
    return $rec->{$fieldName} || '';
}

sub _mdrepoFieldCond {
    my ($neg, $val, $ifMet) = @_;
    if ( $neg ) {
        return $val ? '' : $ifMet;
    }
    else {
        return $val ? $ifMet : '';
    }
}

sub _mdrepoExpand {
    my ($rec, $id, $fmt, $selection, $marker) = @_;
    my $m = $id eq $selection ? $marker : '';
    $fmt =~ s/\?(!?)(\w+)([!#%'\/:?@^`|~])(.*?)\3/_mdrepoFieldCond($1, $rec->{$2}, $4)/ge;
    $fmt =~ s/\$marker(\(\))?/$m/g;
    $fmt =~ s/\$_(\w*)(\(\))?/_getMdrepoField($rec, $id, $1)/ge;
    $fmt =~ s/\$question\(\)/\?/g;
    $fmt =~ s/\$question\b/\?/g;
    return expandStandardEscapes($fmt);
}

sub MDREPO {
    my ( $this, $params ) = @_;
    my $mdrepo = $this->{mdrepo};
    return '' unless ( $mdrepo );
    if ( my $web = $params->{web} ) {
        $web = topLevelWeb($web);
        my $rec = $mdrepo->getRec('webs', $web);
        unless ( $rec ) {
            return $params->{default} || '';
        }
        my $format = $params->{_DEFAULT} || '$__';
        return _mdrepoExpand($rec, $web, $format, '');
    }
    my $table = $params->{_DEFAULT} || $params->{table} || '';
    my $filter = $params->{filter} || '';
    my $format = $params->{format} || '| $_ | $__ |';
    my $separator = $params->{separator};
    if ( defined($separator) ) {
        $separator = expandStandardEscapes($separator);
    }
    else {
        $separator = "\n";
    }
    my $exclude = $params->{exclude} || '';
    my $selection = $params->{selection} || '';
    my $marker = $params->{marker} || 'selected';
    my @excludes;
    if ( $exclude ) {
        for my $i ( split(/,\s*/, $exclude) ) {
            push(@excludes, qr/^$i$/);
        }
    }
    my @recIds = $mdrepo->getList($table);
    if ( $filter ) {
        @recIds = grep { $_ =~ /$filter/i } @recIds;
    }
    my @ents;
  RECID_LOOP:
    for my $i ( sort { lc $a cmp lc $b } @recIds ) {
        for my $e ( @excludes ) {
            next RECID_LOOP if ( $i =~ $e );
        }
        my $rec = $mdrepo->getRec($table, $i);
        push(@ents, _mdrepoExpand($rec, $i, $format, $selection, $marker));
    }
    join($separator, @ents);
}

sub DISKID {
    my ( $this, $params ) = @_;
    my $web = $params->{web} || $this->{webName};
    return ($this->getStorageInfo($web))[2];
}

sub trashWebName {
    my ( $this, %param ) = @_;
    if ( !$TWiki::cfg{MultipleDisks} ) {
        return $TWiki::cfg{TrashWebName};
    }
    my $diskID;
    if ( defined($param{disk}) ) {
	$diskID = $param{disk};
    }
    else {
	$diskID = ($this->getDiskInfo($param{web}))[2];
    }
    my $name = $TWiki::cfg{TrashWebName};
    $name .= 'x' . $diskID . 'x' if ( $diskID );
    return $name;
}

sub TRASHWEB {
    my ( $this, $params, $topic, $web ) = @_;
    my $w = $params->{web} || $web;
    return $this->trashWebName(web => $w);
}

sub _wikiWebMaster {
    my ( $this, $params, $name ) = @_;
    my $web = $params->{web} || $this->{webName};
    my $topic = $params->{topic} || $this->{topicName};
    my $mapping = $this->{users}{mapping};
    my $result = '';
    if ( $mapping->can('wikiWebMaster') ) {
        $result = $mapping->wikiWebMaster($web, $topic, $name);
    }
    if ( $result ) {
        return $result;
    }
    else {
        return $name ? $TWiki::cfg{WebMasterName} : $TWiki::cfg{WebMasterEmail};
    }
}

sub WIKIWEBMASTER {
    return _wikiWebMaster(@_[0, 1], 0);
}

sub WIKIWEBMASTERNAME {
    return _wikiWebMaster(@_[0, 1], 1);
}

1;
