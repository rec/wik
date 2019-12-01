# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 1999-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Part of this module is based on "bin/twiki" script, which is:
#    Copyright (C) 2005 Martin at Cleaver.org
#    Copyright (C) 2005-2007 TWiki Contributors
# 
# and also based/inspired on Catalyst framework, whose Author is
# Sebastian Riedel. Refer to
#
# http://search.cpan.org/~mramberg/Catalyst-Runtime-5.7010/lib/Catalyst.pm
# 
# for more credit and liscence details.
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

---+!! package TWiki::UI

Coordinator of execution flow and service functions used by the UI packages

=cut

package TWiki::UI;
use strict;

BEGIN {
    $TWiki::cfg{SwitchBoard} ||= {};
    $TWiki::cfg{SwitchBoard}{attach} =
      [ 'TWiki::UI::Upload',     'attach',        { attach      => 1 } ];
    $TWiki::cfg{SwitchBoard}{changes} =
      [ 'TWiki::UI::Changes',    'changes',       { changes     => 1 } ];
    $TWiki::cfg{SwitchBoard}{copy} =
      [ 'TWiki::UI::Copy',       'copy',          { copy        => 1 } ];
    $TWiki::cfg{SwitchBoard}{edit} =
      [ 'TWiki::UI::Edit',       'edit',          { edit        => 1 } ];
    $TWiki::cfg{SwitchBoard}{login} =
      [ undef,                   'logon',         { (login=>1, logon=>1) } ];
    $TWiki::cfg{SwitchBoard}{logon} =
      [ undef,                   'logon',         { (login=>1, logon=>1) } ];
    $TWiki::cfg{SwitchBoard}{manage} =
      [ 'TWiki::UI::Manage',     'manage',        { manage      => 1 } ];
    $TWiki::cfg{SwitchBoard}{oops} =
      [ 'TWiki::UI::Oops',       'oops_cgi',      { oops        => 1 } ];
    $TWiki::cfg{SwitchBoard}{preview} =
      [ 'TWiki::UI::Preview',    'preview',       { preview     => 1 } ];
    $TWiki::cfg{SwitchBoard}{rdiffauth} =
      [ 'TWiki::UI::RDiff',      'diff',          { diff        => 1 } ];
    $TWiki::cfg{SwitchBoard}{rdiff} =
      [ 'TWiki::UI::RDiff',      'diff',          { diff        => 1 } ];
    $TWiki::cfg{SwitchBoard}{register} =
      [ 'TWiki::UI::Register',   'register_cgi',  { register    => 1 } ];
    $TWiki::cfg{SwitchBoard}{rename} =
      [ 'TWiki::UI::Manage',     'rename',        { rename      => 1 } ];
    $TWiki::cfg{SwitchBoard}{resetpasswd} =
      [ 'TWiki::UI::Register',   'resetPassword', { resetpasswd => 1 } ];
    $TWiki::cfg{SwitchBoard}{rest} =
      [ 'TWiki::UI::Rest',       'rest',          { rest        => 1 } ];
    $TWiki::cfg{SwitchBoard}{save} =
      [ 'TWiki::UI::Save',       'save',          { save        => 1 } ];
    $TWiki::cfg{SwitchBoard}{search} =
      [ 'TWiki::UI::Search',     'search',        { search      => 1 } ];
    $TWiki::cfg{SwitchBoard}{statistics} =
      [ 'TWiki::UI::Statistics', 'statistics',    { statistics  => 1 } ];
    $TWiki::cfg{SwitchBoard}{upload} =
      [ 'TWiki::UI::Upload',     'upload',        { upload      => 1 } ];
    $TWiki::cfg{SwitchBoard}{viewauth} =
      [ 'TWiki::UI::View',       'view',          { view        => 1 } ];
    $TWiki::cfg{SwitchBoard}{viewfile} =
      [ 'TWiki::UI::View',       'viewfile',      { viewfile    => 1 } ];
    $TWiki::cfg{SwitchBoard}{view} =
      [ 'TWiki::UI::View',       'view',          { view        => 1 } ];
    $TWiki::cfg{SwitchBoard}{mdrepo} =
      [ 'TWiki::UI::MdrepoUI',    'mdrepo',       { mdrepo      => 1 } ];
}

