# TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2011-2016 Timothe Litt <litt at acm dot org>
# Copyright (C) 2011-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# As per the GPL, removal of this notice is prohibited.
#
# This is an original work by Timothe Litt.
#
# TWiki off-line task management framework addon
# -*- mode: CPerl; -*-

use strict;
use warnings;

=pod

---+ package TWiki::Configure::Checkers::CertificateChecker
Configure GUI checker for Certificate items.

This checker validates files that contain X.509 certificates,
such as for the S/MIME signatures and for the Tasks framework.

It must be subclassed for the various certificate types, as the requirements
are slightly different.

=cut

package TWiki::Configure::Checkers::Certificate;

use base 'TWiki::Configure::Checker';
use TWiki::Configure::Load;

use MIME::Base64;

# Private methods

# Load PEM certificate file & extract DER

sub loadCert {
    my $file = shift;

    open( my $cf, '<', $file ) or return (1, scalar $!);
    local $/;
    my $cert = <$cf>;
    close $cf;

    my @certs = ( 0 );
    $cert =~ s/\r//go;

    push @certs, decode_base64($1) while( $cert =~ /^-----BEGIN\s+(?:TRUSTED\s+)?CERTIFICATE-----$(.*?)^-----END\s+(?:TRUSTED\s+)?CERTIFICATE-----$/msog );

    return (1, "None found" ) unless( @certs > 1 );

    return @certs;
}

# Remove duplicates from a subject alternate name list & sort

sub dedup( $@ ) {
    my $hostnames = shift;

    my %x = map { $_ => 1 } @_;

    return map { $_->[0] }
                 sort {
                          my @a = @$a; shift @a;
                          my @b = @$b; shift @b;

                          while( @a && @b ) {
                              my $c = shift @a cmp shift @b;
                              return $c if( $c );
                          }
                          return @a <=> @b;
                      } map { [ $_, ($hostnames? reverse split( /\./, $_ ) : $_) ] }
                        keys %x;
}

=pod

---++ ObjectMethod checkUsage( $valueObject, $usage ) -> $errorString
Validates a Certificate item for the configure GUI
   * =$valueObject= - configure value object
   * =$usage= - Required use (email, client, server, clientserver)

Returns empty string if OK, error string with any errors

=cut

