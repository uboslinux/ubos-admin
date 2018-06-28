#!/usr/bin/perl
#
# Variables that can be looked up by to-be-installed apps etc.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Variables;

use JSON;
use MIME::Base64;
use UBOS::Logging;
use UBOS::Utils;

use fields qw( name hierarchicalMap flatMap delegates );

my $knownFunctions = {
    'base64encode'     => \&encode_base64,
    'base64decode'     => \&decode_base64,

    'escapeSquote'     => \&UBOS::Utils::escapeSquote,
    'escapeDquote'     => \&UBOS::Utils::escapeDquote,

    'trim'             => \&UBOS::Utils::trim,

    'cr2space'         => \&UBOS::Utils::cr2space,

    'randomHex'        => \&UBOS::Utils::randomHex,
    'randomIdentifier' => \&UBOS::Utils::randomIdentifier,
    'randomPassword'   => \&UBOS::Utils::randomPassword,
    'randomBytes'      => \&UBOS::Utils::randomBytes,

    'uid'              => \&UBOS::Utils::getUid,
    'gid'              => \&UBOS::Utils::getGid
};

##
# Constructor.
# $name: name for this Variables object. This helps with debugging.
# $hierarchicalMap: map of name to value (which may be another map)
# @delegates: more objects holding Configuration objects which may be used to resolve unknown variables
sub new {
    my $self            = shift;
    my $name            = shift;
    my $hierarchicalMap = shift;
    my @delegates       = @_;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{name}            = $name;
    $self->{hierarchicalMap} = $hierarchicalMap;
    $self->{flatMap}         = _flatten( $hierarchicalMap );
    $self->{delegates}       = \@delegates;

    return $self;
}

# Get name of the Variables object.
# return: name
sub name {
    my $self = shift;

    return $self->{name};
}

##
# Obtain a value for a named variable. This will not resolve symbolic references in
# the value.
# $name: name of the variable
# $default: value returned if the variable has not been set
# $remainingDepth: recursively evaluate, unless this value is 
# return: the value, or default value
sub get {
    my $self           = shift;
    my $name           = shift;
    my $default        = shift;
    my $remainingDepth = shift || 16;

    my $ret;
    my $found = $self->{flatMap}->{$name};
    if( defined( $found )) {
        $ret = $found;

    } else {
        foreach my $delegate ( @{$self->{delegates}} ) {
            $ret = $delegate->vars()->get( $name, undef, $remainingDepth-1 );
            if( defined( $ret )) {
                last;
            }
        }
        unless( defined( $ret )) {
            $ret = $default;
        }
    }
    return $ret;
}

##
# Obtain a variable value, and recursively resolve symbolic references in the value.
# $name: name of the configuration value
# $default: value returned if the variable has not been set
# $map: location of additional name-value pairs
# $remainingDepth: remaining recursion levels before abortion
# return: the value, or default value
sub getResolve {
    my $self           = shift;
    my $name           = shift;
    my $default        = shift;
    my $unresolvedOk   = shift || 0;
    my $remainingDepth = shift || 16;

    my $func = undef;
    if( $name =~ m!([^\s]+)\s*\(\s*([^\s]+)\s*\)! ) {
        $func = $1;
        $name = $2;
    }
    my $ret;
    if( $name =~ m!^[0-9]+(\.[0-9]*)?$! ) {
        # is number
        $ret = $name;
    } else {
        $ret = $self->get( $name, $default, $remainingDepth-1 );
    }
    if( defined( $ret )) {
        unless( ref( $ret )) {
            # only do this for strings
            if( $remainingDepth > 0 ) {
                $ret =~ s/(?<!\\)\$\{\s*([^\}\s]+(\s+[^\}\s]+)*)\s*\}/$self->getResolve( $1, undef, $unresolvedOk, $remainingDepth-1 )/ge;
            }
            if( defined( $func )) {
                $ret = _applyFunc( $func, $ret );
            }
        }
    } elsif( !$unresolvedOk ) {
        fatal( 'Cannot find symbol', $name, "\n" . $self->dump() );
    } else {
        $ret = '${' . $name . '}';
    }
    return $ret;
}

