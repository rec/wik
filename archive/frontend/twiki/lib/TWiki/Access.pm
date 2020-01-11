# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2018 Peter Thoeny, peter[at]thoeny.org
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
# As per the GPL, removal of this notice is prohibited.

=pod

---+ Dynamic access control and permission caching

As TWiki:Codev/DynamicAccessControl suggests, various cool things can be
done if TWiki variables in access control variables such as ALLOWTOPICVIEW
and ALLOWWEBVIEW are expanded before examining whether the user is in those
values.
Now we have the feature. This chapter describes its design details.

If that's implemented naively, permission checking may take significantly
longer than before in some cases. So having efficiency in mind is crucial.

There had been room for efficiency improvement in access control.
So this is a good opportunity to improve efficiency in general of access
control.

---++ Basics of dynamic access control

If an access control variable contains % and %<nop>DYNAMIC_ACCESS_CONTROL%
is on at the web level, the access control variable is evaluated by
TWiki::handleCommonTags(). And then, permission is determined.

During variable expansion, access checking may occur. For example,
%<nop>FORMFIELD{"fieldname"}% causes access checking. To prevent infinite
recursion, a TWiki::Access class instance now has =recursion= attribute
housing recursion depth. If checkAccessPermission() ends up calling itself,
the recursive call returns true immediately.

---++ When to check the user is an admin

Most topics doesn't restrict viewing. While checking admin membership takes
some cost. Checking if the user is an admin should take place immediately
before concluding permission is denied.

$users->isAdmin($user, $topic, $web) depends on the user mapping handler.
Under !TWikiUserMapping, a user is an admin or not regardless of web or topic.
In that case, once a user is determined to be an admin, subsequent calls to
TWiki::Access:checkAccessPermission() can return true without looking into
access control variables such as DENYTOPICVIEW or ALLOWWEBVIEW.

This may not be true under other user mappings. Each web may have its own
admin.

$TWiki::cfg{Access}{AdminDomain} is to specify the span. It's either
"site" (default) or "web".

It is thinkable that admin differs from topic to topic within a web.
But that seems chaotic and until a realistic scenario of that is presented,
that is not considered.

---++ Why caching matters

In general, during a single session (the lifetime of a TWiki class instance),
TWiki::Access::checkAccessPermission() is called multiple times.
In some cases quite a fiew times - for example, %<nop>SEARCH{...}% checks
view permission for all topics it processes.
As such access permission checking should be efficient.

Most topics don't have DENYTOPIC* or ALLOWTOPIC* set.
In that case, DENYWEB* and ALLOWWEB* determins permission, which is the same
for all topics in a web.
This provide an opportunity for caching to increase efficiency.

The same topic may be INCLUDEd multiple times in a topic. In that case,
caching a topic's permission contributes to efficiency.

Admin membership is another factor. Once a user is determined to be an admin,
you can skip accecc checking and simply return true.

Determining wheter the user is a member of an access control variable
value may take time if groups are involved. So it's thinkable to cache
whether the user is in a string or not. But until a good number of cases
where membership caching is useful, it's not implemented.

---++ How permission should be cached and cached data should be used

Only view permmission and admin membership are worth caching.
There are no ways for change or rename permission to be checked more than
once in a session let alone root permission.

If the user is turned out be an admin, that fact must be recorded to save
the effort of determining permission subsequently.

In checkAccessPermission() cached permission data is used as follows:
   1, cached admin membership
   1. cached topic level access
   1. (actual topic level permission check)
   1. cached web level access
   1. (acttual web level permission check)

When examined, access to the topic needs to be cached because regardless
of access control variables, whether it's determined statically or
dynamically, access to the same topic remains the same and there are
cases where access to the same topic is examined more than once.

In addition, access at the web level can be cached in some cases.

| # | DENYTOPIC | ALLOWTOPIC | DENYWEB          | ALLOWWEB          | WEB level caching |
| 1 | empty     | *          | *                | *                 | no  |
| 2 | match     | *          | *                | *                 | no  |
| 3 | no match  | set        | *                | *                 | no  |
| 4 | not set   | not set    | static, match    | *                 | yes |
| 5 | not set   | not set    | dynamic          | *                 | no  |
| 6 | not set   | not set    | static, no match | dynamic           | no  |
| 7 | not set   | not set    | static, no match | static or not set | yes |
| 8 | not set   | not set    | not set          | dynamic           | no  |
| 9 | not set   | not set    | not set          | static or not set | yes |

---++ Data structure

A TWiki::Access class instance now has =cache= attribute for permission
caching, which has a slot for each user.

