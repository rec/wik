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

=begin twiki

---+ package TWiki::Users::HtPasswdUser

Support for htpasswd and htdigest format password files.

Subclass of [[TWikiUsersPasswordDotPm][ =TWiki::Users::Password= ]].
See documentation of that class for descriptions of the methods of this class.

=cut

package TWiki::Users::HtPasswdUser;
use base 'TWiki::Users::Password';

use strict;
use Assert;

# 'Use locale' for internationalisation of Perl sorting in getTopicNames
# and other routines - main locale settings are done in TWiki::setupLocale
BEGIN {

    # Do a dynamic 'use locale' for this module
    if ( $TWiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }

    # moved srand call to TWiki::Users::BEGIN, as there is a call to rand
    # there that would not be covered if some other TWiki::Users::Password
    # impl was used.
}

sub new {
    my ( $class, $session ) = @_;
    my $this = bless( $class->SUPER::new($session), $class );
    $this->{error} = undef;
    if ( $TWiki::cfg{Htpasswd}{Encoding} eq 'md5' ) {
        require Digest::MD5;
    } elsif ( $TWiki::cfg{Htpasswd}{Encoding} eq 'sha1' ) {
        require MIME::Base64;
        import MIME::Base64 qw( encode_base64 );
        require Digest::SHA;
        # import Digest::SHA1 qw( sha1 );
    }
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
    $this->SUPER::finish();
    undef $this->{passworddata};
}

=pod

---++ ObjectMethod readOnly(  ) -> boolean

returns true if the password file is not currently modifyable

=cut

sub readOnly {
    my $this = shift;
    my $path = $TWiki::cfg{Htpasswd}{FileName};

    #TODO: what if the data dir is also read only?
    if ( ( !-e $path ) || ( -e $path && -r $path && !-d $path && -w $path ) ) {
        $this->{session}->enterContext( 'passwords_modifyable' );
        return 0;
    }
    return 1;
}

sub canFetchUsers {
    return 1;
}

sub fetchUsers {
    my $this  = shift;
    my $db    = _readPasswd( $this );
    my @users = sort keys %$db;
    require TWiki::ListIterator;
    return new TWiki::ListIterator( \@users );
}