use Error qw(:try);
use Assert;

use TWiki;
use TWiki::Request;
use TWiki::Response;
use TWiki::OopsException;
use TWiki::EngineException;
use TWiki::UI::Oops;
use CGI;

# Used to lazily load UI handler modules
our %isInitialized = ();

sub TRACE_PASSTHRU {
    # Change to a 1 to trace passthrough
    0;
};

=begin twiki

---++ StaticMethod handleRequest($req) -> $res

Main coordinator of request-process-response cycle.

=cut

sub handleRequest {
    my $req = shift;

    my $res;
    my $dispatcher = $TWiki::cfg{SwitchBoard}{$req->action()};
    unless (defined $dispatcher && ref($dispatcher) eq 'ARRAY') {
        $res = new TWiki::Response();
        $res->header(-type => 'text/html', -status => '404');
        my $html = CGI::start_html('404 Not Found');
        $html .=   CGI::h1('Not Found');
        $html .=   CGI::p("The requested URL " . $req->uri . " was not found on this server.");
        $html .=   CGI::end_html();
        $res->body($html);
        return $res;
    }
    my ( $package, $function, $context ) = @$dispatcher;

    if ($package && !$isInitialized{$package}) {
        eval qq(use $package);
        die $@ if $@;
        $isInitialized{$package} = 1;
    }

    my $sub;
    $sub  = $package.'::' if $package;
    $sub .= $function;

    my $cache = $req->param('twiki_redirect_cache');
    # Never trust input data from a query. We will only accept an MD5 32 character string
    if ( $cache && $cache =~ /^([a-f0-9]{32})$/ ) {
        $cache = $1;
        # Read cached post parameters
        my $passthruFilename =
          $TWiki::cfg{WorkingDir} . '/tmp/passthru_' . $cache;
        if ( open( F, '<', $passthruFilename ) ) {
            local $/;
            if (TRACE_PASSTHRU) {
                print STDERR "Passthru: Loading cache for ", $req->url(),
                  '?', $req->query_string(), "\n";
                print STDERR <F>, "\n";
                close(F);
                open( F, '<' . $passthruFilename );
            }
            $req->load(\*F);
            close(F);
            unlink($passthruFilename);
            $req->delete('twiki_redirect_cache');
            print STDERR "Passthru: Loaded and unlinked $passthruFilename\n"
              if TRACE_PASSTHRU;
            $req->method('POST');
        }
        else {
            print STDERR "Passthru: Could not find $passthruFilename\n"
              if TRACE_PASSTHRU;
        }
    }

    if ( UNIVERSAL::isa($TWiki::engine, 'TWiki::Engine::CLI') ) {
        $context->{command_line} = 1;
    }

    $res = execute($req, \&$sub, %$context );
    return $res;
}

=begin twiki

---++ StaticMethod execute($req, $sub, %initialContext) -> $res

Creates a TWiki session object with %initalContext and calls
$sub method. Returns the TWiki::Response object generated

=cut

