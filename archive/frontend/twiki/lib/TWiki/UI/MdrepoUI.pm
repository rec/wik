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

---+ package TWiki::UI::MdrepoUI

UI delegate for mdrepo function

=cut

package TWiki::UI::MdrepoUI;

use strict;
use Assert;

require TWiki;
require TWiki::UI;

my %cmdSwitch = (
    show => [\&doShow, 'REC_ID'],
    list => [\&doList, ''],
    add  => [\&doAdd,  'REC_ID FIELD_NAME1=VALUE1 FIELD_NAME2=VALUE2 ...'],
    updt => [\&doUpdt, 'REC_ID FIELD_NAME1=VALUE1 FIELD_NAME2=VALUE2 ...'],
    load => [\&doLoad, 'FILE_NAME'],
    del  => [\&doDel,  'REC_ID'],
    rset => [\&doRset, ''],
);

my $recIdRe = qr/^($TWiki::cfg{Mdrepo}{RecordIDRe})$/;
my $fieldNameRe = qr/$TWiki::cfg{Mdrepo}{FieldNameRe}/;

sub usageCore {
    my $cmd = shift;
    return 'mdrepo ' . substr($cmd . '   ', 0, 4) . 'TABLE ' . $cmdSwitch{$cmd}[1];
}

sub usage {
    my ($session, $cmd) = @_;
    return '' if ( !$session->inContext( 'command_line' ) );
    $cmd ||= '';
    if ( my $spec = $cmdSwitch{$cmd} ) {
	return 'Usage: ' . usageCore($cmd) . "\n";
    }
    else {
	my $retval = "Usage:\n";
	for my $i ( sort keys %cmdSwitch ) {
	    $retval .= '       ' . usageCore($i) . "\n";
	}
	return $retval;
    }
}

sub show {
    my ($recId, $rec) = @_;
    my $retval = '';
    $retval .= $recId . "\n";
    for my $i ( sort keys %$rec ) {
	$retval .= "    $i=$rec->{$i}\n";
    }
    $retval .= "\n";
    return $retval;
}

sub doShow {
    my ($session, $table, $recId) = @_;
    $recId or
	return usage($session, 'show') . "REC_ID is not specified\n";
    my $rec = $session->{mdrepo}->getRec($table, $recId) or return '';
    return show($recId, $rec);
}

sub doList {
    my ($session, $table) = @_;
    my $mdrepo = $session->{mdrepo};
    my $retval = '';
    for my $i ( sort {lc($a) cmp lc($b)} $mdrepo->getList($table) ) {
	$retval .= show($i, $mdrepo->getRec($table, $i));
    }
    return $retval;
}

sub put {
    my ($session, $table, $recId, $newRec, $addOrUpdt) = @_;
    $recId or
	return usage($session, $addOrUpdt) . "REC_ID missing\n";
    $recId =~ $recIdRe or
        return usage($session, $addOrUpdt) . "bad REC_ID\n";
    %$newRec or
	return usage($session, $addOrUpdt) . "record value missing\n";
    my $mdrepo = $session->{mdrepo};
    my $curRec = $mdrepo->getRec($table, $recId);
    if ( $addOrUpdt eq "add" ) {
	$curRec and
	    return "REC_ID $recId already exists\n";
    }
    else {
	$curRec or
	    return "REC_ID $recId does not exist\n";
    }
    $mdrepo->putRec($table, $recId, $newRec);
    return '';
}

sub doAdd {
    put(@_[0..3], "add");
}

sub doUpdt {
    put(@_[0..3], "updt");
}

