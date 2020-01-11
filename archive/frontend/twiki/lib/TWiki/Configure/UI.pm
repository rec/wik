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
#
# This is both the factory for UIs and the base class of UI constructors.
# A UI is the V part of the MVC model used in configure.
#
# Each structural entity in a configure screen has a UI type, either
# stored directly in the entity or indirectly in the type associated
# with a value. The UI type is used to guide a visitor which is run
# over the structure to generate the UI.

package TWiki::Configure::UI;

use strict;
use Carp;
use File::Spec;
use FindBin;

use vars qw ($totwarnings $toterrors);

sub new {
    my ($class, $item) = @_;

    Carp::confess unless $item;

    my $this = bless( { item => $item }, $class);
    $this->{item} = $item;

    $FindBin::Bin =~ /(.*)/;
    $this->{bin} = $1;
    my @root = File::Spec->splitdir($this->{bin});
    pop(@root);
    $this->{root} = File::Spec->catfile(@root, '');

    return $this;
}

sub findRepositories {
    my $this = shift;
    unless (defined($this->{repositories})) {
        my $replist = '';
        $replist .= $TWiki::cfg{ExtensionsRepositories}
          if defined $TWiki::cfg{ExtensionsRepositories};
        $replist .= "$ENV{TWIKI_REPOSITORIES};" # DEPRECATED
          if defined $ENV{TWIKI_REPOSITORIES};  # DEPRECATED
        $replist = ";$replist;";
        while ($replist =~ s/[;\s]+(.*?)=\((.*?),(.*?)(?:,(.*?),(.*?))?\)\s*;/;/) {
            push(@{$this->{repositories}},
                 { name => $1, data => $2, pub => $3});
        }
    }
}

sub getRepository {
    my ($this, $reponame) = @_;
    foreach my $place (@{$this->{repositories}}) {
        return $place if $place->{name} eq $reponame;
    }
    return undef;
}

# Static UI factory
# UIs *must* exist
sub loadUI {
    my ($id, $item) = @_;
    $id = 'TWiki::Configure::UIs::'.$id;
    my $ui;

    eval "use $id; \$ui = new $id(\$item);";

    return undef if (!$ui && $@);

    return $ui;
}

