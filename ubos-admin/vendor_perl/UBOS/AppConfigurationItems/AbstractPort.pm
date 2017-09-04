#!/usr/bin/perl
#
# An abstract AppConfiguration item that is a port
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

package UBOS::AppConfigurationItems::AbstractPort;

use base   qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields qw( portType );

use UBOS::Host;
use UBOS::Logging;
use UBOS::ResourceManager;
use UBOS::Utils qw( saveFile slurpFile );

##
# Constructor
# $json: the JSON fragment from the manifest JSON
# $role: the Role to which this item belongs to
# $appConfig: the AppConfiguration object that this item belongs to
# $installable: the Installable to which this item belongs to
# return: the created File object
sub new {
    my $self        = shift;
    my $json        = shift;
    my $role        = shift;
    my $appConfig   = shift;
    my $installable = shift;
    my $portType    = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $json, $role, $appConfig, $installable );

    $self->{portType} = $portType;

    return $self;
}

##
# Install this item, or check that it is installable.
# $doIt: if 1, install; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $config: the Configuration object that knows about symbolic names and variables
# return: success or fail
sub deployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $name   = $self->{json}->{name};
    my $scope  = $self->{json}->{scope};

    trace( 'AbstractPort::deployOrCheck', $self->{portType}, $name, $scope );

    my $port = UBOS::ResourceManager::findProvisionedPortFor(
            $self->{portType},
            $self->{appConfig}->appConfigId,
            $self->{installable}->packageName,
            $name );

    unless( $port ) {
        if( $doIt ) {
            $port = UBOS::ResourceManager::provisionPort(
                    $self->{portType},
                    $self->{appConfig}->appConfigId,
                    $self->{installable}->packageName,
                    $name );
        } else {
            # put it some placeholder values, so the variables resolve
            $port = 9999;
        }
    }
    # now insert those values into the config object
    if( 'tcp' eq $self->{portType} ) {
        $config->put( "appconfig.tcpport.$name", $port );
    } elsif( 'udp' eq $self->{portType} ) {
        $config->put( "appconfig.udpport.$name", $port );
    } else {
        error( 'Unknown port type:', $self->{portType} );
    }

    return $port ? 1 : 0;
}

##
# Uninstall this item, or check that it is uninstallable.
# $doIt: if 1, uninstall; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $config: the Configuration object that knows about symbolic names and variables
# return: success or fail
sub undeployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $name   = $self->{json}->{name};
    my $scope  = $self->{json}->{scope};

    trace( 'AbstractPort::undeployOrCheck', $self->{portType}, $name, $scope );

    if( $doIt ) {
        return UBOS::ResourceManager::unprovisionPort(
                $self->{portType},
                $self->{appConfig}->appConfigId,
                $self->{installable}->packageName,
                $name );
    }
    return 1;
}

1;