sub checkUsage {
    my $this = shift;
    my $valobj = shift;
    my $usage = shift;

    my $keys = $valobj->getKeys() or die "No keys for value";
    my $value = eval "\$TWiki::cfg$keys";
    return $this->ERROR( "Can't evaluate current value of $keys: $@" ) if( $@ );
    # The default value may not have been available when  the other defaulting is done.

    unless( defined $value ) {
	$value = eval "\$TWiki::defaultCfg->$keys";
        return $this->ERROR( "Can't evaluate default value of $keys: $@" ) if( $@ );
	$value = "***UNDEF***" unless defined $value;
    }

    # Expand any references to other variables

    TWiki::Configure::Load::expandValue($value);

    return '' unless( defined $value && length $value );

    my( $errors, @certs ) = loadCert( $value );

    return $this->ERROR( "No certificate in file: " . $certs[0] ) if( $errors );

    ((stat $value)[2] || 0) & 002 and return $this->ERROR( "File permissions allow world write" );

    eval {
        require Crypt::X509;
    }; if( $@ ) {
        return $this->WARN( "Unable to verify certificate: Please install Crypt::X509 from CPAN" );
    }

    my $x = Crypt::X509->new( cert => shift @certs );
    return $this->ERROR( "Invalid certificate: " . $x->error ) if( $x->error );

    my $sts = '';
    my $warnings = '';
    $errors = '';

    my $notes = sprintf( "\
Certificate Information:<br />
Issued by %s for %s", ($x->issuer_cn || 'Unknown issuer'), ($x->subject_cn || "Unknown subject") );
    my @ans;
    my $hostnames;
    if( $usage eq 'email' ) {
        push @ans, $x->subject_email if( $x->subject_email );
    }
    if( my $an = $x->SubjectAltName ) {
        if( $usage eq 'email' ) {
            push @ans, map { (split( /=/, $_,2 ))[1] } grep { /^(?:rfc822Name|x400Address)=(.?:.*)$/ } @$an;
        } elsif( $usage =~ /^(?:client|server|clientserver)$/ ) {
            push @ans, map { (split( /=/, $_,2 ))[1] } grep { /^(?:dNSName|iPAddress)=(?:.*)$/ } @$an;
            $hostnames = 1;
        } else {
            die "Unknown certificate usage required"; # Code issue: subclass has a new (or typo in) usage type
        }
    }
    if( @ans ) {
        $notes .= ": " . join( ', ',  dedup( $hostnames, @ans ) );
    }
    $notes .= "<br />";

    my $tm = $x->not_before;
    if( time < $tm ) {
        $errors .= " Not valid until " . gmtime( $tm ) . " UTC";
    } else {
        $notes .= " Valid from: " .gmtime( $tm ) . " UTC";
    }
    $tm = $x->not_after;
    if( time > $tm ) {
        $errors .= " Expired " . gmtime( $tm ) . " UTC";
    } else {
        $notes .= " Expires " .gmtime( $tm ) . " UTC";
    }
    $notes .= '<br />' unless( $notes =~ />$/ );

    my %ku = map { $_ => 1 } @{$x->KeyUsage} if( $x->KeyUsage );
    my %xku = map { $_ => 1 } @{$x->ExtKeyUsage} if( $x->ExtKeyUsage );
    if( $usage eq 'email' ) {
        $errors .= " Not valid for email protection"
          unless( $xku{emailProtection} &&
                  $ku{digitalSignature} );
    } elsif( $usage eq 'client' ) {
        $errors .= " Not valid for client authentication"
          unless( $xku{clientAuth} &&
                  $ku{digitalSignature} &&
                  $ku{keyEncipherment} &&
                  $ku{keyAgreement} );
    } elsif( $usage eq 'server' ) {
        $errors .= " Not valid for server authentication"
          unless( $xku{serverAuth} &&
                  $ku{digitalSignature} &&
                  $ku{keyEncipherment} &&
                  $ku{keyAgreement} );
    } elsif( $usage eq 'clientserver' ) {
        $errors .= " Not valid for client/server authentication"
          unless( $xku{clientAuth} &&
                  $xku{serverAuth} &&
                  $ku{digitalSignature} &&
                  $ku{keyEncipherment} &&
                  $ku{keyAgreement} );
    }

    $notes =~ s,<br />\z,,;

    $sts .= $this->NOTE( $notes );
    $sts .= $this->WARN( $warnings ) if( $warnings );
    $sts .= $this->ERROR( $errors ) if( $errors );
    ($notes, $warnings, $errors) = ('') x 3;

    # Handle any chained certificates in file.
    # These must be CAs, so we don't bother with alternate names
    # or other unlikely detail.  The goal is to confirm that the
    # certificates are what's expected and in the right order.

    if( @certs ) {
        $notes .= "Supplemental certificates:<br />";

        my $n = 0;
        my $mult = @certs > 1;
        while( @certs ) {
            $n++;
            $x = Crypt::X509->new( cert => shift @certs );
            return $this->ERROR( "Invalid certificate $n: " . $x->error ) if( $x->error );

            $notes .= "$n: " if( $mult );
            $notes .= sprintf( "\
Issued by %s for %s<br />", ($x->issuer_cn || 'Unknown issuer'), ($x->subject_cn || "Unknown subject") );

            $tm = $x->not_before;
            if( time < $tm ) {
                $errors .= " Not valid until " . gmtime( $tm ) . " UTC";
            } else {
                $notes .= " Valid from: " .gmtime( $tm ) . " UTC";
            }
            $tm = $x->not_after;
            if( time > $tm ) {
                $errors .= " Expired " . gmtime( $tm ) . " UTC";
            } else {
                $notes .= " Expires " .gmtime( $tm ) . " UTC";
            }
            $notes .= '<br />' unless( $notes =~ />$/ );

            my %ku = map { $_ => 1 } @{$x->KeyUsage} if ($x->KeyUsage );
            my %xku = map { $_ => 1 } @{$x->ExtKeyUsage} if( $x->ExtKeyUsage );
            $errors .= " Not valid for Certificate Authority"
              unless( $ku{critical} &&
                      $ku{keyCertSign} &&
                      $ku{cRLSign} );

            $notes =~ s,<br />\z,,;

            $sts .= $this->NOTE( $notes );
            $sts .= $this->WARN( $warnings ) if( $warnings );
            $sts .= $this->ERROR( $errors ) if( $errors );
            ($notes, $warnings, $errors) = ('') x 3;
        }
    }
    return $sts;
}

1;
