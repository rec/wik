# Module of TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2012-2018 Hideyo Imazu, hideyo.imazu[at]morganstanley.com
# Copyright (C) 2012-2018 Peter Thoeny, peter[at]thoeny.org
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

---+ package TWiki::Mdrepo

=cut

package TWiki::Mdrepo;

use strict;
use Assert;
use Fcntl;
use Storable qw(nfreeze thaw);

=pod

---++ ClassMethod new($session)

Construct a Mdrepo module.

It's a caller's responsibility to guarantee all of the followings defined:
   * $TWiki::cfg{Mdrepo}{Store} - 'DB_File' or other module name
   * $TWiki::cfg{Mdrepo}{Dir} - absolute path to the directory where files are located
   * $TWiki::cfg{Mdrepo}{Tables} - [qw(sites webs:b)]
      * Each table name can be followed by : and option letters. Currently only 'b' is valid.
      'b' is for browser, meaning the table can be updated from browser through the mdrepo script.
      By default, tables are updatable only from command line.

=cut

sub tieIt {
    my ($this, $table, $writing) = @_;
    my $openOpt = O_CREAT;
    if ( $this->{cont}{$table} ) {
	untie $this->{cont}{$table};
	delete $this->{cont}{$table};
    }
    $openOpt |= $writing ? O_RDWR : O_RDONLY;
    my $file = "$this->{dir}/$table";
    tie(my %hash, $TWiki::cfg{Mdrepo}{Store}, $file, $openOpt, 0666) or
	die "tying $file as $TWiki::cfg{Mdrepo}{Store} failed: $!\n";
    $this->{cont}{$table} = \%hash;
}

sub new {
    my ( $class, $session ) = @_;
    my $this = bless( { session => $session }, $class );

    my $store = $TWiki::cfg{Mdrepo}{Store};
    eval 'require '.$store;
    if( $@ ) {
        die "$store: compile failed $@";
    }
    $this->{dir} = $TWiki::cfg{Mdrepo}{Dir};
    $this->{cont} = {};
    my %opts;
    for my $i ( @{$TWiki::cfg{Mdrepo}{Tables}} ) {
	my ($table, $opt) = split(/:/, $i, 2);
	$opt = '' unless ( defined($opt) );
	$this->tieIt($table);
	$opts{$table} = $opt;
    }
    $this->{opts} = \%opts;

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
    undef $this->{dir};
    for my $table ( keys %{$this->{cont}} ) {
	untie $this->{cont}{$table};
	undef $this->{cont}{$table};
    }
    undef $this->{cont};
    undef $this->{session};
}

sub writeLog {
    my ($this, $msg) = @_;
    return unless $TWiki::cfg{Log}{mdrepo};
    my $session = $this->{session};
    $session->writeLog('mdrepo', "$session->{webName}.$session->{topicName}", $msg);
}

sub getList {
    my( $this, $table ) = @_;
    return () unless ( $this->{cont}{$table} );
    return map { /(.*)/; $1 } keys %{$this->{cont}{$table}};
}

sub getRec {
    my ($this, $table, $recId) = @_;
    return '' unless ( $this->{cont}{$table} );
    my $v = $this->{cont}{$table}{$recId};
    return '' unless ( defined($v) );
    my $r;
    eval { $r = thaw($v) };
    if ( $@ ) {
	$this->{session}->writeDebug(
	    "TWiki::Mdrepo::getRec(..., $table, $recId, ...): $@\n");
	return '';
    }
    else {
        # cleanse for taint check
        my %rv;
        while ( my ($k, $v) = each %$r ) {
            $v = '' if ( !defined($v) );
            $v =~ /^(.*)$/;
            $rv{$k} = $1;
        }
	return \%rv;
    }
}

sub hash2str {
    my $hash = shift;
    my $str = '';
    for my $i ( sort keys %$hash ) {
	$str .= "$i=$hash->{$i} ";
    }
    chop $str;
    return $str;
}

sub putRec {
    my ($this, $table, $recId, $rec) = @_;
    unless ( $this->{cont}{$table} ) {
	$this->{session}->writeDebug(
	    "TWiki::Mdrepo::putRec(..., $table, $recId, ...): ".
	    "no such table\n");
	return;
    }
    my $f;
    eval { $f = nfreeze($rec) };
    if ( $@ ) {
	$this->{session}->writeDebug(
	    "TWiki::Mdrepo::putRec(..., $table, $recId, ...):".
	    "invalid record content: $@\n");
    }
    else {
	my $cmd = 'add';
	if ( my $cur = $this->{cont}{$table}{$recId} ) {
	    $this->writeLog("cur $table $recId " . hash2str(thaw($cur)));
	    $cmd = 'updt';
	}
	$this->tieIt($table, 1);
	$this->{cont}{$table}{$recId} = $f;
	$this->tieIt($table);
	$this->writeLog("$cmd $table $recId " . hash2str($rec));
    }
}

sub delRec {
    my ($this, $table, $recId) = @_;
    return unless ( $this->{cont}{$table} );
    if ( my $cur = $this->{cont}{$table}{$recId} ) {
	$this->writeLog("cur $table $recId " . hash2str(thaw($cur)));
    }
    $this->tieIt($table, 1);
    delete $this->{cont}{$table}{$recId};
    $this->tieIt($table);
    $this->writeLog("del $table $recId");
}

sub resetTable {
    my ($this, $table) = @_;
    if ( my $t = $this->{cont}{$table} ) {
	for my $i ( sort keys %$t ) {
	    $this->writeLog("cur $table $i " . hash2str(thaw($t->{$i})));
	}
    }
    else {
	return;
    }
    $this->tieIt($table, 1);
    %{$this->{cont}{$table}} = ();
    $this->tieIt($table);
    $this->writeLog("reset $table");
}

1;
