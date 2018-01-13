#!/usr/bin/perl
#
# An abstract AppConfiguration item that is a port
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub deployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

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
    # now insert those values into the vars object
    if( 'tcp' eq $self->{portType} ) {
        $vars->put( "appconfig.tcpport.$name", $port );
    } elsif( 'udp' eq $self->{portType} ) {
        $vars->put( "appconfig.udpport.$name", $port );
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
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub undeployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

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