sub doLoad {
    my ($session, $table, $fileName) = @_;
    my $mdrepo = $session->{mdrepo};
    my $recId = '';
    my %rec;
    my $retval = '';
    open(my $fh, '<', $fileName) or
	return "open: $fileName: $!\n";
    while ( my $line = <$fh> ) {
	chomp $line;
	$line =~ s/^\s+//;
	$line =~ s/\s+$//;
	next if ( $line =~ /^\#/ );
	if ( $line =~ /^$/ ) {
	    $mdrepo->putRec($table, $recId, \%rec) if ( $recId && %rec );
	    $recId = '';
	    %rec = ();
	    next;
	}
	if ( $line =~ $recIdRe ) {
	    $recId = $1;
	}
	elsif ( $line =~ /^($fieldNameRe)\s*=\s*(.*)/ ) {
	    $rec{$1} = $2;
	}
	else {
	    $retval .= "unexpected line format: $line\n";
	}
    }
    if ( $recId && %rec ) {
	$mdrepo->putRec($table, $recId, \%rec);
    }
    close($fh);
    return $retval;
}

sub doDel {
    my ($session, $table, $recId) = @_;
    $recId or
	return usage($session, 'del') . "REC_ID is not specified\n";
    my $mdrepo = $session->{mdrepo};
    $mdrepo->getRec($table, $recId) or
	return "REC_ID $recId does not exist\n";
    $mdrepo->delRec($table, $recId);
    return '';
}

sub doRset {
    my ($session, $table) = @_;
    $session->{mdrepo}->resetTable($table);
    return '';
}

=pod

---++ StaticMethod mdrepo( $session );

=cut

sub mdrepo {
    my( $session ) = @_;

    my $cmdName = '';
    my $table = '';
    my $recId = '';
    my %rec;
    my $cmdSpec = '';
    my $output = '';
    my $req = $session->{request};
    my $mdrepo;
    if ( !($mdrepo = $session->{mdrepo}) ) {
	$output = "Metadata repository is not in use.\n";
    }
    elsif ( $session->inContext( 'command_line' ) ) {
        # At this point, TWiki::Engine::* has determined the web and topic
        # names, which might be weird if the script is invoked from a command
        # line.
        # The following 2 lines are to replace those with something innocuous.
        $session->{webName} = $TWiki::cfg{UsersWebName};
        $session->{topicName} = $TWiki::cfg{HomeTopicName};
	my @argv = @ARGV;
	$cmdName = shift @argv || '';
	$table = shift @argv || '';
	$recId = shift @argv || '';
	for my $i ( @argv ) {
	    if ( $i =~ /^($fieldNameRe)=(.*)$/ ) {
		$rec{$1} = $2;
	    }
	}
	$cmdSpec = $cmdSwitch{$cmdName} || '';
	if ( $cmdSpec && $table ) {
            if ( $session->{mdrepo}{cont}{$table} ) {
                $output = &{$cmdSpec->[0]}($session, $table, $recId, \%rec);
            }
            else {
                $output = "table $table does not exist\n";
            }
	}
	else {
	    if ( !$cmdSpec ) {
		$output .= "$cmdName: invalid command\n" . usage($session);
	    }
	    elsif ( !$table ) {
		$output .= usage($session, $cmdName);
	    }
	}
    }
    else {
	if ( $req->param("_add") ) {
	    $cmdName = "add";
	}
	elsif ( $req->param("_updt") ) {
	    $cmdName = "updt";
	}
	elsif ( $req->param("_del") ) {
	    $cmdName = "del";
	}
	$table = $req->param('_table') || '';
	$recId = $req->param('_recid') || '';
	for my $i ( $req->param ) {
	    if ( $i =~ /^__($fieldNameRe)$/ ) {
                my $field = $1;
                my $val = $req->param($i) || '';
                $val =~ s/^\s+//;
                $val =~ s/\s+$//;
                $rec{$field} = $val if ( $val ne '' );
	    }
	}
	$cmdSpec = $cmdSwitch{$cmdName} || '';
	if ( $cmdSpec && $table ) {
	    if ( $mdrepo->{opts}{$table} =~ /b/ ) {
                if ( $session->{mdrepo}{cont}{$table} ) {
                    my $cUID = $session->{user};
                    my $result;
                    unless (
                        $session->security->checkAccessPermission('CHANGE', $cUID)
                        # super admin is allowed mdrepo operations regardless
                    ) {
                        my $mapping = $session->{users}->_getMapping($session->{user});
                        $result = 'permission denied';
                        if ( $mapping && $mapping->can('mdrepoOpAllowed') ) {
                            $result = $mapping->mdrepoOpAllowed(
                                $cUID, $cmdName, $table, $recId, \%rec);
                            # mdrepoOpAllow() returns '' if the operation is
                            # allowed. Otherwise, returns the reason of not
                            # allowing
                        }
                    }
                    if ( $result ) {
                        $output = $result;
                    }
                    else {
                        $output = &{$cmdSpec->[0]}($session, $table, $recId, \%rec);
                    }
                }
                else {
                    $output = "table $table does not exist\n";
                }
	    }
	    else {
		$output .= "table $table is not allowed to be modified from browser.\n";
	    }
	}
	else {
	    if ( !$cmdSpec ) {
		$output .= "command not specified\n";
	    }
	    elsif ( !$table ) {
		$output .= "table not specified\n";
	    }
	}
    }
    if ( my $url = $req->param('redirectto') ) {
        my $result = $output;
        chomp $result;
        $url =~ s/%RESULT%/$result/g;
	$session->redirect($url, undef);
    }
    else {
	$session->writeCompletePage( $output, 'view', 'text/plain' );
    }
}

1;