sub _readPasswd {
    my $this = shift;
    $this->{error} = undef;

    return $this->{passworddata} if ( defined( $this->{passworddata} ) );

    my $data = {};
    if ( !-e $TWiki::cfg{Htpasswd}{FileName} ) {
        return $data;
    }

    unless( open( IN_FILE, "<$TWiki::cfg{Htpasswd}{FileName}" ) ) {
        $this->{error} = $TWiki::cfg{Htpasswd}{FileName} . ' open failed: ' . $!;
        return $data;
    }

    my $line = '';
    if ( $TWiki::cfg{Htpasswd}{Encoding} eq 'md5' ) {
        # htdigest format: UserName:AuthRealm:password:email1,email2:mustChgPwd:pwdChgTime
        while (defined ( $line =<IN_FILE> ) ) {
            chomp( $line );
            my @tokens = split( /:/, $line );
            next if( $#tokens < 2 );
            if( $tokens[0] =~ /^#/ ) {
                $tokens[0] =~ s/^#+ *//;
                $data->{$tokens[0]}->{disabled} = 1;
            } else {
                $data->{$tokens[0]}->{disabled} = 0;
            }
            $data->{$tokens[0]}->{pass}         = $tokens[2] || '';
            $data->{$tokens[0]}->{emails}       = $tokens[3] || '';
            $data->{$tokens[0]}->{mustChgPwd}   = $tokens[4] || 0;
            $data->{$tokens[0]}->{pwdChgTime}   = $tokens[5] || 0;
        }
    } else {
        # htpasswd format: UserName:password:email1,email2:mustChgPwd:pwdChgTime
        while (defined ( $line =<IN_FILE> ) ) {
            chomp( $line );
            my @tokens = split( /:/, $line );
            next if( $#tokens < 1 );
            if( $tokens[0] =~ /^#/ ) {
                $tokens[0] =~ s/^#+ *//;
                $data->{$tokens[0]}->{disabled} = 1;
            } else {
                $data->{$tokens[0]}->{disabled} = 0;
            }
            $data->{$tokens[0]}->{pass}         = $tokens[1] || '';
            $data->{$tokens[0]}->{emails}       = $tokens[2] || '';
            $data->{$tokens[0]}->{mustChgPwd}   = $tokens[3] || 0;
            $data->{$tokens[0]}->{pwdChgTime}   = $tokens[4] || 0;
        }
    }
    close( IN_FILE );
    # use Data::Dumper;
    # print STDERR Dumper( $data );

    $this->{passworddata} = $data;
    return $data;
}

sub _dumpPasswd {
    my $db = shift;

    my $s = '';
    my $text = join( "\n",
        sort
        map{
            $s  = '';
            $s .= '#' if( $db->{$_}->{disabled} );
            $s .= $_ . ':';
            $s .= $TWiki::cfg{AuthRealm} . ':' if ( $TWiki::cfg{Htpasswd}{Encoding} eq 'md5' );
            $s .= $db->{$_}->{pass} . ':'
                . $db->{$_}->{emails} . ':'
                . $db->{$_}->{mustChgPwd} . ':'
                . $db->{$_}->{pwdChgTime};
            $s;
        }
        keys( %$db )
      ) . "\n";

    return $text;
}

sub _savePasswd {
    my $this = shift;
    my $db = shift;
    $this->{error} = undef;

    umask( 077 );
    unless( open( FILE, ">$TWiki::cfg{Htpasswd}{FileName}" ) ) {
        $this->{error} = $TWiki::cfg{Htpasswd}{FileName} . ' open failed: ' . $!;
        return $this->{error};
    }

    print FILE _dumpPasswd( $db );
    unless( close( FILE ) ) {
        $this->{error} = $TWiki::cfg{Htpasswd}{FileName} . ' close failed: ' . $!;
    }
    return $this->{error};
}

sub encrypt {
    my ( $this, $login, $passwd, $fresh ) = @_;

    $passwd ||= '';

    if ( $TWiki::cfg{Htpasswd}{Encoding} eq 'sha1' ) {
        my $encodedPassword =
          '{SHA}' . MIME::Base64::encode_base64( Digest::SHA::sha1($passwd) );

        # don't use chomp, it relies on $/
        $encodedPassword =~ s/\s+$//;
        return $encodedPassword;

    } elsif ( $TWiki::cfg{Htpasswd}{Encoding} eq 'crypt' ) {

        # by David Levy, Internet Channel, 1997
        # found at http://world.inch.com/Scripts/htpasswd.pl.html

        my $salt;
        $salt = $this->fetchPass( $login ) unless( $fresh );
        if ( $fresh || !$salt ) {
            my @saltchars = ( 'a'..'z', 'A'..'Z', '0'..'9', '.', '/' );
            $salt =
                $saltchars[ int( rand( $#saltchars + 1 ) ) ]
              . $saltchars[ int( rand( $#saltchars + 1 ) ) ];
        }
        return crypt( $passwd, substr( $salt, 0, 2 ) );

    } elsif ( $TWiki::cfg{Htpasswd}{Encoding} eq 'md5' ) {

        # SMELL: what does this do if we are using a htpasswd file?
        my $toEncode = "$login:$TWiki::cfg{AuthRealm}:$passwd";
        return Digest::MD5::md5_hex( $toEncode );

    } elsif ( $TWiki::cfg{Htpasswd}{Encoding} eq 'crypt-md5' ) {
        my $salt = $this->fetchPass( $login ) unless( $fresh );
        if ( $fresh || !$salt ) {
            $salt = '$1$';
            my @saltchars = ( '.', '/', 0..9, 'A'..'Z', 'a'..'z' );
            foreach my $i ( 0 .. 7 ) {

                # generate a salt not only from rand() but also mixing in
                # the users login name: unecessary
                $salt .= $saltchars[
                  (
                      int( rand( $#saltchars + 1 ) ) +
                        $i +
                        ord( substr( $login, $i % length( $login ), 1 ) ) )
                  % ( $#saltchars + 1 )
                ];
            }
        }
        my $ret = crypt( $passwd, substr( $salt, 0, 11 ) );
        return $ret;

    } elsif ( $TWiki::cfg{Htpasswd}{Encoding} eq 'plain' ) {
        return $passwd;

    }
    die 'Unsupported password encoding ' . $TWiki::cfg{Htpasswd}{Encoding};
}

sub fetchPass {
    my ( $this, $login ) = @_;
    my $ret = 0;

    if ( $login ) {
        my $db = $this->_readPasswd();
        unless( $this->{error} ) {
            if ( exists $db->{$login} && ! $db->{$login}{disabled} ) {
                $ret = $db->{$login}->{pass};
            } else {
                $this->{error} = 'Login invalid';
                $ret = undef;
            }
        }

    } else {
        $this->{error} = 'No user';
    }
    return $ret;
}

sub setPassword {
    my ( $this, $login, $newUserPassword, $oldUserPassword, $mcp ) = @_;
    if ( defined( $oldUserPassword ) ) {
        unless ( $oldUserPassword eq '1' ) {
            return 0 unless $this->checkPassword( $login, $oldUserPassword );
        }

    } elsif ( $this->fetchPass( $login ) ) {
        $this->{error} = $login . ' already exists';
        return 0;
    }

    my $db = $this->_readPasswd();
    unless( $this->{error} ) {
        $db->{$login}->{pass}       = $this->encrypt( $login, $newUserPassword, 1 );
        $db->{$login}->{emails}   ||= '';
        $db->{$login}->{pwdChgTime} = time();
        $db->{$login}->{mustChgPwd} = $mcp ? 1 : 0;
        $this->_savePasswd( $db );
    }
    if( $this->{error} ) {
        print STDERR "ERROR: failed to resetPassword - " . $this->{error};
        return undef;
    }

    $this->{error} = undef;
    return 1;
}

sub removeUser {
    my ( $this, $login ) = @_;
    my $result = undef;
    $this->{error} = undef;

    my $db = $this->_readPasswd();
    unless( $this->{error} ) {
        unless ( $db->{$login} ) {
            $this->{error} = 'No such user ' . $login;
        } else {
            delete $db->{$login};
            $this->_savePasswd( $db );
            $result = 1;
        }
    }
    return $result;
}

sub checkPassword {
    my ( $this, $login, $password ) = @_;
    my $encryptedPassword = $this->encrypt( $login, $password );

    $this->{error} = undef;

    my $pw = $this->fetchPass( $login );
    return 0 unless defined $pw;

    # $pw will be 0 if there is no pw

    return 1 if ( $pw && ( $encryptedPassword eq $pw ) );

    # pw may validly be '', and must match an unencrypted ''. This is
    # to allow for sysadmins removing the password field in .htpasswd in
    # order to reset the password.
    return 1 if ( defined $password && $pw eq '' && $password eq '' );

    $this->{error} = 'Invalid user/password';
    return 0;
}

sub isManagingEmails {
    return 1;
}

sub getEmails {
    my ( $this, $login ) = @_;

    # first try the mapping cache
    my $db = $this->_readPasswd();
    if ( $db->{$login}->{emails} && ! $db->{$login}{disabled} ) {
        return split( /;/, $db->{$login}->{emails} );
    }

    return;
}

sub setEmails {
    my $this  = shift;
    my $login = shift;
    ASSERT( $login ) if DEBUG;

    my $db = $this->_readPasswd();
    unless ( $db->{$login} ) {
        $db->{$login}->{pass} = '';
    }

#SMELL: this makes no sense. - the if above suggests that we can get to this point without $db->{$login}
#  what use is going on if the user is not in the auth system?
    if ( defined( $_[0] ) ) {
        $db->{$login}->{emails} = join( ';', @_ );
    } else {
        $db->{$login}->{emails} = '';
    }
    $this->_savePasswd( $db );
    return 1;
}

# Searches the password DB for users who have set this email.
sub findUserByEmail {
    my ( $this, $email ) = @_;
    my $logins = [];
    my $db     = _readPasswd();
    while ( my ( $k, $v ) = each %$db ) {
        next if( $v->{disabled} );
        my %ems = map { $_ => 1 } split( ';', $v->{emails} );
        if ( $ems{$email} ) {
            push( @$logins, $k );
        }
    }
    return $logins;
}

=pod

---++ ObjectMethod getMustChangePassword( $cUID ) -> $flag

Returns 1 if the $cUID must change the password, else 0. Returns undef if $cUID not found.

=cut

sub getMustChangePassword {
    my( $this, $cUID ) = @_;

    my $db = $this->_readPasswd();
    return undef unless( $db->{$cUID} );
    return $db->{$cUID}->{mustChgPwd};
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
    my( $this, $cUID ) = @_;

    my $db = $this->_readPasswd();
    return undef unless( $db->{$cUID} );

    my $wikiName  = "[[$TWiki::cfg{UsersWebName}.$cUID][$cUID]]";
    my $login     = $cUID;
    my $emails    = join( ', ', split( /;/, $db->{$cUID}->{emails} ) );
    my $pwdChgStr = '';
    if( $db->{$cUID}->{pwdChgTime} ) {
        $pwdChgStr = '%CALC{$FORMATGMTIME('
                   . $db->{$cUID}->{pwdChgTime}
                   . ', $year-$mo-$day $hour:$min GMT)}%'
                   . ' (%CALC{$FORMATTIMEDIFF(sec, 1, $TIMEDIFF('
                   . $db->{$cUID}->{pwdChgTime}
                   . ', $TIME(), sec))}% ago)';
    }

    my $data;
    my $i = 0;
    $data->[$i++] = { name => 'wikiname', title => 'User profile page',
        value => $wikiName, type => 'label', size  => 40, note => '' };
    $data->[$i++] = { name => 'login',    title => 'Login name',
        value => $login, type => 'label', size  => 40, note => '' };
    $data->[$i++] = { name => 'emails',   title => 'E-mail',
        value => $emails, type => 'text', size  => 40,
        note => 'Separate multiple e-mail addresses by comma or space' };
    $data->[$i++] = { name => 'password', title => 'Password',
        value => '', type => 'password', size  => 40, note => '' };
    $data->[$i++] = { name => 'confirm',  title => 'Retype password',
        value => '', type => 'password', size  => 40,
        note => 'Leave password fields empty unless you want to change it' };
    $data->[$i++] = { name => 'mcp',      title => 'Must change password',
        value => $db->{$cUID}->{mustChgPwd}, type => 'checkbox', size  => 1, note => '' };
    $data->[$i++] = { name => 'lpc',      title => 'Last password change', 
        value => $pwdChgStr, type => 'label', size  => 40, note => '' };
    $data->[$i++] = { name => 'disable',  title => 'Disable account', 
        value => $db->{$cUID}->{disabled}, type => 'checkbox', size  => 1,
        note => 'Disabled accounts cannot login but remain in the system' };

    return $data;
}

=pod

---++ ObjectMethod setUserData( $cUID, $dataRef )

Set the user data of a user. Same array of hashes as getUserData is 
assumed, although only ={name}= and ={value}= are used.

Returns an empty string if save action is OK, or an error string 
starting with 'Error: ' if there is an error.

=cut

sub setUserData {
    my( $this, $cUID, $data ) = @_;

    my $emails   = '';
    my $password = '';
    my $confirm  = '';
    my $mcp      = 0;
    my $disable  = 0;

    foreach my $item ( @{$data} ) {
        my $name  = $item->{name};
        my $value = $item->{value};
        if( $name eq 'emails' ) {
            $emails   = join( ';', split( /[,; ]+/, $value ) );
        } elsif( $name eq 'password' ) {
            $password = $value;
        } elsif( $name eq 'confirm' ) {
            $confirm  = $value;
        } elsif( $name eq 'mcp' ) {
            $mcp      = 1 if( $value );
        } elsif( $name eq 'disable' ) {
            $disable  = 1 if( $value );
        }
    }

    my $db = $this->_readPasswd();
    if( $this->{error} ) {
        return 'Error: Failed to read user data - ' . $this->{error};
    }

    unless ( $db->{$cUID} ) {
        return "Error: User =$cUID= does not exist";
    }

    if( $password && $confirm ) {
        if( $password ne $confirm ) {
            return 'Error: Passwords do not match';
        }
        if( length( $password ) < $TWiki::cfg{MinPasswordLength} ) {
            return 'Error: Bad password. This site requires at least '
                . $TWiki::cfg{MinPasswordLength} . ' character passwords';
        }

        $db->{$cUID}->{pass}       = $this->encrypt( $cUID, $password, 1 );
        $db->{$cUID}->{pwdChgTime} = time();
    }

    $db->{$cUID}->{emails}     = $emails;
    $db->{$cUID}->{mustChgPwd} = $mcp;
    $db->{$cUID}->{disabled}   = $disable;

    $this->_savePasswd( $db );
    if( $this->{error} ) {
        return 'Error: Failed to upate user data - ' . $this->{error};
    }

    return '';
}

1;