| *Data* | *Where it's housed* |
| admin membership | $access->{cache}{$user}{isadmin}{"web"} |
| view access to the web | $access->{cache}{$user}{allowview}{"web"} |
| view access to the topic | $access->{cache}{$user}{allowview}{"web.topic"} |
| failure value of the web | $access->{cache}{$user}{failure}{"web"} |
| failure value of the topic | $access->{cache}{$user}{failure}{"web.topic"} |

---++ Notes for unit test

Once checkAccessPermission() returns a value for a user-web-topic
combination, the same value is always returned for the same user-web-topic
combination during the same session.

!UnitTestContrib functions may call checkAccessPermission() repeatedly for
the same user-web-topic combination while changing other arguments.
As such, in test functions, before calling checkAccessPermission(),
the session's permission cache needs to be cleared.

=cut

=pod

---+ package TWiki::Access::Helper

A class for permission caching. Its instance is constructed at the
beginning of checkAccessPermission().

=cut

package TWiki::Access::Helper;

sub MONITOR { 0 } # don't forget to change the other MONITOR()

sub new {
    my( $class, $access, $mode, $user, $topic, $web ) = @_;
    if ( ++$access->{recursion} > 1 ) {
        --$access->{recursion};
        return undef;
    }
    $web ||= '';
    $topic ||= '';
    print STDERR __PACKAGE__ . ": $mode $user $web.$topic\n" if MONITOR;
    my $this = bless {
        access => $access,
        mode   => $mode,
        user   => $user,
        topic  => $topic,
        web    => $web,
        cache  => $access->{cache}{$user} ||= {},
    }, $class;
    return $this;
}

sub prologue {
    my $this = shift;
    my $cache = $this->{cache};
    my $access = $this->{access};
    if ( $cache->{isadmin}{$this->{web}} || $cache->{isadmin}{site} ) {
        print STDERR __PACKAGE__ . ": isAdmin() == true cached\n" if MONITOR;
        return 1;
    }
    if ( $this->{mode} eq 'VIEW' ) {
        my $webTopic = "$this->{web}.$this->{topic}";
        my $result = $cache->{allowview}{$webTopic};
        if ( defined $result ) {
            unless ( $result ) {
                $access->{failure} = $cache->{failure}{$webTopic};
            }
	    print STDERR
		__PACKAGE__ . ": topic level cache hit: $result\n"
		if MONITOR;
            return $result;
        }
    }
    return undef;
}

sub isAdmin {
    my $this = shift;
    my $cache = $this->{cache};
    my $result = $cache->{isadmin}{$this->{web}} || $cache->{isadmin}{site};
    if ( defined $result ) {
        print STDERR __PACKAGE__ . ": isAdmin() == $result cached\n" if MONITOR;
        return $result;
    }
    else {
        $result = 0;
        if ( $this->{access}{session}{users}->isAdmin(
                $this->{user}, $this->{topic}, $this->{web})
        ) {
            print STDERR __PACKAGE__ . ": isAdmin() == true\n" if MONITOR;
            $result = 1;
        }
        my $adminDomain =
            ($TWiki::cfg{Access}{AdminDomain} &&
             $TWiki::cfg{Access}{AdminDomain} eq 'web') ? $this->{web} : 'site';
        return $this->{cache}{isadmin}{$adminDomain} = $result;
    }
}

sub checkWebLevel {
    my $this = shift;
    return undef if ( $this->{mode} ne 'VIEW' );
    my $cache = $this->{cache};
    my $web = $this->{web};
    my $result = $cache->{allowview}{$web};
    if ( defined $result ) {
        unless ( $result ) {
            $this->{access}{failure} = $cache->{failure}{$web};
        }
	print STDERR __PACKAGE__ . ": web level cache hit: $result\n"
	    if MONITOR;
	return $result;
    }
    return undef;
}

sub epilogue {
    my ($this, $result, $cacheTopicLevel, $cacheWebLevel) = @_;
    my $access = $this->{access};
    if ( $this->{mode} eq 'VIEW' ) {
        my $cache = $this->{cache};
        my $cacheSlot;
        if ( $cacheTopicLevel ) {
            $cacheSlot = "$this->{web}.$this->{topic}";
            $cache->{allowview}{$cacheSlot} = $result;
            unless ( $result ) {
                $cache->{failure}{$cacheSlot} = $access->{failure};
            }
            print STDERR __PACKAGE__ .
                ": epilogue: $result is cached at $cacheSlot\n"
                if MONITOR;
        }
        if ( $cacheWebLevel ) {
            $cacheSlot = $this->{web};
            $cache->{allowview}{$cacheSlot} = $result;
            unless ( $result ) {
                $cache->{failure}{$cacheSlot} = $access->{failure};
            }
            print STDERR __PACKAGE__ .
                ": epilogue: $result is cached at $cacheSlot\n"
                if MONITOR;
        }
    }
    $access->{recursion}--;
    undef $this->{access};
    undef $this->{mode};
    undef $this->{user};
    undef $this->{topic};
    undef $this->{web};
    undef $this->{cache};
    return $result;
}