# Static checker factory
# Checkers *need not* exist
sub loadChecker {
    my ($keys, $item) = @_;
    my $id = $keys;
    $id =~ s/}\{/::/g;
    $id =~ s/[}{]//g;
    $id =~ s/'//g;
    $id =~ s/-/_/g;
    my $checkClass = 'TWiki::Configure::Checkers::'.$id;
    my $checker;

    eval "use $checkClass; \$checker = new $checkClass(\$item);";
    # Can't locate errors are OK
    if ($@) {
	die $@ unless ($@ =~ /Can't locate /);
	# See if type can generate a generic checker
	if ($item->can('getType' )) {
	    my $type = $item->getType();
	    if ($type && $type->can('makeChecker')) {
		$checker = $type->makeChecker($item, $keys);
	    }
	}
    }
    return $checker;
}

# Returns a response object as described in TWiki::Net
sub getUrl {
    my ($this, $url) = @_;

    require TWiki::Net;
    my $tn = new TWiki::Net();
    my $response = $tn->getExternalResource($url);
    $tn->finish();
    return $response;
}

# STATIC Used by a whole bunch of things that just need to show a key-value row
# (called as a method, i.e. with class as first parameter)
sub setting {
    my $this = shift;
    my $key = shift;
    return CGI::Tr(CGI::td({class=>'firstCol'}, $key).
                   CGI::td({class=>'secondCol'}, join(' ', @_)))."\n";
}

# Generate a foldable block (twisty). This is a DIV with a table in it
# that contains the settings and doc rows.
sub foldableBlock {
    my( $this, $head, $attr, $body ) = @_;
    my $headText = $head . CGI::span({ class => 'blockLinkAttribute' }, $attr);
    $body = CGI::start_table({width => '100%', -border => 0, -cellspacing => 0, -cellpadding => 0}).$body.CGI::end_table();
    my $mess = $this->collectMessages($this->{item});

    my $anchor = $this->_makeAnchor( $head );
    my $id = $anchor;
    my $blockId = $id;
    my $linkId = 'blockLink'.$id;
    my $linkAnchor = $anchor.'link';
    return CGI::a({ name => $linkAnchor }).
      CGI::a({id => $linkId,
              class => 'blockLink blockLinkOff',
              href => '#'.$linkAnchor,
              rel => 'nofollow',
              onclick => 'foldBlock("' . $id . '"); return false;'
             },
             $headText.$mess).
               CGI::div( {id => $blockId,
                          class=> 'foldableBlock foldableBlockClosed'
                         }, $body ).
                           "\n";
}

# encode a string to make an HTML anchor
sub _makeAnchor {
    my ($this, $str) = @_;

    $str =~ s/\s(\w)/uc($1)/ge;
    $str =~ s/\W//g;
    return $str;
}

sub NOTE {
    my $this = shift;
    return CGI::p({class=>"info"}, join("\n",@_));
}

# a warning
sub WARN {
    my $this = shift;
    $this->{item}->inc('warnings');
    $totwarnings++;
    return CGI::div(CGI::span({class=>'warn'},
                              CGI::strong('Warning: ').join("\n",@_)));
}

# an error
sub ERROR {
    my $this = shift;
    $this->{item}->inc('errors');
    $toterrors++;
    return CGI::div(CGI::span({class=>'error'},
                              CGI::strong('Error: ').join("\n",@_)));
}

# Used in place of CGI::hidden, which is broken in some versions.
# Assumes $name does not need to be encoded
# HTML encodes the value
sub hidden {
    my ($this, $name, $value) = @_;
    $value ||= '';
    $value =~ s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&'*<=>@[_\|])/'&#'.ord($1).';'/ge;
	return '<input type="hidden" name="'.$name.'" value="'.$value.'" />';
}

# Invoked to confirm authorisation, and handle password changes. The password
# is changed in $TWiki::cfg, a change which is then detected and written when
# the configuration file is actually saved.
sub authorised {
    my $pass = $TWiki::query->param('cfgAccess');
    my $newPass = $TWiki::query->param('newCfgP');

    # The first time we get here is after the "next" button is hit. A password
    # won't have been defined yet; so the authorisation must fail to force
    # a prompt.
    if (defined ($newPass)) {
          $pass = $newPass;
    }    

    if (!defined($pass)) {
        return 0;
    }

    # If we get this far, a password has been given. Check it.
    if (!$TWiki::cfg{Password} && !$TWiki::query->param('confCfgP')) {
        # No password passed in, and TWiki::cfg doesn't contain a password
        print CGI::div({class=>'error'}, <<'HERE');
WARNING: You have not defined a password. You must define a password before
you can enter the configuration screen.
HERE
        return 0;
    }

    # If a password has been defined, check that it has been used
    if ($TWiki::cfg{Password} &&
        crypt($pass, $TWiki::cfg{Password}) ne $TWiki::cfg{Password}) {
        print CGI::div({class=>'error'}, "Password incorrect");
        return 0;
    }

    # Password is correct, or no password defined
    # Change the password if so requested

    if ($newPass) {
        my $confPass = $TWiki::query->param('confCfgP') || '';
        if ($newPass ne $confPass) {
            print CGI::div({class=>'error'},
              'New password and confirmation do not match');
            return 0;
        }
        $TWiki::cfg{Password} = _encode($newPass);
        print CGI::div({class=>'error'}, 'Password changed');
    }

    return 1;
}


sub collectMessages {
    my $this = shift;
    my ($item)  =  @_;

    my $warnings      =  $item->{warnings} || 0;
    my $errors        =  $item->{errors} || 0;
    my $errorsMess    =  "$errors error"     .  (($errors   > 1) ? 's' : '');
    my $warningsMess  =  "$warnings warning" .  (($warnings > 1) ? 's' : '');
    my $mess          =  '';
    $mess .= ' ' . CGI::span({class=>'error'}, $errorsMess) if $errors;
    $mess .= ' ' . CGI::span({class=>'warn'}, $warningsMess) if $warnings;

    return $mess;
}

sub _encode {
    my $pass = shift;
    my @saltchars = ( 'a'..'z', 'A'..'Z', '0'..'9', '.', '/' );
    my $salt = $saltchars[int(rand($#saltchars+1))] .
      $saltchars[int(rand($#saltchars+1)) ];
    return crypt($pass, $salt);
}

1;
