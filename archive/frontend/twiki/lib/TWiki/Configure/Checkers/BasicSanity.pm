# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2000-2018 Peter Thoeny, peter[at]thoeny.org
# and TWiki Contributors. All Rights Reserved. TWiki Contributors
# are listed in the AUTHORS file in the root of this distribution.
# NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
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

package TWiki::Configure::Checkers::BasicSanity;
use base 'TWiki::Configure::Checker';

use strict;

sub new {
    my ($class, $item) = @_;
    my $this = $class->SUPER::new($item);
    $this->{LocalSiteDotCfg} = undef;
    $this->{errors} = 0;

    return $this;
}

# return true if we have fatal errors
sub insane() {
    my $this = shift;
    return $this->{errors};
}

sub ui {
    my $this = shift;
    my $result = '';
    my $badLSC = 0;

    $this->{LocalSiteDotCfg} = TWiki::findFileOnPath('LocalSite.cfg');
    unless ($this->{LocalSiteDotCfg}) {
        $this->{LocalSiteDotCfg} = TWiki::findFileOnPath('TWiki.spec') || '';
        $this->{LocalSiteDotCfg} =~ s/TWiki\.spec/LocalSite.cfg/;
    }

    # Get default settings by reading .spec files
    require TWiki::Configure::Load;
    TWiki::Configure::Load::readDefaults();

    $TWiki::defaultCfg = _copy( \%TWiki::cfg );

    if (!$this->{LocalSiteDotCfg} ) {
        $this->{errors}++;
        $result .= <<HERE;
Could not find where LocalSite.cfg is supposed to go.
Edit your LocalLib.cfg and set \$twikiLibPath to point to the 'lib' directory
for your install.
Please correct this error before continuing.
HERE
    } elsif( -e $this->{LocalSiteDotCfg} ) {
        eval {
            TWiki::Configure::Load::readConfig();
        };
        if ($@) {
            $result .= <<HERE;
Existing configuration file has a problem
that is causing a Perl error - the following message(s) was generated:
<pre>$@</pre>
You can continue, but configure will not pick up any of the existing
settings from this file unless you correct the perl error.
HERE
            $badLSC = 1;
        } elsif (!-w $this->{LocalSiteDotCfg} ) {
            $result .= <<HERE;
Cannot write to existing configuration file<br />
$this->{LocalSiteDotCfg} is not writable.
You can view the configuration, but you will not be able to save.
Check the file permissions.
HERE
        }

    } else {
        # Doesn't exist (yet)
        my $errs = $this->checkCanCreateFile(
            $this->{LocalSiteDotCfg});

        if ($errs) {
            $result .= <<HERE;
Configuration file $this->{LocalSiteDotCfg} does not exist, and I cannot
write a new configuration file due to these errors:
<pre>$errs</pre>
You will not be able to save the password or any other configure changes.
HERE
            $badLSC = 2;
        } else {
            $result .= <<HERE;
Could not find existing configuration file $this->{LocalSiteDotCfg}.
<p />
This may be because this is the first time you have run configure.
<p />
<b>If so, please specify a password below, continue to the configure screen,
fill in the required paths in the "General path settings" section, click
'Next' to save, then return to configure to complete the configuration.</b>
<p />
If you previously ran configure and saved the configuration, then please 
check for the existence of lib/LocalSite.cfg, and make sure the webserver 
user can read it.
HERE
            $badLSC = 3;
        }
    }

    # If we got this far without definitions for key variables, then
    # we need to default them. otherwise we get peppered with
    # 'uninitialised variable' alerts later.
    foreach my $var ( 'DataDir', 'DefaultUrlHost', 'PubUrlPath',
                      'PubDir', 'TemplateDir', 'ScriptUrlPath', 'LocalesDir' ) {
        # NOT SET tells the checker to try and guess the value later on
        $TWiki::cfg{$var} = 'NOT SET' unless defined $TWiki::cfg{$var};
    }

    # Make %ENV safer for CGI
    $TWiki::cfg{DETECTED}{originalPath} = $ENV{PATH} || '';
    unless( $TWiki::cfg{SafeEnvPath} ) {
        # Grab the current path
        if( defined( $ENV{PATH} )) {
            $ENV{PATH} =~ /(.*)/;
            $TWiki::cfg{SafeEnvPath} = $1;
        } else {
            # Can't guess
            $TWiki::cfg{SafeEnvPath} = '';
        }
    }
    $ENV{PATH} = $TWiki::cfg{SafeEnvPath};
    delete $ENV{IFS};
    delete $ENV{CDPATH};
    delete $ENV{ENV};
    delete $ENV{BASH_ENV};

if ($TWiki::cfg{'Password'} eq '' || !defined $TWiki::cfg{'Password'}) {
     $badLSC = 3;
     $result .=<<HERE;
 Resetting the admin Password for the TWiki
HERE

}

    return ($result, $badLSC);
}

sub _copy {
    my $n = shift;

    return undef unless defined( $n );

    if (UNIVERSAL::isa($n, 'ARRAY')) {
        my @new;
        for ( 0..$#$n ) {
            push(@new, _copy( $n->[$_] ));
        }
        return \@new;
    }
    elsif (UNIVERSAL::isa($n, 'HASH')) {
        my %new;
        for ( keys %$n ) {
            $new{$_} = _copy( $n->{$_} );
        }
        return \%new;
    }
    elsif (UNIVERSAL::isa($n, 'Regexp')) {
        return qr/$n/;
    }
    elsif (UNIVERSAL::isa($n, 'REF') || UNIVERSAL::isa($n, 'SCALAR')) {
        $n = _copy($$n);
        return \$n;
    }
    else {
        return $n;
    }
}

1;
