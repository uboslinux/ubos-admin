#!/usr/bin/perl
#
# Run-time configuration.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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

package UBOS::Subconfiguration;

use UBOS::Logging;
use UBOS::Utils;
use JSON;
use base   qw( UBOS::AbstractConfiguration );
use fields qw( parent );

##
# Constructor.
# $name: name for this Configuration object. This helps with debugging.
# $parent: parent holding Configuration object to which puts are written
# @delegates: objects holding Configuration objects which may be used to resolve unknown variables
sub new {
    my $self      = shift;
    my $name      = shift;
    my $parent    = shift;
    my @delegates = @_;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $name, $parent, @delegates ); # $parent is the first delegate
    $self->{parent} = $parent;

    return $self;
}

##
# Add an additional configuration value. This will fail if the name exists already.
# $name: name of the configuration value
# $value: value of the configuration value
sub put {
    my $self  = shift;
    my $name  = shift;
    my $value = shift;

    return $self->{parent}->config()->put( $name, $value );
}

##
# Obtain the keys in this Configuration object.
# return: the keys
sub keys {
    my $self = shift;

    my $uniq = {};
    foreach my $delegate ( @{$self->{delegates}} ) {
        foreach my $key ( $delegate->config()->keys() ) {
            $uniq->{$key} = 1;
        }
    }
    return CORE::keys %$uniq;
}

1;
