# Plugin for TWiki Enterprise Collaboration Platform, http://TWiki.org/
#
# Copyright (C) 2015 Alba Power Quality Solutions
# Copyright (C) 2015 Wave Systems Corp.
# Copyright (C) 2010-2018 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2010-2018 TWiki Contributors
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 3
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# As per the GPL, removal of this notice is prohibited.
#
# =========================
#
# This is the core module of the SetGetPlugin.

package TWiki::Plugins::SetGetPlugin::Core;

use Config;
use Fcntl qw(:flock);

my $debug = $TWiki::cfg{Plugins}{SetGetPlugin}{Debug};
my $jNameRE = '[a-zA-Z0-9_\-\$]+';
my $jPathRE = '\.([a-zA-Z0-9_\-\:]+)|\[([0-9]+|\*)\]';
my $jNameAndPathRE = " *($jNameRE)((?:$jPathRE){0,}) *";
my $defaultStore = 'persistentvars';  # default store (do not change name)
my $canFlock = $Config{d_flock};      # file locking is not available on all platforms

# =========================
sub new {
    my ( $class ) = @_;

    my $this = {
          WorkArea => TWiki::Func::getWorkArea( 'SetGetPlugin' ),
        };
    bless( $this, $class );
    TWiki::Func::writeDebug( "- SetGetPlugin Core constructor" ) if $debug;

    $this->initVariables();

    return $this;
}

# =========================
# variables need to be reset on topic init
sub initVariables {
    my ( $this ) = @_;
    $this->{VolatileVars} = undef;
    $this->{Stores} = undef;
    $this->_loadStoreVars( $defaultStore );
}

# =========================
sub VarDUMP {
    my ( $this, $params ) = @_;
    my $remember = $params->{remember};
    my $store = _sanitizeName( $params->{store} );
    $store = $defaultStore if( $remember && ! $store );
    TWiki::Func::writeDebug( "- SetGetPlugin DUMP ( store=\"$store\" )" ) if $debug;

    my $value = '';
    my $hold = '';
    my $sep = '';

    if( defined $params->{format} ) {
        $format = $params->{format};
    } else {
        $format = "name: \$name, value: \$value <br />";
    }

    if( defined $params->{separator} ) {
        $sep = $params->{separator};
    } else {
        $sep = "\n";
    }
    $sep =~ s/\$n/\n/g;

    my $hRef = $store ? $this->{Stores}{$store}{Vars} : $this->{VolatileVars};
    foreach my $k ( sort keys %{$hRef} ) {
        my $v = $hRef->{$k};
        if( ref( $v ) =~ /^(ARRAY|HASH)$/ ) {
            require JSON;
            $v = JSON::encode_json( $v );
        }
        $hold = $format;
        $hold =~ s/\$name/$k/g;
        $hold =~ s/\$key/$k/g; # undocumented, for compatibility
        $hold =~ s/\$value/$v/g;
        $value .= "$hold$sep";
    }
    $value =~ s/$sep$//;

    return $value;
}

