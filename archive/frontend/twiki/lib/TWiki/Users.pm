# Users Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
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

---+ package TWiki::Users
This package provides services for the lookup and manipulation of login and
wiki names of users, and their authentication.

It is a Facade that presents a common interface to the User Mapping
and Password modules. The rest of the core should *only* use the methods
of this package, and should *never* call the mapping or password managers
directly.

TWiki uses the concept of a _login name_ which is used to authenticate a
user. A login name maps to a _wiki name_ that is used to identify the user
for display. Each login name is unique to a single user, though several
login names may map to the same wiki name.

Using this module (and the associated plug-in user mapper) TWiki supports
the concept of _groups_. Groups are sets of login names that are treated
equally for the purposes of access control. Group names do not have to be
wiki names, though it is helpful for display if they are.

Internally in the code TWiki uses something referred to as a _canonical user
id_ or just _user id_. The user id is also used externally to uniquely identify
the user when (for example) recording topic histories. The user id is *usually*
just the login name, but it doesn't need to be. It just has to be a unique
7-bit alphanumeric and underscore string that can be mapped to/from login
and wiki names by the user mapper.

The canonical user id should *never* be seen by a user. On the other hand,
core code should never use anything *but* a canonical user id to refer
to a user.

*Terminology*
   * A *login name* is the name used to log in to TWiki. Each login name is
     assumed to be unique to a human. The Password module is responsible for
     authenticating and manipulating login names.
   * A *canonical user id* is an internal TWiki representation of a user. Each
     canonical user id maps 1:1 to a login name.
   * A *wikiname* is how a user is displayed. Many user ids may map to a
     single wikiname. The user mapping module is responsible for mapping
     the user id to a wikiname.
   * A *group id* represents a group of users and other groups.
     The user mapping module is responsible for mapping from a group id to
     a list of canonical user ids for the users in that group.
   * An *email* is an email address asscoiated with a *login name*. A single
     login name may have many emails.
	 
*NOTE:* 
   * wherever the code references $cUID, its a canonical_id
   * wherever the code references $group, its a group_name
   * $name may be a group or a cUID

=cut

package TWiki::Users;

use strict;
use Assert;

require TWiki::AggregateIterator;

BEGIN {

    # Do a dynamic 'use locale' for this module
    if ( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }

    # no point calling rand() without this
    # See Camel-3 pp 800.  "Do not call =srand()= multiple times in your
    # program ... just do it once at the top of your program or you won't
    # get random numbers out of =rand()=
    srand( time() ^ ( $$ + ( $$ << 15 ) ) );
}

=pod

---++ ClassMethod new ($session)
Construct the user management object that is the facade to the BaseUserMapping
and the user mapping chosen in the configuration.

=cut

sub new {
    my ( $class, $session ) = @_;
    my $this = bless( { session => $session }, $class );

    # register tag handler for user manager GUI
    TWiki::registerTagHandler( 'USERMANAGER', \&_USERMANAGER );

    require TWiki::LoginManager;
    $this->{loginManager} = TWiki::LoginManager::makeLoginManager( $session );

    # setup the cgi session, from a cookie or the url. this may return
    # the login, but even if it does, plugins will get the chance to
    # override (in TWiki.pm)
    $this->{remoteUser} =
      $this->{loginManager}->loadSession( $session->{remoteUser} );

    $this->{remoteUser} = $TWiki::cfg{DefaultUserLogin}
      unless ( defined( $this->{remoteUser} ) );

    # making basemapping
    my $implBaseUserMappingManager = $TWiki::cfg{BaseUserMappingManager}
      || 'TWiki::Users::BaseUserMapping';
    eval "require $implBaseUserMappingManager";
    die $@ if $@;
    $this->{basemapping} = $implBaseUserMappingManager->new( $session );

    my $implUserMappingManager = $TWiki::cfg{UserMappingManager};
    if ( $implUserMappingManager eq 'none' ) {
        $implUserMappingManager = 'TWiki::Users::TWikiUserMapping';
    }

    if ( $implUserMappingManager eq 'TWiki::Users::BaseUserMapping' ) {
        $this->{mapping} = $this->{basemapping};    #TODO: probly make undef..
    } else {
        eval "require $implUserMappingManager";
        die $@ if $@;
        $this->{mapping} = $implUserMappingManager->new( $session );
    }

    # the UI for rego supported/not is different from rego temporarily
    # turned off
    if ( $this->supportsRegistration() ) {
        $session->enterContext( 'registration_supported' );
        $session->enterContext( 'registration_enabled' )
          if $TWiki::cfg{Register}{EnableNewUserRegistration};
    }

    # caches - not only used for speedup, but also for authenticated but
    # unregistered users
    # SMELL: this is basically a user object, something we had previously
    # but dropped for efficiency reasons
    $this->{cUID2WikiName} = {};
    $this->{cUID2Login}    = {};
    $this->{isAdmin}       = {};

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

    $this->{loginManager}->finish() if $this->{loginManager};
    $this->{basemapping}->finish()  if $this->{basemapping};

    if( $this->{mapping} && $this->{mapping} ne $this->{basemapping} ) {
        $this->{mapping}->finish();
    }

    undef $this->{loginManager};
    undef $this->{basemapping};
    undef $this->{mapping};
    undef $this->{session};
    undef $this->{cUID2WikiName};
    undef $this->{cUID2Login};
    undef $this->{isAdmin};

}

