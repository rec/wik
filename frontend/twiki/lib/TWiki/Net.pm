# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2001-2018 Peter Thoeny, peter[at]thoeny.org
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

---+ package TWiki::Net

Object that brokers access to network resources.

=cut

# This module is used by configure, and as such must *not* 'use TWiki',
# or any other module that uses it. Always run configure to test after
# changing the module.

package TWiki::Net;

our $TEST_SOCKET_HTTP = 0;

use strict;
use Assert;
use Error qw( :try );

# note that the session is *optional*
sub new {
    my ( $class, $session ) = @_;
    my $this = bless( { session => $session }, $class );

    $this->{mailHandler} = undef;
    $this->{httpHandlers} = [];

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
    undef $this->{mailHandler};
    undef $this->{HELLO_HOST};
    undef $this->{MAIL_HOST};
    undef $this->{httpHandlers};
    undef $this->{session};
}

=pod

---+++ ObjectMethod registerExternalHTTPHandler( \&fn )

See TWikiFuncDotPm#RegisterExternalHTTPHandler

=cut

sub registerExternalHTTPHandler {
    my ($this, $function) = @_;
    push @{$this->{httpHandlers}}, $function;
}

=pod

---+++ ObjectMethod getExternalResource( $url, \@headers, \%params ) -> $response

See TWikiFuncDotPm#GetExternalResource

=cut

sub getExternalResource {
    my ($this, $url, @options) = @_;
    my ($headers, $params) = $this->_options(@options);
    return $this->_requestHTTP(GET => $url, $headers, $params);
}

=pod

---+++ ObjectMethod postExternalResource( $url, $content, \@headers, \%params ) -> $response

See TWikiFuncDotPm#PostExternalResource

=cut

sub postExternalResource {
    my ($this, $url, $content, @options) = @_;
    my ($headers, $params) = $this->_options(@options);
    return $this->_requestHTTP(POST => $url, $headers, $params, $content);
}

# =======================================
sub _options {
    my ($this, @options) = @_;
    my ($headers, $params) = ([], {});

    for my $opt (@options) {
        if (ref $opt eq 'ARRAY') {
            push @$headers, @$opt;
        } elsif (ref $opt eq 'HASH') {
            $params->{$_} = $opt->{$_} foreach keys %$opt;
        } else {
            $this->{session}->writeWarning("Unknown type to request external resource: ".
                (ref($opt) || '(not ref)'));
        }
    }

    return ($headers, $params);
}