sub execute {
    my ($req, $sub, %initialContext ) = @_;

    my $session = new TWiki( $req->remoteUser, $req, \%initialContext );
    my $res = $session->{response};

    unless ( defined $session->{response}->status()
        && $session->{response}->status() =~ /^\s*3\d\d/ )
    {
        try {
            $session->{users}->{loginManager}->checkAccess();
            &$sub($session);
        }
        catch TWiki::AccessControlException with {
            my $e = shift;
            unless ( $session->{users}->{loginManager}->forceAuthentication() )
            {

                # Login manager did not want to authenticate, perhaps because
                # we are already authenticated.
                my $exception = new TWiki::OopsException(
                    'accessdenied',
                    web    => $e->{web},
                    topic  => $e->{topic},
                    def    => 'topic_access',
                    status => '403 Forbidden',
                    params => [ $e->{mode}, $e->{reason} ]
                );

                # Item7320
                # it used to $exception->redirect($session);
                TWiki::UI::Oops::oops($session, $e->{web}, $e->{topic}, $req,
                                      $exception);
            }
        }
        catch TWiki::OopsException with {
            # Item7320
            # It used to shift->redirect($session);
            my $e = shift;
            TWiki::UI::Oops::oops($session, $e->{web}, $e->{topic}, $req, $e);
        }
        catch Error::Simple with {
            my $e = shift;
            $res = new TWiki::Response;
            $res->header( -type => 'text/plain' );
            if (DEBUG) {

                # output the full message and stacktrace to the browser
                $res->body( $e->stringify() );
            }
            else {
                my $mess = $e->stringify();
                print STDERR $mess;
                $session->writeWarning($mess);

                # tell the browser where to look for more help
                my $text =
'TWiki detected an internal error - please check your TWiki logs and webserver logs for more information.'
                  . "\n\n";
                $mess =~ s/ at .*$//s;

                # cut out pathnames from public announcement
                $mess =~ s#/[\w./]+#path#g;
                $text .= $mess;
                $res->body($text);
            }
        }
        catch TWiki::EngineException with {
            my $e   = shift;
            my $res = $e->{response};
            unless ( defined $res ) {
                $res = new TWiki::Response();
                $res->header( -type => 'text/html', -status => $e->{status} );
                my $html = CGI::start_html( $e->{status} . ' Bad Request' );
                $html .= CGI::h1('Bad Request');
                $html .= CGI::p( $e->{reason} );
                $html .= CGI::end_html();
                $res->body($html);
            }
            $TWiki::engine->finalizeError($res);
            return $e->{status};
        }
        otherwise {
            $res = new TWiki::Response;
            $res->header( -type => 'text/plain' );
            $res->body("Unspecified error");
        };
    }

    $session->finish();
    return $res;
}

=begin twiki

---++ StaticMethod logon($session)

Handler to "logon" action.
   * =$session= is a TWiki session object

=cut

sub logon {
  my $session = shift;
  $session->{users}->{loginManager}->login( $session->{request}, $session );
}

=pod twiki

---++ StaticMethod checkWebExists( $session, $web, $topic, $op )

Check if the web exists. If it does not, will throw an oops exception.
 $op is the user operation being performed.

=cut

sub checkWebExists {
    my ( $session, $webName, $topic, $op ) = @_;
    ASSERT($session->isa( 'TWiki')) if DEBUG;

    unless ( $session->{store}->webExists( $webName ) ) {
        if( $TWiki::cfg{Log}{view} ) {
            $session->writeLog( $op, $webName.'.'.$topic, "(web doesn't exist)" );
        }
        throw
          TWiki::OopsException( 'notfound',
                                def => 'no_such_web',
                                web => $webName,
                                topic => $topic,
                                status => '404 Not Found',
                                params => [ $op ] );
    }
}

=pod

---++ StaticMethod topicExists( $session, $web, $topic, $op ) => boolean

Check if the given topic exists, throwing an OopsException
if it doesn't. $op is the user operation being performed.

=cut

sub checkTopicExists {
    my ( $session, $webName, $topic, $op ) = @_;
    ASSERT($session->isa( 'TWiki')) if DEBUG;

    unless( $session->{store}->topicExists( $webName, $topic )) {
        throw TWiki::OopsException( 'notfound',
                                    def => 'no_such_topic',
                                    web => $webName,
                                    topic => $topic,
                                    status => '404 Not Found',
                                    params => [ $op ] );
    }
}

=pod twiki

---++ StaticMethod checkWebWritable( $session )

Checks if this web is writable on this site, Throwing an exception
if it is not.

=cut

sub checkWebWritable {
    my ( $session, $web ) = @_;
    ASSERT($session->isa( 'TWiki')) if DEBUG;

    unless ( $session->webWritable($web) ) {
        throw TWiki::OopsException( 'accessdenied',
                                    def => 'not_writable',
                                    web => $web,
                                    topic => 'WebHome',
                                    status => '403 Forbidden',
            );
    }
    return;
}