# =========================
sub VarGET {
    my ( $this, $params ) = @_;

    my $name  = _sanitizeName( $params->{_DEFAULT} );

    # test for JSON path, such as: "name.key[2][3].subkey"
    my ( $jBase, $jPath );
    if( $params->{_DEFAULT} && $params->{_DEFAULT} =~ /^$jNameAndPathRE$/ ) {
        $jBase = _sanitizeName( $1 ); # example: "name"
        $jPath = $2;                  # example: ".key[2][3].subkey"
        TWiki::Func::writeDebug( "- SetGetPlugin GET( $jBase$jPath )" ) if $debug;
    } else {
        TWiki::Func::writeDebug( "- SetGetPlugin GET( $name )" ) if $debug;
    }
    return '' unless( $name );

    # load store if needed
    my $store = _sanitizeName( $params->{store} );
    if( $store ) {
        $this->_loadStoreVars( $store );
    }

    # load variable
    my $isDefined = 0;
    my $isPersistent = 0;
    my $value = '';
    if( $jBase && $store && defined $this->{Stores}{$store}{Vars}{$jBase}
                         &&    ref( $this->{Stores}{$store}{Vars}{$jBase} ) =~ /^(ARRAY|HASH)$/ ) {
        $isDefined = 1;
        $isPersistent = 1;
        $value = $this->{Stores}{$store}{Vars}{$jBase};
        TWiki::Func::writeDebug( "  - get store JSON -> " . ref( $value ) ) if $debug;

    } elsif( $jBase && defined $this->{VolatileVars}{$jBase}
                    &&    ref( $this->{VolatileVars}{$jBase} ) =~ /^(ARRAY|HASH)$/ ) {
        $isDefined = 1;
        $value = $this->{VolatileVars}{$jBase};
        TWiki::Func::writeDebug( "  - get volatile JSON -> " . ref( $value ) ) if $debug;

    } elsif( $jBase && defined $this->{Stores}{$defaultStore}{Vars}{$jBase}
                    &&    ref( $this->{Stores}{$defaultStore}{Vars}{$jBase} ) =~ /^(ARRAY|HASH)$/ ) {
        $isDefined = 1;
        $isPersistent = 1;
        $value = $this->{Stores}{$defaultStore}{Vars}{$jBase};
        TWiki::Func::writeDebug( "  - get persistent JSON -> " . ref( $value ) ) if $debug;

    } elsif( $store && defined $this->{Stores}{$store}{Vars}{$name} ) {
        $isDefined = 1;
        $isPersistent = 1;
        $value = $this->{Stores}{$store}{Vars}{$name};
        TWiki::Func::writeDebug( "  - get store -> $value" ) if $debug;

    } elsif( defined $this->{VolatileVars}{$name} ) {
        $isDefined = 1;
        $value = $this->{VolatileVars}{$name};
        TWiki::Func::writeDebug( "  - get volatile -> $value" ) if $debug;

    } elsif( defined $this->{Stores}{$defaultStore}{Vars}{$name} ) {
        $isDefined = 1;
        $isPersistent = 1;
        $value = $this->{Stores}{$defaultStore}{Vars}{$name};
        TWiki::Func::writeDebug( "  - get persistent -> $value" ) if $debug;

    } elsif( defined $params->{default} ) {
        return $params->{default};
    }

    my $arr = undef;
    if( $jPath && ref( $value ) =~ /^(ARRAY|HASH)$/ ) {
        # drill down the structure by traversing the JSON path, such as: "name.key[2][3].subkey"
        while( $jPath =~ s/^($jPathRE)// ) {
            my $key = $2;
            my $index = $3;
            if( ref( $value ) =~ /^(ARRAY)$/ && defined $index ) {
                if( $index eq '*' && !defined $arr ) {
                    require Clone;
                    $arr = Clone::clone( $value );
                    $value = $value->[0];
                } elsif( $index ne '*' && $index < scalar @{ $value } ) {
                    $value = $value->[$index];
                    if( defined $arr ) {
                        for my $i ( 0 .. $#$arr ) {
                            my $obj = $arr->[$i]; 
                            $arr->[$i] = $obj->[$index] if( $obj );
                        }
                    }
                } else {
                    $value = 'ERROR: Invalid JSON path, syntax or range.';
                    last;
                }

            } elsif( ref( $value ) =~ /^(HASH)$/ && defined $key && $value->{$key} ) {
                $value = $value->{$key};
                if( defined $arr ) {
                    for my $i ( 0 .. $#$arr ) {
                        my $obj = $arr->[$i];
                        $arr->[$i] = $obj->{$key} if( $obj );
                    }
                }

            } else {
                $value = 'ERROR: Invalid JSON path, syntax or range.';
                last;
            }
        }
        if( $jPath ) {
            # the while loop did not consume the whole path
            $value = 'ERROR: Invalid JSON path, syntax or range.';
        }
    }

    # convert structure into JSON string
    if( defined $arr ) {
        require JSON;
        $value = JSON::encode_json( $arr );
        $arr = undef; 
   } elsif( ref( $value ) =~ /^(ARRAY|HASH)$/ ) {
        require JSON;
        $value = JSON::encode_json( $value );
    }

    if( defined $params->{format} ) {
        my $v = $value;
        $value = $params->{format};
        $value =~ s/\$name/$name/g;
        $value =~ s/\$value/$v/g;
        $value =~ s/\$isdefined/$isDefined/g;
        $value =~ s/\$isset/_isTrue( $v )/ge;
        $value =~ s/\$ispersistent/$isPersistent/g;
        $value = TWiki::Func::decodeFormatTokens( $value );
    }

    return $value;
}