# =======================================
sub _requestHTTP {
    my ( $this, $method, $url, $headers, $params, $content ) = @_;

    # Run registered HTTP handlers
    for my $handler ( @{$this->{httpHandlers}} ) {
        my @moreOptions = $handler->( $this->{session}, $url );
        my ($moreHeaders, $moreParams) = $this->_options(@moreOptions);

        # Append all the additional headers
        push @$headers, @$moreHeaders;

        # Import all the additional params
        foreach (keys %$moreParams) {
            # but do not override params set by the caller of getExternalResource
            unless (exists $params->{$_}) {
                $params->{$_} = $moreParams->{$_};
            }
        }
    }

    $method = $params->{method} if defined $params->{method};

    # Detect protocol
    my $protocol;

    if( $url =~ m!^([a-z]+):! ) {
        $protocol = $1;
    } else {
        require TWiki::Net::HTTPResponse;
        return new TWiki::Net::HTTPResponse( "Bad URL: $url" );
    }

    # Attempt LWP
    unless ($TEST_SOCKET_HTTP) {
        eval "use LWP";
        unless( $@ ) {
            unless ( defined $params->{agent} ) {
                '$Rev: 30610 (2018-07-16) $'=~/([0-9]+)/;
                my $revstr=$1;
                $params->{agent} = 'TWiki::Net/'.$revstr." libwww-perl/$LWP::VERSION";
            }

            return $this->_requestUsingLWP( $method, $url, $headers, $params, $content );
        }
    }

    # Fallback mechanism
    if( $protocol ne 'http') {
        require TWiki::Net::HTTPResponse;
        return new TWiki::Net::HTTPResponse( "LWP not available for handling protocol: $url" );
    }

    my $response;
    try {
        $url =~ s!^\w+://!!; # remove protocol
        my ( $user, $pass );
        if( $url =~ s!([^/\@:]+)(?::([^/\@:]+))?@!! ) {
            ( $user, $pass ) = ( $1, $2 || '');
        }

        unless( $url =~ s!([^:/]+)(?::([0-9]+))?!! ) {
            die "Bad URL: $url";
        }
        my( $host, $port ) = ( $1, $2 || 80);

        require Socket;
        import Socket qw(:all);

        $url = '/' unless( $url );
        my $req = "$method $url HTTP/1.0\r\n";

        $req .= "Host: $host:$port\r\n";
        if( $user ) {
            # Use MIME::Base64 at run-time if using outbound proxy with
            # authentication
            require MIME::Base64;
            import MIME::Base64 ();
            my $base64 = encode_base64( "$user:$pass", "\r\n" );
            $req .= "Authorization: Basic $base64"; # "\r\n" added by encode_base64
        }

        my $useproxy = 1;
        if( defined( $TWiki::cfg{PROXY}{SkipProxyForDomains} ) ) { 
            my @skipdomains = split( /[\,\s]+/,  $TWiki::cfg{PROXY}{SkipProxyForDomains} );
            foreach my $domain ( @skipdomains ) {
                next if $domain =~ /^\s*$/;
                if ($domain =~ /^\./) {
                    $domain = quotemeta($domain);
                    if ($host =~ /$domain$/i) {
                        $useproxy = 0;
                    }
                } else {
                    $domain = quotemeta($domain);
                    if ($host =~ /(^|\.)$domain$/i) {
                        $useproxy = 0;
                    }
                }
            }
        }
 
        if ($useproxy) {
            # SMELL: Reference to TWiki variables used for compatibility
            my ($proxyHost, $proxyPort);
            if ($this->{session} && $this->{session}->{prefs}) {
                my $prefs = $this->{session}->{prefs};
                $proxyHost = $prefs->getPreferencesValue( 'PROXYHOST' );
                $proxyPort = $prefs->getPreferencesValue( 'PROXYPORT' );
            }
            $proxyHost ||= $TWiki::cfg{PROXY}{HOST};
            $proxyPort ||= $TWiki::cfg{PROXY}{PORT};
            if( $proxyHost && $proxyPort ) {
                $req =~ s{^.*?\r\n}{$method http://$host:$port$url HTTP/1.0\r\n};
                $host = $proxyHost;
                $port = $proxyPort;
            }
            # TODO: Should we also add Proxy-Authorization as in _requestUsingLWP?
        }

        unless ( defined $params->{agent} ) {
            '$Rev: 30610 (2018-07-16) $'=~/([0-9]+)/;
            my $revstr=$1;
            $params->{agent} = 'TWiki::Net/'.$revstr;
        }

        $req .= "User-Agent: $params->{agent}\r\n";
        if( $headers ) {
            while( my $key = shift @$headers ) {
                my $val = shift( @$headers );
                $req .= "$key: $val\r\n" if( defined $val );
            }
        }

        if (defined $content && $content ne '') { # '0' should not be excluded
            $req .= 'Content-Length: '.length($content)."\r\n";
        }

        $req .= "\r\n"; # End of HTTP Header

        if (defined $content && $content ne '') { # '0' should not be excluded
            $req .= $content;
        }

        my $result = '';
        eval {
            local $SIG{ALRM} = sub {die 'Timed out'};
            alarm $params->{timeout} if $params->{timeout};

            my ( $iaddr, $paddr, $proto );
            $iaddr = inet_aton( $host );
            die "Could not find IP address for $host" unless $iaddr;

            $paddr = sockaddr_in( $port, $iaddr );
            $proto = getprotobyname( 'tcp' );
            unless( socket( *SOCK, &PF_INET, &SOCK_STREAM, $proto ) ) {
                die "socket failed: $!";
            }
            unless( connect( *SOCK, $paddr ) ) {
                die "connect failed: $!";
            }
            select SOCK; $| = 1;
            local $/ = undef;
            print SOCK $req;
            $result = <SOCK>;
            unless( close( SOCK ) ) {
                die "close faied: $!";
            }

            alarm 0 if $params->{timeout};
        };

        alarm 0 if $params->{timeout};
        select STDOUT;

        if ($@) {
            $response = new TWiki::Net::HTTPResponse( $@ );
        }

        # No LWP, but may have HTTP::Response which would make life easier
        # (it has a much more thorough parser)
        eval 'require HTTP::Response';
        if ($@) {
            # Nope, no HTTP::Response, have to do things the hard way :-(
            require TWiki::Net::HTTPResponse;
            $response = TWiki::Net::HTTPResponse->parse( $result );
        } else {
            $response = HTTP::Response->parse( $result );
        }
    } catch Error::Simple with {
        require TWiki::Net::HTTPResponse;
        $response = new TWiki::Net::HTTPResponse( shift );
    };
    return $response;
}

my @LWPUAParamsAllowed = qw(
    agent cookie_jar load_address max_redirect max_size
    parse_head requests_redirectable ssl_opts timeout
);

# =======================================
sub _requestUsingLWP {
    my( $this, $method, $url, $headers, $params, $content ) = @_;
    $headers ||= [];
    $params ||= {};

    my ( $user, $pass );
    if( $url =~ s!^(\w+://)([^/\@:]+)(?::([^/\@:]+))?@!$1! ) {
        ( $user, $pass ) = ( $2, $3 );
    }

    my %initParams;
    my $cfgLWPUAParams = $TWiki::cfg{LWPUserAgent}{Params};
    if ( defined($cfgLWPUAParams) && ref $cfgLWPUAParams eq 'HASH' ) {
        %initParams =
            map { $_ => $cfgLWPUAParams->{$_} }
                grep {exists $cfgLWPUAParams->{$_}} @LWPUAParamsAllowed;
    }
    for my $i ( @LWPUAParamsAllowed ) {
        $initParams{$i} = $params->{$i} if ( exists $params->{$i} );
    }

    require TWiki::Net::UserCredAgent;
    my $ua = new TWiki::Net::UserCredAgent( $user, $pass, $url, \%initParams );

    $ua->credentials(@{$params->{credentials}}) if defined $params->{credentials};

    if (defined $params->{handlers}) {
        for my $phase (keys %{$params->{handlers}}) {
            $ua->add_handler($phase => $params->{handlers}{$phase});
        }
    }

    require HTTP::Request;
    my $request = HTTP::Request->new( $method => $url, $headers, $content );

    if( $TWiki::cfg{PROXY}{Username} && $TWiki::cfg{PROXY}{Password} ) {
        $request->proxy_authorization_basic( $TWiki::cfg{PROXY}{Username}, $TWiki::cfg{PROXY}{Password} );
    }

    return $ua->request($request);
}

# pick a default mail handler
# =======================================
sub _installMailHandler {
    my $this = shift;
    my $handler = 0; # Not undef
    if ($this->{session} && $this->{session}->{prefs}) {
        my $prefs = $this->{session}->{prefs};
        $this->{MAIL_HOST}  = $prefs->getPreferencesValue( 'SMTPMAILHOST' );
        $this->{HELLO_HOST} = $prefs->getPreferencesValue( 'SMTPSENDERHOST' );
    }

    $this->{MAIL_HOST}  ||= $TWiki::cfg{SMTP}{MAILHOST};
    $this->{HELLO_HOST} ||= $TWiki::cfg{SMTP}{SENDERHOST};

    if( $this->{MAIL_HOST} ) {
        # See Codev.RegisterFailureInsecureDependencyCygwin for why
        # this must be untainted
        require TWiki::Sandbox;
        $this->{MAIL_HOST} = TWiki::Sandbox::untaintUnchecked( $this->{MAIL_HOST} );
        eval {   # May fail if Net::SMTP not installed
            require Net::SMTP;
        };
        if( $@ ) {
            $this->{session}->writeWarning( "SMTP not available: $@" )
              if ($this->{session});
        } else {
            $handler = \&_sendEmailByNetSMTP;
        }
    }

    if( !$handler && $TWiki::cfg{MailProgram} ) {
        $handler = \&_sendEmailBySendmail;
    }

    $this->setMailHandler( $handler ) if $handler;
}

=pod

---++ ObjectMethod setMailHandler( \&fn )

   * =\&fn= - reference to a function($) (see _sendEmailBySendmail for proto)
Install a handler function to take over mail sending from the default
SMTP or sendmail methods. This is provided mainly for tests that
need to be told when a mail is sent, without actually sending it. It
may also be useful in the event that someone needs to plug in an
alternative mail handling method.

=cut

sub setMailHandler {
    my( $this, $fnref ) = @_;
    $this->{mailHandler} = $fnref;
}

=pod

---++ ObjectMethod sendEmail ( $text, $tries ) -> $error

   * =$text= - text of the mail, including MIME headers
   * =$tries= - number of times to try the send (default 1)

Send an email specified as MIME format content.
Date: ...\nFrom: ...\nTo: ...\nCC: ...\nSubject: ...\n\nMailBody...

=cut

sub sendEmail {
    my( $this, $text, $tries ) = @_;
    $tries ||= 1;
   
    unless( $TWiki::cfg{EnableEmail} ) {
        return 'Trying to send email while email functionality is disabled';
    }

    unless( defined $this->{mailHandler} ) {
        _installMailHandler( $this );
    }

    return 'No mail handler available' unless( $this->{mailHandler} );

    # Put in a Date header, mainly for Qmail
    require TWiki::Time;
    my $dateStr = TWiki::Time::formatTime( time, '$email' );
    $text = "Date: " . $dateStr . "\n" . $text;

    my $errors = '';
    my $back_off = 1; # seconds, doubles on each retry
    my $nTries = $tries;
    while ( $tries-- ) {
        try {
            &{$this->{mailHandler}}( $this, $text );
            $tries = 0;
        } catch Error::Simple with {
            my $e = shift->stringify();
            $this->{session}->writeWarning( $e );
            # be nasty to errors that we didn't throw. They may be
            # caused by SMTP or perl, and give away info about the
            # install that we don't want to share.
	    $e = join( "\n", grep( /^ERROR/, split( /\n/, $e ) ) );

            unless( $e =~ /^ERROR/ ) {
                $e = "Mail could not be sent - see TWiki warning log.";
            }
            $errors .= $e;
            if ( $tries ) {
                $errors .= "\n";
                sleep( $back_off );
                $back_off *= 2;
            }
            else {
                $errors .= "\nToo many failures sending mail"
                    if ( $nTries > 1 );
            }
        };
    }
    return $errors;
}

# =======================================
sub _fixLineLength {
    my( $addrs ) = @_;
    # split up header lines that are too long
    $addrs =~ s/(.{60}[^,]*,\s*)/$1\n        /go;
    $addrs =~ s/\n\s*$//gos;
    return $addrs;
}

# =======================================
sub _slurpFile( $ ) {
    my $file = shift;

    unless( open( IN, '<', $file ) ) {
	( $<,$>) = ( $>,$<);
	die( "Failed to open $file: $!\n" );
    }
    my $text = do { local( $/ ); <IN> };

    unless( close IN ) {
	( $<,$>) = ( $>,$<);
	die( "Failed to close $file: $!\n" );
    }

    return $text;
}

# =======================================
sub _smimeSignMessage {
    my $this = shift;

    if( $TWiki::cfg{SmimeCertificateFile} && $TWiki::cfg{SmimeKeyFile} ) {
        eval {
            require Crypt::SMIME;
        };if( $@ ) {
            $@ =~ /^(.*?)\n.*\z/s; # Any useful error information is on the first line.
            $this->{session}->writeWarning( "ERROR: Cypt::SMIME is not available: " . ($1 || $@) . ".  Mail will be sent unsigned.\n" )
               if ($this->{session});
            return;
        }
	my $smime = Crypt::SMIME->new();

        my $key = _slurpFile( $TWiki::cfg{SmimeKeyFile} );
        if( exists $TWiki::cfg{SmimeKeyPassword} &&
            length $TWiki::cfg{SmimeKeyPassword} &&
            $key =~ /^-----BEGIN RSA PRIVATE KEY-----\n(?:(.*?\n)\n)?/s ) {
            my %h = map { split( /:\s*/, $_, 2 ) } split( /\n/, $1 ) if( defined $1 );
            if( $h{'Proc-Type'} && $h{'Proc-Type'} eq '4,ENCRYPTED' &&
                $h{'DEK-Info'} && $h{'DEK-Info'} =~ /^DES-EDE3-CBC,/ ) {

                require Convert::PEM;
                my $pem = Convert::PEM->new( Name => 'RSA PRIVATE KEY',
                                             ASN  => qq(
                   RSAPrivateKey SEQUENCE {
                      version INTEGER, n INTEGER, e INTEGER, d INTEGER,
                      p INTEGER, q INTEGER, dp INTEGER, dq INTEGER,
                      iqmp INTEGER
                   }                                   ) );
                $key = $pem->decode( Content => $key,
                                     Password => $TWiki::cfg{SmimeKeyPassword});
                unless( $key ) {
                    $this->{session}->writeWarning( "ERROR: Unable to decrypt " .
                         $TWiki::cfg{SmimeKeyFile} . ": " . $pem->errstr . ".  Mail will be sent unsigned.\n" )
                      if ($this->{session});
                    return;
                }
                $key = $pem->encode( Content => $key );
            }
        }
        eval {
            $smime->setPrivateKey( $key, _slurpFile( $TWiki::cfg{SmimeCertificateFile} ) );
        }; if( $@ ) {
            $@ =~ /^(.*?)\n.*\z/s; # Any useful error information is on the first line.
             $this->{session}->writeWarning( "ERROR: Key or Certificate problem sending email: " . ($1 || $@) . ". Mail will be sent unsigned.\n" )
               if ($this->{session});
            return;
        }
	$_[0] = $smime->sign( $_[0] );
    }
}
# =======================================
sub _sendEmailBySendmail {
    my( $this, $text ) = @_;

    # send with sendmail
    my ( $header, $body ) = split( "\n\n", $text, 2 );
    $header =~ s/([\n\r])(From|To|CC|BCC)(\:\s*)([^\n\r]*)/$1.$2.$3._fixLineLength($4)/geois;
    $text = "$header\n\n$body";   # rebuild message

    $this->_smimeSignMessage( $text );

    open( MAIL, '|'.$TWiki::cfg{MailProgram} ) ||
      die "ERROR: Can't send mail using TWiki::cfg{MailProgram}";
    print MAIL $text;
    close( MAIL );
    die "ERROR: Exit code $? from TWiki::cfg{MailProgram}" if $?;
}

# =======================================
sub _sendEmailByNetSMTP {
    my( $this, $text ) = @_;

    my $from = '';
    my @to = ();

    my ( $header, $body ) = split( "\n\n", $text, 2 );
    my @headerlines = split( /\r?\n/, $header );
    $header =~ s/\nBCC\:[^\n]*//os;  #remove BCC line from header
    $header =~ s/([\n\r])(From|To|CC|BCC)(\:\s*)([^\n\r]*)/$1 . $2 . $3 . _fixLineLength( $4 )/geois;
    $text = "$header\n\n$body";   # rebuild message

    $this->_smimeSignMessage( $text );

    # extract 'From:'
    my @arr = grep( /^From: /i, @headerlines );
    if( scalar( @arr ) ) {
        $from = $arr[0];
        $from =~ s/^From:\s*//io;
        $from =~ s/.*<(.*?)>.*/$1/o; # extract "user@host" out of "Name <user@host>"
    }
    unless( $from ) {
        # SMELL: should be a TWiki::inlineAlert
        die "ERROR: Can't send mail, missing 'From:'";
    }

    # extract @to from 'To:', 'CC:', 'BCC:'
    @arr = grep( /^To: /i, @headerlines );
    my $tmp = '';
    if( scalar( @arr ) ) {
        $tmp = $arr[0];
        $tmp =~ s/^To:\s*//io;
        @arr = split( /,\s*/, $tmp );
        push( @to, @arr );
    }
    @arr = grep( /^CC: /i, @headerlines );
    if( scalar( @arr ) ) {
        $tmp = $arr[0];
        $tmp =~ s/^CC:\s*//io;
        @arr = split( /,\s*/, $tmp );
        push( @to, @arr );
    }
    @arr = grep( /^BCC: /i, @headerlines );
    if( scalar( @arr ) ) {
        $tmp = $arr[0];
        $tmp =~ s/^BCC:\s*//io;
        @arr = split( /,\s*/, $tmp );
        push( @to, @arr );
    }
    if( ! ( scalar( @to ) ) ) {
        # SMELL: should be a TWiki::inlineAlert
        die "ERROR: Can't send mail, missing recipient";
    }

    return undef unless( scalar @to );

    # Change SMTP protocol recipient format from 
    # "User Name <userid@domain>" to "userid@domain"
    # for those SMTP hosts that need it just that way.
    foreach (@to) {
        s/^.*<(.*)>$/$1/;
    }

    my $smtp = 0;
    if( $this->{HELLO_HOST} ) {
        $smtp = Net::SMTP->new( $this->{MAIL_HOST},
                                Hello => $this->{HELLO_HOST},
                                Debug => $TWiki::cfg{SMTP}{Debug} || 0 );
    } else {
        $smtp = Net::SMTP->new( $this->{MAIL_HOST},
                                Debug => $TWiki::cfg{SMTP}{Debug} || 0 );
    }
    my $status = '';
    my $mess = "ERROR: Can't send mail using Net::SMTP. ";
    die $mess."Can't connect to '$this->{MAIL_HOST}'" unless $smtp;

    if( $TWiki::cfg{SMTP}{Username} ) {
        $smtp->auth($TWiki::cfg{SMTP}{Username}, $TWiki::cfg{SMTP}{Password});
    }
    $smtp->mail( $from ) || die $mess.$smtp->message;
    $smtp->to( @to, { SkipBad => 1 } ) || die $mess.$smtp->message;
    $smtp->data( $text ) || die $mess.$smtp->message;
    $smtp->dataend() || die $mess.$smtp->message;
    $smtp->quit();
}

1;
