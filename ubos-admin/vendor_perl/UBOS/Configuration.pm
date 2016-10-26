#!/usr/bin/perl
#
# Run-time configuration.
#
# This file is part of ubos-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# ubos-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
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

package UBOS::Configuration;

use UBOS::Logging;
use UBOS::Utils;
use JSON;
use base   qw( UBOS::AbstractConfiguration );
use fields qw( hierarchicalMap flatMap );

##
# Constructor.
# $name: name for this Configuration object. This helps with debugging.
# $hierarchicalMap: map of name to value (which may be another map)
# @delegates: more Configuration objects which may be used to resolve unknown variables
sub new {
    my $self            = shift;
    my $name            = shift;
    my $hierarchicalMap = shift;
    my @delegates       = @_;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $name, @delegates );
    $self->{hierarchicalMap} = $hierarchicalMap;
    $self->{flatMap}         = _flatten( $hierarchicalMap );

    return $self;
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
    my $found = $self->{flatMap}->{$name};
    if( defined( $found )) {
        $ret = $found;
    } else {
        $ret = $self->SUPER::get( $name, $default, $remainingDepth );
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
        foreach my $key ( $delegate->keys() ) {
            $uniq->{$key} = 1;
        }
    }
    return CORE::keys %$uniq;
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


1;