##
# Obtain a variable value, and recursively resolve symbolic references in the value.
# $name: name of the variable
# $default: value returned if the variable has not been set
# $unresolvedOk: if true, and a variable cannot be replaced, leave the variable and continue; otherwise die
# $remainingDepth: remaining recursion levels before abortion
# return: the value, or default value
sub getResolveOrNull {
    my $self           = shift;
    my $name           = shift;
    my $default        = shift;
    my $unresolvedOk   = shift || 0;
    my $remainingDepth = shift || 16;

    my $func = undef;
    if( $name =~ m!([^\s]+)\s*\(\s*([^\s]+)\s*\)! ) {
        $func = $1;
        $name = $2;
    }
    my $ret;
    if( $name =~ m!^[0-9]+(\.[0-9]*)?$! ) {
        # is number
        $ret = $name;
    } else {
        $ret = $self->get( $name, $default, $remainingDepth-1 );
    }
    if( defined( $ret )) {
        unless( ref( $ret )) {
            # only do this for strings
            if( $remainingDepth > 0 ) {
                $ret =~ s/(?<!\\)\$\{\s*([^\}\s]+(\s+[^\}\s]+)*)\s*\}/$self->getResolve( $1, undef, $unresolvedOk, $remainingDepth-1 )/ge;
            }
            if( defined( $func )) {
                $ret = _applyFunc( $func, $ret );
            }
        }
    } elsif( !$unresolvedOk ) {
        fatal( 'Cannot find symbol', $name, "\n" . $self->dump() );
    } else {
        $ret = undef;
    }
    return $ret;
}

##
# Add an additional configuration value. This will fail if the name exists already.
# $pairs: name-value pairs
sub put {
    my $self  = shift;
    my %pairs = @_;

    foreach my $name ( keys %pairs ) {
        my $value = $pairs{$name};
        if( !defined( $self->{flatMap}->{$name} )) {
            $self->{flatMap}->{$name} = $value;

        } elsif( $self->{flatMap}->{$name} ne $value ) {
            error( 'Have different value already for', $name, 'was:', $self->{flatMap}->{$name}, ', new:', $value );
        }
    }
}

##
# Obtain the keys in this Configuration object.
# return: the keys
sub keys {
    my $self = shift;

    my $uniq = {};
    foreach my $key ( CORE::keys %{$self->{flatMap}} ) {
        $uniq->{$key} = 1;
    }
    foreach my $delegate ( @{$self->{delegates}} ) {
        foreach my $key ( $delegate->vars()->keys() ) {
            $uniq->{$key} = 1;
        }
    }
    return CORE::keys %$uniq;
}

##
# Replace all variables in the string values in this hash with the values from this Configuration object.
# $value: the hash, array or string
# $unresolvedOk: if true, and a variable cannot be replaced, leave the variable and continue; otherwise die
# $remainingDepth: remaining recursion levels before abortion
# return: the same $value
sub replaceVariables {
    my $self           = shift;
    my $value          = shift;
    my $unresolvedOk   = shift || 0;
    my $remainingDepth = shift || 16;

    my $ret;
    if( ref( $value ) eq 'HASH' ) {
        $ret = {};
        foreach my $key2 ( CORE::keys %$value ) {
            my $value2 = $value->{$key2};

            my $newValue2 = $self->replaceVariables( $value2, $unresolvedOk, $remainingDepth-1 );
            $ret->{$key2} = $newValue2;
        }

    } elsif( ref( $value ) eq 'ARRAY' ) {
        $ret = [];
        foreach my $value2 ( @$value ) {
            my $newValue2 = $self->replaceVariables( $value2, $unresolvedOk, $remainingDepth-1 );
            push @$ret, $newValue2
        }
    } elsif( $value ) {
        $ret = $value;
        $ret =~ s/(?<!\\)\$\{\s*([^\}\s]+(\s+[^\}\s]+)*)\s*\}/$self->getResolveOrNull( $1, undef, $unresolvedOk, $remainingDepth-1 )/ge;
    } elsif( defined( $value )) {
        $ret = ''; # otherwise some files will have undef content
    } else {
        $ret = undef;
    }

    return $ret;
}