=pod twiki

---++ StaticMethod checkAccess( $web, $topic, $mode, $user )

Check if the given mode of access by the given user to the given
web.topic is permissible, throwing a TWiki::OopsException if not.

=cut

sub checkAccess {
    my ( $session, $web, $topic, $mode, $user ) = @_;
    ASSERT($session->isa( 'TWiki')) if DEBUG;

    unless( $session->security->checkAccessPermission(
        $mode, $user, undef, undef, $topic, $web )) {
        throw TWiki::OopsException( 'accessdenied',
                                    def => 'topic_access',
                                    web => $web,
                                    topic => $topic,
                                    status => '403 Forbidden',
                                    params =>
                                      [ $mode,
                                        $session->security->getReason()]);
    }

    if( $session->{users}->getMustChangePassword( $user ) 
        && "$web.$topic" ne "$TWiki::cfg{SystemWebName}.ChangePassword"
    ) {
        my $wikiname = $session->{users}->getWikiName( $user ) || $user;
        my $url = $session->getScriptUrl( 1, 'view',
            $TWiki::cfg{SystemWebName}, 'ChangePassword',
            username => $wikiname,
            mcp => '1' );
        $session->redirect( $url );
    }
}

=pod

---++ StaticMethod readTemplateTopic( $session, $theTopicName ) -> ( $meta, $text )

Search for a template topic in current web, Main web, and TWiki web, in that order.

=cut

sub readTemplateTopic {
    my( $session, $theTopicName ) = @_;
    ASSERT($session->isa( 'TWiki')) if DEBUG;

    $theTopicName =~ s/$TWiki::cfg{NameFilter}//go;

    my $web = $TWiki::cfg{SystemWebName};
    if( $session->{store}->topicExists( $session->{webName}, $theTopicName )) {
        # try to read from current web, if found
        $web = $session->{webName};
    } elsif( $session->{store}->topicExists( $TWiki::cfg{UsersWebName}, $theTopicName )) {
        # try to read from current web, if found
        $web = $TWiki::cfg{UsersWebName};
    }
    return $session->{store}->readTopic( $session->{user}, $web, $theTopicName, undef );
}

=pod

---++ StaticMethod run( $method )

Supported for bin scripts that were written for TWiki < 5.0. The
parameter is a function reference to the UI method to call, and is ignored
in TWiki >= 5.0, where it should be replaced by a Config.spec entry such as:

# **PERL H**
# Bin script registration - do not modify
$TWiki::cfg{SwitchBoard}{publish} = [ "TWiki::Contrib::Publish", "publish", { publishing => 1 } ];

=cut



=pod

---++ StaticMethod verifyCryptToken( $session, $crypt_token )


=cut



sub verifyCryptToken {
    my ($session, $crypt_token) = @_;
    my $cgi = $session->{users}->{loginManager}->{_cgisession};
    my $id = $cgi->id();
    my $webName = $session->{webName};
    my $topicName = $session->{topicName};
    my $success = 0;
    use CGI::Session;

    if( defined $crypt_token ) {
        my $cgisess =
          CGI::Session->new( undef, $id,
                             { Directory => "$TWiki::cfg{WorkingDir}/tmp" } );
        my $crypttokens = $cgisess->param('CryptToken');

        foreach my $token (@$crypttokens) {
            foreach (keys %$token) {
                if ($token->{$_}  eq $crypt_token) {
                    $success = 1;
                    # cleanup of token from session data-once used token should be
                    # removed from users session
                    $cgisess->close();
                    $session->{users}->{loginManager}->cleanCryptToken($crypt_token);
                    last;
                }
            }
        }
    }

    if (!$success) {

        throw
          TWiki::OopsException( 'invalidtoken',
                                def => 'invalid_token',
                                web => $webName,
                                topic => $topicName,
                                params => [] );
    }

   return $success;

}



sub run {
    $TWiki::engine->run();
}

1;