# =========================
sub VarSET {
    my ( $this, $params ) = @_;
    my $name  = _sanitizeName( $params->{_DEFAULT} );
    my $store = _sanitizeName( $params->{store} ) || $defaultStore;
    my $value = $params->{value};
    my $remember = _isTrue( $params->{remember} ) || ( $store ne $defaultStore );
    my $raw = $params->{_RAW};
    if( $raw && $raw =~ s/^($jNameAndPathRE=.*) remember="([0-9a-z]*)" *$/$1/ ) {
        # found %SET{ someJSON = ... remember="1" }% syntax & cut remember="1"
        $remember = _isTrue( $6 );
    }
    if( $raw && $raw =~ s/^($jNameAndPathRE=.*) store="([0-9a-zA-Z\-\_]+)" *$/$1/ ) {
        # found %SET{ someJSON = ... store="..." }% syntax & cut store="..."
        $store = _sanitizeName( $6 );
        $remember = 1;
    }
    if( $raw && $raw =~ /^$jNameAndPathRE= *([\[\{\"])(.*?)([\]\}\"]) *$/s ) {
        # found %SET{ someJSON = ... }% syntax
        $name = _sanitizeName( $1 );
        my $jPath = $2; # example: ".key" or "[5]"
        TWiki::Func::writeDebug( "- SetGetPlugin SET( $name$jPath )" ) if $debug;

        if( $5 eq '"' && $7 eq '"' ) {
            # found %SET{ name = "some string" }% -> store just string
            $value = $6;
        } elsif( ( $5 eq '{' && $7 eq '}' ) || ( $5 eq '[' && $7 eq ']' ) ) {
            # found %SET{ name = {...} }% or %SET{ name = [...] }%  -> store object or array
            $value = "$5$6$7";
            require JSON;
            # do eval in case of die due to parse error
            eval '$value = JSON::decode_json( $value )';
            if( $@ ) {
                $value = 'ERROR: ' . $@;
                $value =~ s/ at \(?eval .*//;
                $value =~ s/\n+$//;
            }
        } else {
            return '';
        }

        if( $jPath && $value !~ /^ERROR: / ) {
            # parse the JSON path and build an array containing path with type and key.
            my @nodes = ();
            while( $jPath =~ s/^($jPathRE)// ) {
                my $key = $2;
                my $index = $3;
                if( defined $index && $index ne '*' ) {
                    push( @nodes, { idx => $index, type => 'ARRAY' } );
                } elsif( defined $key ) {
                    push( @nodes, { key => $key, type => 'HASH' } );
                }
            }
            if( $jPath || scalar @nodes < 1 ) {
                # the while loop did not consume the whole JSON path
                $value = 'ERROR: Invalid JSON path, syntax or range.';

            } else {
                my $existingValue = $remember ?
                     $this->{Stores}{$store}{Vars}{$name} : $this->{VolatileVars}{$name};
                # using the JSON path, we need to merge the value into the existing structure
                # in the proper place.
                # example existing structure named "menu":
                #   { "File": { "New": [ "new", "F" ], "Open": [ "open", "F" ] },
                #     "Edit": { "Copy": [ "cpy", "F" ], "Paste": [ "pst", "F" ] } }
                # example JSON input:
                #   menu.File.Open[1] = "T"
                # example JSON input:
                #   menu.Edit.Cut = [ "cut", "T" ]
                # resulting structure of name "menu":
                #   { "File": { "New": [ "new", "F" ], "Open": [ "open", "T" ] },
                #     "Edit": { "Copy": [ "cpy", "F" ], "Paste": [ "pst", "F" ], "Cut": [ "cut", "T" ] } }
                $value = _mergeStructure( $existingValue, \@nodes, 0, $value );
            }
        }

    } else {
        TWiki::Func::writeDebug( "- SetGetPlugin SET( $name )" ) if $debug;
    }
    return '' unless( $name && defined $value );

    if( $remember ) {
        if(    defined   $this->{Stores}{$store}{Vars}{$name}
            && ! ref( $value )
            && $value eq $this->{Stores}{$store}{Vars}{$name}
          ) {
                TWiki::Func::writeDebug( "  - eliding set persistent -> $value" ) if $debug;
        } else {
                $this->_saveStoreVar( $store, $name, $value );
        }

    } else {
        TWiki::Func::writeDebug( "  - set volatile -> $value" ) if $debug;
        $this->{VolatileVars}{$name} = $value;
    }
    return '';
}

# =========================
sub _mergeStructure {
    my( $exVal, $nodes, $i, $value ) = @_;

    my $n = $nodes->[$i++];
    if( $n->{type} ne ref $exVal ) {
        # new node type is stronger, so redefine it
        $exVal = undef;
    }
    if( $n->{type} eq 'ARRAY' ) {
        my $idx = $n->{idx};
        if( $i >= scalar @{ $nodes } ) {
            $exVal->[$idx] = $value;
        } else {
            # recursively copy structure
            $exVal->[$idx] = _mergeStructure( $exVal->[$idx], $nodes, $i, $value );
        }

    } elsif( $n->{type} eq 'HASH' ) {
        my $key = $n->{key};
        if( $i >= scalar @{ $nodes } ) {
            $exVal->{$key} = $value;
        } else {
            # recursively copy structure
            $exVal->{$key} = _mergeStructure( $exVal->{$key}, $nodes, $i, $value );
        }
    }
    return $exVal;
}

# =========================
sub _isTrue {
    my( $value ) = @_;
    return 0 unless( defined( $value ) );
    $value =~ s/^\s*(.*?)\s*$/$1/gi;
    $value =~ s/off//gi;
    $value =~ s/no//gi;
    $value =~ s/false//gi;
    return ( $value ) ? 1 : 0;
}

# =========================
sub _loadStoreVars {
    my ( $this, $store, $dontLock ) = @_;

    # check if store is newer, load persistent vars if needed
    my $storeFile = $this->{WorkArea} . "/$store.dat";
    my $lockFile  = $this->{WorkArea} . "/$store.lock";
    my $lockHandle = undef;
    my $fileTimeStamp = ( stat( $storeFile ) )[9];
    my $storeTimeStamp = $this->{Stores}{$store}{TimeStamp} || 0;
    if( defined $fileTimeStamp && $fileTimeStamp != $storeTimeStamp ) {
        if( $canFlock && ! $dontLock ) {
            open( $lockHandle, ">$lockFile") || die "Cannot create lock $lockFile - $!\n";
            flock( $lockHandle, LOCK_SH );  # wait for shared rights
        }
        $this->{Stores}{$store}{TimeStamp} = $fileTimeStamp;
        my $text = TWiki::Func::readFile( $storeFile );
        $text =~ /^(.*)$/gs; # untaint, it's safe
        $text = $1;
        $this->{Stores}{$store}{Vars} = eval $text;
        if( $canFlock && ! $dontLock ) {
            flock( $lockHandle, LOCK_UN );
            close( $lockHandle );
        }
    }
}

# =========================
sub _saveStoreVar {
    my ( $this, $store, $name, $value ) = @_;

    my $storeFile  = $this->{WorkArea} . "/$store.dat";
    my $lockFile   = $this->{WorkArea} . "/$store.lock";
    my $lockHandle = undef;
    if( $canFlock ) {
        open( $lockHandle, ">$lockFile") || die "Cannot create lock $lockFile - $!\n";
        flock( $lockHandle, LOCK_EX );  # wait for exclusive rights
    }
    $this->_loadStoreVars( $store, 1 );            # re-load latest from disk in case updated
    $this->{Stores}{$store}{Vars}{$name} = $value; # set variable
    use Data::Dumper;
    my $d = Data::Dumper->new([$this->{Stores}{$store}{Vars}], [qw(PersistentVars)]);
    $d->Indent(1);
    TWiki::Func::saveFile( $storeFile, $d->Dump() ) ;
    if( $canFlock ) {
        flock( $lockHandle, LOCK_UN );
        close( $lockHandle );
    }
    $this->{Stores}{$store}{TimeStamp} = ( stat( $storeFile ) )[9];
}

# =========================
sub _sanitizeName {
    my ( $name ) = @_;
    $name = '' unless( defined $name );
    $name =~ s/[^a-zA-Z0-9\-]/_/go;
    $name =~ s/_+/_/go;
    return $name;
}

# =========================
1;