##
# Dump this Variables object to string, for debugging
# return: string
sub dump {
    my $self = shift;

    my $ret = ref( $self ) . '(' . $self->{name} . ",\n" . join( '', map
        {
            my $key   = $_;
            my $value = $self->getResolve( $_, undef, 1 );
            if( defined( $value )) {
                my $valueRef = ref( $value );

                if( $valueRef =~ m/^JSON.*[Bb]oolean$/ ) {
                    if( $value ) {
                        "    $_ => true\n";
                    } else {
                        "    $_ => false\n";
                    }
                } elsif( ref( $value )) {
                    "    $_ => " . ref( $value ) ."\n";
                } else {
                    "    $_ => '$value'\n";
                }
            } else {
                "    $_ => <undef>\n";
            }
        } sort $self->keys() ) . ")";
    return $ret;
}

##
# Recursive helper to flatten JSON into hierarchical variable names
# $map: JSON, or sub-JSON
# return: array of hierarchical variables names (may be sub-hierarchy)
sub _flatten {
    my $map = shift;
    my $ret = {};

    foreach my $key ( CORE::keys %$map ) {
        my $value = $map->{$key};

        if( ref( $value ) eq 'HASH' ) {
            my $subRet = _flatten( $value );

            foreach my $foundKey ( CORE::keys %$subRet ) {
                my $foundValue = $subRet->{$foundKey};

                $ret->{"$key.$foundKey"} = $foundValue;
            }
        } else {
            $ret->{$key} = $value;
        }
    }

    return $ret;
}

##
# Helper method to apply a named function to a value
# $funcName: the named function
# $value: the value to apply the function to
# return: the value, after having been processed by the function
sub _applyFunc {
    my $funcName = shift;
    my $value    = shift;

    my $func = $knownFunctions->{$funcName};
    my $ret;
    if( ref( $func ) eq 'CODE' ) {
        $ret = $func->( $value );

    } elsif( defined( $func )) {
        error( 'Not a function', $funcName, 'in varsubst' );
        $ret = $value;

    } else {
        error( 'Unknown function', $funcName, 'in varsubst' );
        $ret = $value;
    }
    return $ret;
}

##
# Obtain the resolved variables, recursively to delegates, as JSON.
#
# $resolveAgainst: when invoked in the recursion, pointer to the outermost vars object
# $ret: when involved in the recursion, aggregates results
# return: JSON hash
sub asJson {
    my $self           = shift;
    my $resolveAgainst = shift || $self;
    my $ret            = shift || {};

    foreach my $delegate ( @{$self->{delegates}} ) {
        $delegate->vars()->asJson( $resolveAgainst, $ret );
    }
    $self->_addToJson( $self->{hierarchicalMap}, $resolveAgainst, $ret );

    return $ret;
}

##
# Add the resolved variables to this hash.
#
# $map: the current level in the traversal
# $resolveAgainst: pointer to the outermost vars object
# $h: where to aggregate results
sub _addToJson {
    my $self           = shift;
    my $map            = shift;
    my $resolveAgainst = shift;
    my $h              = shift;

    foreach my $key ( CORE::keys %$map ) {
        my $value    = $map->{$key};
        my $valueRef = ref( $value );

        if( $valueRef && $valueRef !~ m!^JSON::PP! ) {
            unless( exists( $h->{$key} )) {
                $h->{$key} = {};
            }
            $self->_addToJson( $value, $resolveAgainst, $h->{$key} );
        } else {
            $h->{$key} = $resolveAgainst->replaceVariables( $value );
        }
    }
}

1;
