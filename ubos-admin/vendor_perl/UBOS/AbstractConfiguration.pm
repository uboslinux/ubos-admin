#!/usr/bin/perl
#
# Abstract superclass for run-time configuration objects.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
#
# ubos-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::AbstractConfiguration;

use UBOS::Logging;
use UBOS::Utils;
use JSON;
use fields qw( name delegates );

my $knownFunctions = {
    'escapeSquote'     => \&UBOS::Utils::escapeSquote,
    'escapeDquote'     => \&UBOS::Utils::escapeDquote,
    'trim'             => \&UBOS::Utils::trim,
    'cr2space'         => \&UBOS::Utils::cr2space,
    'randomHex'        => \&UBOS::Utils::randomHex,
    'randomIdentifier' => \&UBOS::Utils::randomIdentifier,
    'randomPassword'   => \&UBOS::Utils::randomPassword
};

##
# Constructor.
# $name: name for this Configuration object. This helps with debugging.
# @delegates: more objects olding Configuration objects which may be used to resolve unknown variables
sub new {
    my $self            = shift;
    my $name            = shift;
    my @delegates       = @_;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{name}      = $name;
    $self->{delegates} = \@delegates;

    return $self;
}

##
# Get name of the configuration.
# return: name
sub name {
    my $self = shift;

    return $self->{name};
}

##
# Obtain a configuration value. This will not resolve symbolic references in the value.
# $name: name of the configuration value
# $default: value returned if the configuration value has not been set
# return: the value, or default value
sub get {
    my $self           = shift;
    my $name           = shift;
    my $default        = shift;
    my $remainingDepth = shift || 16;

    my $ret;
    foreach my $delegate ( @{$self->{delegates}} ) {
        $ret = $delegate->config()->get( $name, undef, $remainingDepth-1 );
        if( defined( $ret )) {
            last;
        }
    }
    unless( defined( $ret )) {
        $ret = $default;
    }

    return $ret;
}

##
# Add an additional configuration value. This will fail if the name exists already.
# $name: name of the configuration value
# $value: value of the configuration value
sub put {
    my $self  = shift;
    my $name  = shift;
    my $value = shift;

    error( 'Cannot perform put', $name, 'at this level; implement put() in', ref( $self ) );
}

##
# Obtain a configuration value, and recursively resolve symbolic references in the value.
# $name: name of the configuration value
# $default: value returned if the configuration value has not been set
# $map: location of additional name-value pairs
# $unresolvedOk: if true, and a variable cannot be replaced, leave the variable and continue; otherwise die
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
# Obtain a configuration value, and recursively resolve symbolic references in the value.
# $name: name of the configuration value
# $default: value returned if the configuration value has not been set
# $map: location of additional name-value pairs
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
# Obtain the keys in this Configuration object.
# return: the keys
sub keys {
    my $self = shift;

    error( 'Cannot perform keys at this level; subclass' );
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
# Dump this Configuration to string
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
                    "    $_ => $value\n";
                }
            } else {
                "    $_ => <undef>\n";
            }
        } sort $self->keys() ) . ")";
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

1;