=pod

---++ ObjectMethod loginTemplateName () -> templateFile

allows UserMappings to come with customised login screens - that should preffereably only over-ride the UI function

=cut

sub loginTemplateName {
    my $this = shift;

    #use login.sudo.tmpl for admin logins
    return $this->{basemapping}->loginTemplateName()
      if ( $this->{session}->inContext( 'sudo_login' ) );
    return $this->{mapping}->loginTemplateName() || 'login';
}

# ($cUID, $login, $wikiname, $noFallBack) -> usermapping object
sub _getMapping {
    my ( $this, $cUID, $login, $wikiname, $noFallBack ) = @_;

    $login    = '' unless defined $login;
    $wikiname = '' unless defined $wikiname;

    $wikiname =~ s/^($TWiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;

    # The base user mapper users must always override those defined in
    # custom mappings, even though that makes it impossible to maintain 100%
    # compatibility with earlier releases (guest user edits will get saved as
    # edits by BaseMapping_666).
    return $this->{basemapping}
      if ( $this->{basemapping}->handlesUser( $cUID, $login, $wikiname ) );

    return $this->{mapping}
      if ( $this->{mapping}->handlesUser( $cUID, $login, $wikiname ) );

    # The base mapping and the selected mapping claim not to know about
    # this user. Use the base mapping unless the caller has explicitly
    # requested otherwise.
    return $this->{basemapping} unless ( $noFallBack );

    return undef;
}

=pod

---++ ObjectMethod supportsRegistration () -> boolean

#return 1 if the  main UserMapper supports registration (ie can create new users)

=cut

sub supportsRegistration {
    my ( $this ) = @_;
    return $this->{mapping}->supportsRegistration();
}

=pod

---++ ObjectMethod initialiseUser ($login) -> $cUID

Given a login (which must have been authenticated) determine the cUID that
corresponds to that user. This method is used from TWiki.pm to map the
$REMOTE_USER to a cUID.

=cut

sub initialiseUser {
    my ( $this, $login ) = @_;

    # For compatibility with older ways of building login managers,
    # plugins can provide an alternate login name.
    my $plogin =
      $this->{session}->{plugins}->load( $TWiki::cfg{DisableAllPlugins} );
    $login = $plogin if( $plogin );

    my $cUID;
    if ( defined( $login ) && $login ne '' ) {

        # In the case of a user mapper that accepts any identifier as
        # a cUID,
        $cUID = $this->getCanonicalUserID( $login );

        # see BugsItem4771 - it seems that authenticated, but unmapped
        # users have rights too
        if ( !defined( $cUID ) ) {

            # There is no known canonical user ID for this login name.
            # Generate a cUID for the login, and add it anyway. There is
            # a risk that the generated cUID will overlap a cUID generated
            # by a custom mapper, but since (1) the user has to be
            # authenticated to get here and (2) the custom user mapper
            # is specific to the login process used, that risk should be
            # small (unless the author of the custom mapper screws up)
            $cUID = mapLogin2cUID($login);

            $this->{cUID2Login}->{$cUID}    = $login;
            $this->{cUID2WikiName}->{$cUID} = $login;

            # needs to be WikiName safe
            $this->{cUID2WikiName}->{$cUID} =~ s/$TWiki::cfg{NameFilter}//go;
            $this->{cUID2WikiName}->{$cUID} =~ s/\.//go;

            $this->{login2cUID}->{$login} = $cUID;
            $this->{wikiName2cUID}->{ $this->{cUID2WikiName}->{$cUID} } = $cUID;
        }
    }

    # if we get here without a login id, we are a guest. Get the guest
    # cUID.
    $cUID ||= $this->getCanonicalUserID( $TWiki::cfg{DefaultUserLogin} );

    return $cUID;
}

# global used by test harness to give predictable results
use vars qw( $password );

=pod

---++ randomPassword()
Static function that returns a random password. This function is not used
in this module; it is provided as a service for other modules, such as
custom mappers and registration modules.

=cut

sub randomPassword {
    return $password
      || join(
        "",
        ( "_", "/", 0 .. 9, "A" .. "Z", "a" .. "z" )[
          rand(64), rand(64), rand(64), rand(64),
        rand(64),   rand(64), rand(64), rand(64)
        ]
      );
}

=pod

---++ ObjectMethod addUser($login, $wikiname, $password, $emails, $mcp) -> $cUID

   * =$login= - user login name. If =undef=, =$wikiname= will be used as
     the login name.
   * =$wikiname= - user wikiname. If =undef=, the user mapper will be asked
     to provide it.
   * =$password= - password. If undef, a password will be generated.
   * =$mcp= - must change password flag. 

Add a new TWiki user identity, returning the canonical user id for the new
user. Used ONLY for user registration.

The user is added to the password system (if there is one, and if it accepts
changes). If the user already exists in the password system, then the password
is checked and an exception thrown if it doesn't match. If there is no
existing user, and no password is given, a random password is generated.

$login can be undef; $wikiname must always have a value.

The return value is the canonical user id that is used
by TWiki to identify the user.

=cut

sub addUser {
    my ( $this, $login, $wikiname, $password, $emails, $mcp ) = @_;
    my $removeOnFail = 0;

    ASSERT( $login || $wikiname ) if DEBUG;    # must have at least one

    # create a new user and get the canonical user ID from the user mapping
    # manager.
    my $cUID =
      $this->{mapping}->addUser( $login, $wikiname, $password, $emails, $mcp );

    # update the cached values
    $this->{cUID2Login}->{$cUID}    = $login;
    $this->{cUID2WikiName}->{$cUID} = $wikiname;

    $this->{login2cUID}->{$login}       = $cUID;
    $this->{wikiName2cUID}->{$wikiname} = $cUID;

    return $cUID;
}

=pod

---++ StaticMethod mapLogin2cUID( $login ) -> $cUID

This function maps an arbitrary string into a valid cUID. The transformation
is reversible, but the function is not idempotent (a cUID passed to this
function will NOT be returned unchanged). The generated cUID will be unique
for the given login name.

This static function is designed to be called from custom user mappers that
support 1:1 login-to-cUID mappings.

=cut

sub mapLogin2cUID {
    my $cUID = shift;

    ASSERT( defined( $cUID ) ) if DEBUG;

    # use bytes to ignore character encoding
    use bytes;
    $cUID =~ s/([^a-zA-Z0-9])/'_'.sprintf('%02x', ord($1))/ge;
    no bytes;
    return $cUID;
}

=pod

---++ ObjectMethod getCanonicalUserID( $identifier ) -> $cUID

Works out the TWiki canonical user identifier for the user who either
(1) logs in with the login name $identifier or (2) has the wikiname
$identifier.

The canonical user ID is an alphanumeric string that is unique
to the login name, and can be mapped back to a login name and the
corresponding wiki name using the methods of this class.

Note that if the login name to wiki name mapping is not 1:1, this
method will map a wikiname to one of the login names that corresponds
to the wiki name, but there is no guarantee which one.

Returns undef if the user does not exist.

=cut

# This function was previously known as forceCUID. It differs from that
# implementation in that it does *not* accept a CUID as parameter, which
# if why it has been renamed.
sub getCanonicalUserID {
    my ( $this, $identifier ) = @_;
    my $cUID;

    # Someone we already know?
    if ( defined( $this->{login2cUID}->{$identifier} ) ) {
        $cUID = $this->{login2cUID}->{$identifier};
    } elsif ( defined( $this->{wikiName2cUID}->{$identifier} ) ) {
        $cUID = $this->{wikiName2cUID}->{$identifier};
    } else {

        # See if a mapping recognises the identifier as a login name
        my $mapping = $this->_getMapping( undef, $identifier, undef, 1 );
        if ( $mapping ) {
            if ( $mapping->can( 'login2cUID' ) ) {
                $cUID = $mapping->login2cUID( $identifier );

            } elsif ( $mapping->can( 'getCanonicalUserID' ) ) {

                # Old name of login2cUID. Name changed to avoid confusion
                # with TWiki::Users::getCanonicalUserID. See
                # Codev.UserMapperChangesBetween420And421 for more.
                $cUID = $mapping->getCanonicalUserID( $identifier );

            } else {
                die( "Broken user mapping $mapping; does not implement login2cUID" );
            }
        }
        unless ( $cUID ) {

            # Finally see if it's a valid user wikiname

            # Strip users web id (legacy, probably specific to
            # TWikiUserMappingContrib but may be used by other mappers
            # that support user topics)
            my ( $dummy, $nid ) =
              $this->{session}->normalizeWebTopicName( '', $identifier );
            $identifier = $nid if ( $dummy eq $TWiki::cfg{UsersWebName} );

            my $found = $this->findUserByWikiName( $identifier );
            $cUID = $found->[0] if ( $found && scalar( @$found ) );
        }
    }
    return $cUID;
}

=pod

---++ ObjectMethod findUserByWikiName( $wn ) -> \@users
   * =$wn= - wikiname to look up
Return a list of canonical user names for the users that have this wikiname.
Since a single wikiname might be used by multiple login ids, we need a list.

If $wn is the name of a group, the group will *not* be expanded.

=cut

sub findUserByWikiName {
    my ( $this, $wn ) = @_;
    ASSERT( $wn ) if DEBUG;

    # Trim the (pointless) userweb, if present
    $wn =~ s/^($TWiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
    my $mapping = $this->_getMapping( undef, undef, $wn );
    return $mapping->findUserByWikiName( $wn );
}

=pod

---++ ObjectMethod findUserByEmail( $email ) -> \@users
   * =$email= - email address to look up
Return a list of canonical user names for the users that have this email
registered with the user mapping managers.

=cut

sub findUserByEmail {
    my ( $this, $email ) = @_;
    ASSERT( $email ) if DEBUG;

    my $users = $this->{mapping}->findUserByEmail( $email );
    push @{$users}, @{ $this->{basemapping}->findUserByEmail( $email ) };

    return $users;
}

=pod

---++ ObjectMethod getEmails($name) -> @emailAddress

If $name is a cUID, return their email addresses. If it is a group,
return the addresses of everyone in the group.

The password manager and user mapping manager are both consulted for emails
for each user (where they are actually found is implementation defined).

Duplicates are removed from the list.

=cut

sub getEmails {
    my ( $this, $name ) = @_;

    return () unless ( $name );
    if ( $this->{mapping}->isGroup( $name ) ) {
        return $this->{mapping}->getEmails( $name );
    }

    return $this->_getMapping( $name )->getEmails( $name );
}

=pod

---++ ObjectMethod setEmails($cUID, @emails)

Set the email address(es) for the given user.
The password manager is tried first, and if it doesn't want to know the
user mapping manager is tried.

=cut

sub setEmails {
    my $this   = shift;
    my $cUID   = shift;
    my @emails = @_;
    return $this->_getMapping( $cUID )->setEmails( $cUID, @emails );
}

=pod

---++ ObjectMethod getMustChangePassword( $cUID ) -> $flag

Returns 1 if the $cUID must change the password, else 0. Returns undef if $cUID not found.

=cut

sub getMustChangePassword {
    my( $this, $cUID ) = @_;
    return $this->_getMapping( $cUID )->getMustChangePassword( $cUID );
}

=pod

---++ ObjectMethod getUserData( $cUID ) -> $dataRef

Return a reference to an array of hashes with user data, used to manage 
users. Each item is a hash with:

   * ={name}= - name of field, such as "email"
   * ={title}= - title of field, such as "E-mail"
   * ={value}= - value of field, such as "jimmy@example.com"
   * ={type}= - type of field: =text=, =password=, =checkbox=, =label=
   * ={size}= - size of field, such as =40=
   * ={note}= - comment note, if any

User management forms can be build dynamically from this data structure.
Each password manager may return a different set of fields.

=cut

sub getUserData {
    my ( $this, $cUID ) = @_;
    return $this->_getMapping( $cUID )->getUserData( $cUID );
}

=pod

---++ ObjectMethod setUserData( $cUID, $dataRef )

Set the user data of a user. Same array of hashes as getUserData is 
assumed, although only ={name}= and ={value}= are used.

=cut

sub setUserData {
    my ( $this, $cUID, $dataRef ) = @_;
    return $this->_getMapping( $cUID )->setUserData( $cUID, $dataRef );
}

=pod

---++ ObjectMethod isAdmin( $cUID, $topic, $web ) -> $boolean

True if the user is an admin
   * is $TWiki::cfg{SuperAdminGroup}
   * is a member of the $TWiki::cfg{SuperAdminGroup}

=cut

sub isAdmin {
    my ( $this, $cUID, $topic, $web ) = @_;

    return 0 unless defined $cUID;

    my $webTopic = defined($web) && defined($topic) ? "$web.$topic" : '';
    my $cached = $this->{isAdmin}->{$cUID}{$webTopic};
    return $cached if ( defined( $cached ) );

    my $mapping = $this->_getMapping( $cUID );
    my $otherMapping =
      ( $mapping eq $this->{basemapping} )
      ? $this->{mapping}
      : $this->{basemapping};

    if ( $mapping eq $otherMapping ) {
        return $this->{isAdmin}->{$cUID}{$webTopic} =
            $mapping->isAdmin( $cUID, $topic, $web );
    }
    return $this->{isAdmin}->{$cUID}{$webTopic} =
      ( $mapping->isAdmin( $cUID, $topic, $web ) ||
        $otherMapping->isAdmin( $cUID, $topic, $web ) );
}

=pod

---++ ObjectMethod isInList( $cUID, $list ) -> $boolean

Return true if $cUID is in a list of user *wikinames*, *logins* and group ids.

The list may contain the conventional web specifiers (which are ignored).

=cut

sub isInList {
    my ( $this, $cUID, $userlist, $topic, $web ) = @_;

    return 0 unless $userlist;

    # comma delimited list of users or groups
    # i.e.: "%USERSWEB%.UserA, UserB, Main.UserC  # something else"
    $userlist =~ s/(<[^>]*>)//go;    # Remove HTML tags

    return 0 unless defined $cUID;

    foreach my $ident ( split( /[\,\s]+/, $userlist ) ) {

        # Dump the users web specifier if userweb
        $ident =~ s/^($TWiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
        next unless $ident;
        my $identCUID = $this->getCanonicalUserID( $ident );
        if ( defined $identCUID ) {
            return 1 if ( $this->isEquivalentCUIDs($cUID, $identCUID,
                                                   $topic, $web ) );
        }
        if ( $this->isGroup( $ident ) ) {
            return 1 if ( $this->isInGroup( $cUID, $ident, $topic, $web ) );
        }
    }
    return 0;
}

sub isEquivalentCUIDs {
    my ( $this, $cUID, $identCUID, $topic, $web ) = @_;
    my $mapping = $this->_getMapping($cUID);
    if ( $mapping && $mapping->can( 'isEquivalentCUIDs' ) ) {
        return $mapping->isEquivalentCUIDs($cUID, $identCUID, $topic, $web);
    }
    else {
        return $cUID eq $identCUID;
    }
}

=pod

---++ ObjectMethod getEffectiveUser($cUID) -> $cUID

Returns the effective user when UserMasquerading is in action.
Returns the argument as it is otherwise.

=cut

sub getEffectiveUser {
    my ( $this, $cUID, $topic, $web ) = @_;
    my $mapping = $this->_getMapping($cUID);
    if ( $mapping && $mapping->can( 'getEffectiveUser' ) ) {
        return $mapping->getEffectiveUser($cUID, $topic, $web);
    }
    else {
        return $cUID;
    }
}

=pod

---++ ObjectMethod getRealUser($cUID) -> $cUID

Returns the real user when UserMasquerading is in action.
Returns the argument as it is otherwise.

=cut

sub getRealUser {
    my ( $this, $cUID, $topic, $web ) = @_;
    my $mapping = $this->_getMapping($cUID);
    if ( $mapping && $mapping->can( 'getRealUser' ) ) {
        return $mapping->getRealUser($cUID, $topic, $web);
    }
    else {
        return $cUID;
    }
}

=pod

---++ ObjectMethod getLoginName($cUID) -> $login

Get the login name of a user. Returns undef if the user is not known.

=cut

sub getLoginName {
    my ( $this, $cUID ) = @_;

    return undef unless defined( $cUID );

    return $this->{cUID2Login}->{$cUID}
      if ( defined( $this->{cUID2Login}->{$cUID} ) );

    my $mapping = $this->_getMapping( $cUID );
    my $login;
    if ( $cUID && $mapping ) {
        $login = $mapping->getLoginName( $cUID );
    }

    if ( defined $login ) {
        $this->{cUID2Login}->{$cUID}  = $login;
        $this->{login2cUID}->{$login} = $cUID;
    }

    return $login;
}

=pod

---++ ObjectMethod getWikiName($cUID) -> $wikiName

Get the wikiname to display for a canonical user identifier.

Can return undef if the user is not in the mapping system
(or the special case from initialiseUser)

=cut

sub getWikiName {
    my ( $this, $cUID ) = @_;
    return 'UnknownUser' unless defined( $cUID );
    return $this->{cUID2WikiName}->{$cUID}
      if ( defined( $this->{cUID2WikiName}->{$cUID} ) );

    my $wikiname;
    my $mapping = $this->_getMapping( $cUID );
    $wikiname = $mapping->getWikiName( $cUID ) if( $mapping );

    if ( !defined( $wikiname ) ) {
        if ( $TWiki::cfg{RenderLoggedInButUnknownUsers} ) {
            $wikiname = "UnknownUser (<nop>$cUID)";
        } else {
            $wikiname = $cUID;
        }
    }

    # remove the web part
    # SMELL: is this really needed?
    $wikiname =~ s/^($TWiki::cfg{UsersWebName}|%MAINWEB%|%USERSWEB%)\.//;

    $this->{cUID2WikiName}->{$cUID}     = $wikiname;
    $this->{wikiName2cUID}->{$wikiname} = $cUID;

    return $this->{cUID2WikiName}->{$cUID};
}

=pod

---++ ObjectMethod webDotWikiName($cUID) -> $webDotWiki

Return the fully qualified wikiname of the user

=cut

sub webDotWikiName {
    my ( $this, $cUID ) = @_;

    return $TWiki::cfg{UsersWebName} . '.' . $this->getWikiName( $cUID );
}

=pod

---++ ObjectMethod userExists($cUID) -> $boolean

Determine if the user already exists or not. A user exists if they are
known to to the user mapper.

=cut

sub userExists {
    my ( $this, $cUID ) = @_;
    return $this->_getMapping( $cUID )->userExists( $cUID );
}

=pod

---++ ObjectMethod eachUser() -> TWiki::Iterator of cUIDs

Get an iterator over the list of all the registered users *not* including
groups.

list of canonical_ids ???

Use it as follows:
<verbatim>
    my $iterator = $umm->eachUser();
    while ($iterator->hasNext()) {
        my $user = $iterator->next();
        ...
    }
</verbatim>

=cut

sub eachUser {
    my $this = shift;
    my @list =
      ( $this->{basemapping}->eachUser(@_), $this->{mapping}->eachUser(@_) );
    return new TWiki::AggregateIterator( \@list, 1 );
}

=pod

---++ ObjectMethod eachGroup() ->  TWiki::ListIterator of groupnames

Get an iterator over the list of all the groups.

=cut

sub eachGroup {
    my $this = shift;
    my @list =
      ( $this->{basemapping}->eachGroup(@_), $this->{mapping}->eachGroup(@_) );
    return new TWiki::AggregateIterator( \@list, 1 );
}

=pod

---++ ObjectMethod eachGroupMember($group) -> $iterator

Return a iterator of user ids that are members of this group.
Should only be called on groups.

Note that groups may be defined recursively, so a group may contain other
groups. This method should *only* return users i.e. all contained groups
should be fully expanded.

=cut

sub eachGroupMember {
    my $this = shift;
    my @list = (
        $this->{basemapping}->eachGroupMember(@_),
        $this->{mapping}->eachGroupMember(@_)
    );
    return new TWiki::AggregateIterator( \@list, 1 );
}

=pod

---++ ObjectMethod isGroup($name) -> boolean

Establish if a $name refers to a group or not. If $name is not
a group name it will probably be a canonical user id, though that
should not be assumed.

=cut

sub isGroup {
    my $this = shift;
    return ( $this->{basemapping}->isGroup(@_) )
        || ( $this->{mapping}->isGroup(@_) );
}

=pod

---++ ObjectMethod isInGroup( $cUID, $group, $topic, $web ) -> $boolean

Test if the user identified by $cUID is in the given group.
That is determined in the context of $topic and $web,
which matters in context dependent user masquerading a user mapping
handler may do.

=cut

sub isInGroup {
    my ( $this, $cUID, $group, $topic, $web ) = @_;
    return unless ( defined( $cUID ) );

    # SMELL: group names and "unknown" cUID are hard-coded
    if ( $group eq 'AllUsersGroup' ) {
        return 1;
    }
    if ( $group eq 'AllAuthUsersGroup' ) {
        return $cUID ne 'BaseUserMapping_666';
    }
    my $mapping = $this->_getMapping( $cUID );
    my $otherMapping =
      ( $mapping eq $this->{basemapping} )
      ? $this->{mapping}
      : $this->{basemapping};
    return 1 if( $mapping->isInGroup( $cUID, $group, undef, $topic, $web ) );

    return $otherMapping->isInGroup( $cUID, $group, undef, $topic, $web )
      if ( $otherMapping ne $mapping );
}

=pod

---++ ObjectMethod eachMembership($cUID) -> $iterator

Return an iterator over the groups that $cUID
is a member of.

=cut

sub eachMembership {
    my ( $this, $cUID ) = @_;

    my $mapping  = $this->_getMapping( $cUID );
    my $wikiname = $mapping->getWikiName( $cUID );

    #stop if the user has no wikiname (generally means BugsItem4771)
    unless ( defined( $wikiname ) ) {
        require TWiki::ListIterator;
        return new TWiki::ListIterator( \() );
    }

    my $otherMapping =
      ( $mapping eq $this->{basemapping} )
      ? $this->{mapping}
      : $this->{basemapping};

    if ( $mapping eq $otherMapping ) {
        # only using BaseMapping.
        return $mapping->eachMembership( $cUID );
    }

    my @list =
      ( $mapping->eachMembership( $cUID ), $otherMapping->eachMembership( $cUID ) );
    return new TWiki::AggregateIterator( \@list, 1 );
}

=pod

---++ ObjectMethod checkLogin( $login, $passwordU ) -> $boolean

Finds if the password is valid for the given user. This method is
called using the login name rather than the $cUID so that it can be called
with a user who can be authenticated, but may not be mappable to a
cUID (yet).

Returns 1 on success, undef on failure.

TODO: add special check for BaseMapping admin user's login, and if
its there (and we're in sudo_context?) use that..

=cut

sub checkPassword {
    my ( $this, $login, $pw ) = @_;
    my $mapping = $this->_getMapping( undef, $login, undef, 0 );
    return $mapping->checkPassword( $login, $pw );
}

=pod

---++ ObjectMethod setPassword( $cUID, $newPassU, $oldPassU, $mcp ) -> $boolean

If the $oldPassU matches matches the user's password, then it will
replace it with $newPassU.

If $oldPassU is not correct and not 1, will return 0.

If $oldPassU is 1, will force the change irrespective of
the existing password, adding the user if necessary.

Otherwise returns 1 on success, undef on failure.

$mcp is the "must change password flag" that forces the user to change
the password on next login

=cut

sub setPassword {
    my ( $this, $cUID, $newPassU, $oldPassU, $mcp ) = @_;
    return $this->_getMapping( $cUID )
      ->setPassword( $this->getLoginName( $cUID ), $newPassU, $oldPassU, $mcp );
}

=pod

---++ ObjectMethod passwordError() -> $string

Returns a string indicating the error that happened in the password handlers
TODO: these delayed error's should be replaced with Exceptions.

returns undef if no error

=cut

sub passwordError {
    my ( $this ) = @_;
    return $this->_getMapping()->passwordError();
}

=pod

---++ ObjectMethod removeUser( $cUID ) -> $boolean

Delete the users entry. Removes the user from the password
manager and user mapping manager. Does *not* remove their personal
topics, which may still be linked.

=cut

sub removeUser {
    my ( $this, $cUID ) = @_;
    $this->_getMapping( $cUID )->removeUser( $cUID );
}

=pod

---++ ObjectMethod _USERMANAGER( $twiki, $params )

=cut

sub _USERMANAGER {
    my( $twiki, $params ) = @_;

    my $this = $twiki->{users};
    my $action = $params->{action};

    unless( $this->isAdmin( $this->getCanonicalUserID( $this->{remoteUser} ) ) ) {
        return "__Note:__ User management is reserved to TWiki administrators.";
    }

    if( $action eq 'queryusers' ) {
        return $this->_userManagerQueryUsers( $params );

    } elsif( $action eq 'edituser' ) {
        return $this->_userManagerEditUser( $params );

    } else {
        return "User Manager: Unrecognized or missing action parameter.";
    }
}

=pod

---++ ObjectMethod _userManagerQueryUsers( $params )

=cut

sub _userManagerQueryUsers {
    my( $this, $params ) = @_;

    my $filter = $params->{filter};
    $filter = '.*' if( $filter eq '*' );
    unless( $filter ) {
        return "__Note:__ Specify part of a user name, or =*= for all users.";
    }

    my $text = '';
    my %rows = ();
    my $iterator = $this->eachUser();
    while( $iterator->hasNext() ) {
        my $cUID = $iterator->next();
        my $wikiName = $this->getWikiName( $cUID );
        next unless( $wikiName =~ /$filter/i );

        # FIXME: Quick hack that violates data encapsulation: This module
        # should not assume the data structure of password handlers.
        # It should be data driven like _userManagerEditUser().
        my $data      = $this->getUserData( $cUID );
        my $emails    = '';
        my $mcp       = '';
        my $lpc       = '';
        my $disable   = '';
        my $canModify = 0;

        foreach my $item ( @{$data} ) {
            $canModify = 1 if( $item->{type} ne 'label' );
            my $name  = $item->{name};
            my $value = $item->{value};
            if( $name eq 'emails' ) {
                $emails   = $value;
            } elsif( $name eq 'mcp' ) {
                $mcp      = '  %ICON{choice-yes}%  ' if( $value );
            } elsif( $name eq 'lpc' ) {
                $lpc      = $value;
                if( $lpc =~ '(.*?) *\((\%CALC\{.*)\)' ) {
                    $lpc      = "  <span title=\"$1\" style=\"white-space:nowrap\">$2</span>";
                }
            } elsif( $name eq 'disable' ) {
                $disable  = '  %ICON{choice-yes}%  ' if( $value );
            }
        }

        my $iconName  = $canModify ? 'edittopic' : 'viewtopic';
        my $linkLabel = $canModify ? 'Edit' : 'View';
        $linkLabel    = 'N/A' unless( @{$data} ); # Indicate 'N/A' for empty record
        my $url = $this->{session}->getScriptUrl(
            1, 'view', $TWiki::cfg{SystemWebName}, 'EditUserAccount',
            'user' => $wikiName );
        $text = "| <!--$linkLabel--> [[$url][<span style=\"white-space:nowrap\">"
              . "\%ICON{$iconName}% $linkLabel</span>]] "
              . "| [[$TWiki::cfg{UsersWebName}.$wikiName][$wikiName]] "
              . "| $emails | $mcp | $lpc | $disable |";
        $rows{$wikiName} = $text;
    }

    unless( scalar ( %rows ) ) {
        return "__Note:__ No users found. Specify part of a user name, or =*= for all.";
    }

    $text = "| *Manage* | *User Profile Page* | *E-mail* "
          . "| *MCP* | *LPC* | *Disabled* |\n"
          . join( "\n", map{ $rows{$_} } sort keys( %rows ) ) . "\n"
          . '__Total:__ ' . keys( %rows ) . "\n"
          . '%BB% *MCP*: User must change password' . "\n"
          . '%BB% *LPC*: Last password change' . "\n"
          . '%BB% *Disabled*: User account is disabled' . "\n";

    return $text;
}

=pod

---++ ObjectMethod _userManagerEditUser( $params )

=cut

sub _userManagerEditUser {
    my( $this, $params ) = @_;

    my $wikiName = $params->{user};

    return 'Please specify a user' unless( $wikiName );

    # get cUID the complicated way (not possible to use
    # getCanonicalUserID because of disabled users)
    my $cUID = undef;
    my $iterator = $this->eachUser();
    while( $iterator->hasNext() ) {
        my $c = $iterator->next();
        if( $this->getWikiName( $c ) eq $wikiName ) {
            $cUID = $c;
            last;
        }
    }
    return 'User does not exist' unless( $cUID );

    my $text = '';
    my $data = $this->getUserData( $cUID );
    if( $data ) {
        my $canModify = 0;
        $text .= '<form name="saveuserdata" action="%SCRIPTURLPATH{"manage"}%/'
               . '%BASEWEB%/%BASETOPIC%" method="post">' . "\n";
        $text .= '<input type="hidden" name="action" value="saveUserData" />' . "\n";
        $text .= '<input type="hidden" name="user" value="' . $wikiName . '" />' . "\n";
        $text .= "<noautolink>\n" . '%TABLE{ sort="off" }%' . "\n";
        for( my $i=0; $i < scalar @$data; $i++ ) {
            $canModify = 1 if( $data->[$i]->{type} ne 'label' );
            $text .= $this->_renderUserDataField( $data->[$i] );
        }
        if( $canModify ) {
            $text .= $this->_renderUserDataField(
                {
                    type  => 'submit',
                    value => 'Save'
                } );
        }
        my $cgiQuery = $this->{session}->{request};
        if( $cgiQuery && $cgiQuery->param('saveMsg') ) {
            my $icon = ( $cgiQuery->param('saveMsg') =~ /^Err/ )
                     ? '%ICON{led-red}%' : '%ICON{led-green}%';
            $text .= $this->_renderUserDataField(
                {
                    type  => 'label',
                    name  => 'savemsg',
                    value => '<div style="color:#A6000B; background-color:#F5F4AB;'
                           . ' padding: 0 3px 0 3px"> ' . $icon . ' '
                           . $cgiQuery->param( 'saveMsg' ) . '</div>'
                } );
        }
        $text .= "</noautolink>\n</form>\n";
    }

    return $text;
}

=pod

---++ ObjectMethod _renderUserDataField( $fieldRef )

=cut

sub _renderUserDataField {
    my( $this, $field ) = @_;
    my $cell1 = '';
    $cell1    = $field->{title} . ':' if( $field->{title} );
    my $cell2 = $field->{value};
    if( $field->{type} =~ /^(text|password)$/ ) {
        $cell2 = '<input type="' . $field->{type}
               . '" name="ud_'  . $field->{name}
               . '" value="' . TWiki::entityEncode( $field->{value} )
               . '" size="'  . $field->{size}
               . '" class="twikiInputField" />';
    } elsif( $field->{type} eq 'checkbox' ) {
        $cell1 = '';
        my $checked = $field->{value} ? '" checked="checked' : '';
        $cell2 = '<input type="checkbox'
               . '" name="ud_'  . $field->{name}
               . '" id="'    . $field->{name}
               . $checked
               . '" class="twikiCheckbox" />'
               . '<label for="' . $field->{name}
               . '"> ' . $field->{title} . ' </label>';
    } elsif( $field->{type} eq 'submit' ) {
        $cell2 = '<input type="submit'
               . '" value="' . $field->{value}
               . '" class="twikiSubmit" />';
    } else {
        # 'label'
    }

    $cell2 .= ' <br /> %GRAY% %BULLET% ' . $field->{note} . ' %ENDCOLOR%' if( $field->{note} );

    return( "|  $cell1 | $cell2 |\n" );
}

=pod

---++ ObjectMethod canCreateWeb($web) -> $boolean

=cut

sub canCreateWeb {
    my( $this, $web ) = @_;
    my $cUID = $this->{session}{user};
    my $mapping = $this->_getMapping( $cUID );
    if ( $mapping && $mapping->can( 'canCreateWeb' ) ) {
        return $mapping->canCreateWeb($cUID, $web);
    }
    return 0;
}

=pod

---++ ObjectMethod canRenameWeb($oldWeb, $newWeb) -> $boolean

=cut

sub canRenameWeb {
    my( $this, $oldWeb, $newWeb ) = @_;
    my $cUID = $this->{session}{user};
    my $mapping = $this->_getMapping( $cUID );
    if ( $mapping && $mapping->can( 'canRenameWeb' ) ) {
        return $mapping->canRenameWeb($cUID, $oldWeb, $newWeb);
    }
    return 0;
}

=pod

---++ ObjectMethod getAffiliation($cUID) -> $affiliation

=cut

sub getAffiliation {
    my( $this, $cUID ) = @_;
    my $mapping = $this->_getMapping( $cUID );
    if ( $mapping->can( 'getAffiliation' ) ) {
        return $mapping->getAffiliation($cUID);
    }
    return undef;
}

1;