=pod

---+ package TWiki::Access

A singleton object of this class manages the access control database.

=cut

package TWiki::Access;

use strict;
use Assert;

# Enable this for debug. Done as a sub to allow perl to optimise it out.
sub MONITOR { 0 } # don't forget to change the other MONITOR()

=pod

---++ ClassMethod new($session)

Constructor.

=cut

sub new {
    my ( $class, $session ) = @_;
    my $this = bless( { session => $session,
                        cache   => {}        }, $class );

    return $this;
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
    undef $this->{failure};
    undef $this->{recursion};
    undef $this->{session};
    undef $this->{cache};
}

=pod

---++ ObjectMethod getReason() -> $string

Return a string describing the reason why the last access control failure
occurred.

=cut

sub getReason {
    my $this = shift;

    return $this->{failure};
}

sub _expandVariables {
    my ($this, $text, $web, $topic) = @_;
    my $session = $this->{session};
    my %saveTags;
    my $user = $session->{user};
    my $eUser = $session->{users}->getEffectiveUser($user);
    print STDERR "effective user = $eUser\n" if MONITOR;
    if ( $user ne $eUser ) {
        my $users = $session->{users};
        %saveTags = %{$session->{SESSION_TAGS}};
        $session->{SESSION_TAGS}{WIKINAME} = $users->getWikiName($eUser);
        $session->{SESSION_TAGS}{USERNAME} = $users->getLoginName($eUser);
        $session->{SESSION_TAGS}{WIKIUSERNAME} = $users->webDotWikiName($eUser);
    }

    my $result = $session->handleCommonTags($text, $web, $topic);

    if ( $user ne $eUser ) {
        %{$session->{SESSION_TAGS}} = %saveTags;
    }
    return $result;
}

=pod

---++ ObjectMethod checkAccessPermission( $action, $user, $text, $meta, $topic, $web ) -> $boolean

Check if user is allowed to access topic
   * =$action=  - 'VIEW', 'CHANGE', 'CREATE', etc.
   * =$user=    - User id (*not* wikiname)
   * =$text=    - If undef or '': Read '$theWebName.$theTopicName' to check permissions
   * =$meta=    - If undef, but =$text= is defined, then metadata will be parsed from =$text=. If defined, then metadata embedded in =$text= will be ignored. Always ignored if =$text= is undefined. Settings in =$meta= override * Set settings in plain text.
   * =$topic=   - Topic name to check, e.g. 'SomeTopic' *undef to check web perms only)
   * =$web=     - Web, e.g. 'Know'
If the check fails, the reason can be recoveered using getReason.

=cut

sub checkAccessPermission {
    my( $this, $mode, $user, $text, $meta, $topic, $web ) = @_;

    undef $this->{failure};

    print STDERR "Check $mode access $user to ". ($web||'undef'). '.'. ($topic||'undef')."\n" if MONITOR;

    $mode = uc( $mode );  # upper case

    my $helper = TWiki::Access::Helper->new($this, $mode, $user, $topic, $web);
    unless ( $helper ) {
        print STDERR "Recursion detected. returning true\n" if MONITOR;
        return 1;
    }
    my $result = $helper->prologue;
    if ( defined $result ) {
        return $helper->epilogue($result);
    }

    my $session = $this->{session};
    my $prefs = $session->{prefs};
    my $users = $session->{users};

    my $allowText;
    my $denyText;
    my $denyWeb = $prefs->getWebPreferencesValue( 'DENYWEB'.$mode, $web );
    my $allowWeb = $prefs->getWebPreferencesValue( 'ALLOWWEB'.$mode, $web );

    # retrieve $TWiki::cfg{Access}{Topic}{TOPIC}
    my $cfgAccessTopic;
    if ( $topic && ($cfgAccessTopic = $TWiki::cfg{Access}{Topic}{$topic}) ) {
        $denyText = $cfgAccessTopic->{'DENY'.$mode};
        $allowText = $cfgAccessTopic->{'ALLOW'.$mode};
    }
    # Check DENY
    if( defined( $denyText ) && $denyText =~ /\S/ ) {
        if( $users->isInList( $user, $denyText, $topic, $web ) ) {
            if( $helper->isAdmin ) {
                return $helper->epilogue(1);
            }
            $this->{failure} =
                $session->i18n->maketext('access denied by configuration') .
                " {Access}{Topic}{$topic}";
            print STDERR $this->{failure}." ($denyText)\n" if MONITOR;
            return $helper->epilogue(0, 1);
        }
    }
    # Check ALLOW. If this is defined the user _must_ be in it
    if( defined( $allowText ) && $allowText =~ /\S/ ) {
        if( $users->isInList( $user, $allowText, $topic, $web ) ) {
            print STDERR "in ALLOWTOPIC: $allowText\n" if MONITOR;
            return $helper->epilogue(1, 1);
        }
        if ( $helper->isAdmin ) {
            return $helper->epilogue(1);
        }
        $this->{failure} =
            $session->i18n->maketext('access not allowed by configuration') .
            " {Access}{Topic}{$topic}";
        print STDERR $this->{failure}." ($allowText)\n" if MONITOR;
        return $helper->epilogue(0, 1);
    }

    my $isDynamic = TWiki::isTrue(
        $prefs->getWebPreferencesValue( 'DYNAMIC_ACCESS_CONTROL', $web ));

    # Check DENYTOPIC, but only if {Access}{Topic}{TOPICNAME}{DENY*}
    # is not set or is null
    unless( defined( $denyText ) && $denyText =~ /\S/ ) {
        if( defined( $text ) ) {
            $denyText = $prefs->getTextPreferencesValue(
                'DENYTOPIC'.$mode, $text, $meta, $web, $topic );
        }
        elsif( $topic ) {
            $denyText = $prefs->getTopicPreferencesValue(
                'DENYTOPIC'.$mode, $web, $topic );
        }
        if( defined( $denyText ) && $denyText =~ /\S/ ) {
            $denyText =~ s/^\s*\+/$denyWeb, / if defined $denyWeb;
            my $foreignWebDenyDynamic = 0;
            if( $isDynamic && $denyText =~ /%/ ) {
                if( $session->{webName} ne $web ) {
                    $foreignWebDenyDynamic = 1;
                    $denyText .= ': dynamic in a foreign web';
                }
                else {
                    $denyText =
                        $this->_expandVariables($denyText, $web, $topic);
                }
                print STDERR "$web.$topic DENYTOPIC$mode = $denyText\n"
                    if MONITOR;
            }
            if( $foreignWebDenyDynamic ||
                $users->isInList( $user, $denyText, $topic, $web )
            ) {
                if( $helper->isAdmin ) {
                    return $helper->epilogue(1);
                }
                $this->{failure} =
                    $session->i18n->maketext('access denied on topic');
                print STDERR $this->{failure}." ($denyText)\n" if MONITOR;
                return $helper->epilogue(0, 1);
            }
        }
        # Until 5.X releases if DENYTOPIC is empty, didn't deny _anyone_
        # Item7330 has changed that behavior.
    }

    # Check ALLOWTOPIC. If this is defined the user _must_ be in it
    if( defined( $text ) ) {
        $allowText = $prefs->getTextPreferencesValue(
            'ALLOWTOPIC'.$mode, $text, $meta, $web, $topic );
    }
    elsif( $topic ) {
        $allowText = $prefs->getTopicPreferencesValue(
            'ALLOWTOPIC'.$mode, $web, $topic );
    }
    if( defined( $allowText ) && $allowText =~ /\S/ ) {
        my $foreignWebAllowDynamic = 0;
        $allowText =~ s/^\s*\+/$allowWeb, / if defined $allowWeb;
        if ( $isDynamic && $allowText =~ /%/ ) {
            if ( $session->{webName} ne $web ) {
                $foreignWebAllowDynamic = 1;
                $allowText .= ': dynamic in a foreign web';
            }
            else {
                $allowText =
                    $this->_expandVariables($allowText, $web, $topic);
            }
        }
        print STDERR "$web.$topic ALLOWTOPIC$mode = $allowText\n"
            if MONITOR;
        if( !$foreignWebAllowDynamic &&
            $users->isInList( $user, $allowText, $topic, $web )
        ) {
            print STDERR "in ALLOWTOPIC: $allowText\n" if MONITOR;
            return $helper->epilogue(1, 1);
        }
        if ( $helper->isAdmin ) {
            return $helper->epilogue(1);
        }
        $this->{failure} =
            $session->i18n->maketext('access not allowed on topic');
        print STDERR $this->{failure}." ($allowText)\n" if MONITOR;
        return $helper->epilogue(0, 1);
    }

    $result = $helper->checkWebLevel();
    if ( defined($result) ) {
	return $helper->epilogue($result);
    }

    # Check DENYWEB, but only if {Access}{Topic}{TOPICNAME}{DENY*} is not set
    # or is null, and DENYTOPIC is not set or is null
    my $cacheWebLevel = 1;
    unless( defined( $denyText ) && $denyText =~ /\S/ ) {
        $denyText = $denyWeb;
        if( defined( $denyText ) ) {
            my $foreignWebDenyDynamic = 0;
            if ( $isDynamic && $denyText =~ /%/ ) {
                if ( $session->{webName} ne $web ) {
                    $foreignWebDenyDynamic = 1;
                    $denyText .= ': dynamic in a foreign web';
                }
                else {
                    $denyText = $this->_expandVariables($denyText, $web,
                                                           $topic);
                    $cacheWebLevel = 0;
                }
                print STDERR "$web.$topic DENYTOPIC$mode = $denyText\n"
                    if MONITOR;
            }
            if ( $foreignWebDenyDynamic ||
                 $users->isInList( $user, $denyText, $topic, $web )
            ) {
                if ( $helper->isAdmin ) {
                    return $helper->epilogue(1);
                }
                $this->{failure} =
                    $session->i18n->maketext('access denied on web');
                print STDERR $this->{failure}." ($denyText)\n" if MONITOR;
                return $helper->epilogue(0, 1, $cacheWebLevel);
            }
        }
    }

    # Check ALLOWWEB. If this is defined and not overridden by
    # ALLOWTOPIC, the user _must_ be in it.
    $allowText = $allowWeb;

    if( defined( $allowText ) && $allowText =~ /\S/ ) {
        my $foreignWebAllowDynamic = 0;
        if ( $isDynamic && $allowText =~ /%/ ) {
            if ( $session->{webName} ne $web ) {
                $foreignWebAllowDynamic = 1;
                $allowText .= ': dynamic in a foreign web';
            }
            else {
                $allowText = $this->_expandVariables($allowText, $web,
                                                        $topic);
                $cacheWebLevel = 0;
            }
            print STDERR "$web.$topic ALLOWTOPIC$mode = $allowText\n"
                if MONITOR;
        }
        if( !$foreignWebAllowDynamic &&
            $users->isInList( $user, $allowText, $topic, $web )
        ) {
            print STDERR "in ALLOWWEB: $allowText\n" if MONITOR;
            return $helper->epilogue(1, 1, $cacheWebLevel);
        }
        else {
            if ( $helper->isAdmin ) {
                return $helper->epilogue(1);
            }
            $this->{failure} =
                $session->i18n->maketext('access not allowed on web');
            print STDERR $this->{failure}." ($allowText)\n" if MONITOR;
            return $helper->epilogue(0, 1, $cacheWebLevel);
        }
    }

    # Check DENYROOT and ALLOWROOT, but only if web is not defined
    unless( $web ) {
        $cacheWebLevel = 0;
        $denyText =
          $prefs->getPreferencesValue( 'DENYROOT'.$mode, $web );
        if( defined( $denyText ) &&
              $users->isInList( $user, $denyText, $topic, $web )
        ) {
            if ( $helper->isAdmin ) {
                return $helper->epilogue(1);
            }
            $this->{failure} =
                $session->i18n->maketext('access denied on root');
            print STDERR $this->{failure}." ($denyText)\n" if MONITOR;
            return $helper->epilogue(0);
        }

        $allowText = $prefs->getPreferencesValue( 'ALLOWROOT'.$mode, $web );

        if( defined( $allowText ) && $allowText =~ /\S/ ) {
            if( $users->isInList( $user, $allowText, $topic, $web )) {
                print STDERR "in ALLOWROOT: $allowText\n" if MONITOR;
                return $helper->epilogue(1);
            }
            else {
                if ( $helper->isAdmin ) {
                    return $helper->epilogue(1);
                }
                $this->{failure} =
                    $session->i18n->maketext('access not allowed on root');
                print STDERR $this->{failure}." ($allowText)\n" if MONITOR;
                return $helper->epilogue(0);
            }
        }
    }

    if( MONITOR ) {
        # if $allowText is defined, this line cannot be reached.
        print STDERR "OK, permitted\n";
        print STDERR "DENY: $denyText\n" if defined $denyText;
    }
    return $helper->epilogue(1, 1, $cacheWebLevel);
}

1;
