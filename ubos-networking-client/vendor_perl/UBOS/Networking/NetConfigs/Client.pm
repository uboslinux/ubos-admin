#!/usr/bin/perl
#
# A network configuration for a device that expects a network controller
# on the network that provides network services such as DHCP, DNS etc.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigs::Client;

use JSON;
use UBOS::HostStatus;
use UBOS::Networking::NetConfigUtils;

my $name       = 'client';
my @etherGlobs = qw( en* eth* );
my @wlanGlobs  = qw( wifi* wl* );

##
# Obtain this network configuration's name.
# return: the name
sub name {
    return $name;
}

##
# Determine whether this network configuration could currently be activated.
# This return false, if, for example, this network configuration requires two
# ethernet interfaces, but the device has only one ethernet interface attached.
# This will also return true if this configuration is currently active.
# return: 1 or 0
sub isPossible {
    my $allNics = UBOS::HostStatus::nics();

    return ( keys %$allNics ) > 0;
}

##
# Activate this network configuration.
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
# $force: do not read existing configuration, initialize netconfig from scratch
sub activate {
    my $initOnly = shift;
    my $force    = shift;

    my @allNics;
    if( $initOnly ) {
        @allNics = ( @etherGlobs, @wlanGlobs );
    } else {
        @allNics = sort keys %{ UBOS::HostStatus::hardwareNics() };
        # We don't use this Netconfig in containers, so this should be fine
        # If we also do softwareNics, than a UBOS device that runs Docker containers will
        # have all the software NIC info stored for each running Docker container, even
        # if it was only temporary
    }

    my $conf    = undef;
    my $error   = 0;
    my $updated = 0;

    if( $force ) {
        $conf    = {};
        $updated = 1;
    } else {
        $conf = UBOS::Networking::NetConfigUtils::readNetconfigConfFileFor( $name );
    }
    unless( $conf ) {
        $conf  = {};
        $error = 1;
    }

    my $appNic = undef;
    foreach my $nic ( @allNics ) {
        if( exists( $conf->{$nic} ) && exists( $conf->{$nic}->{appnic} ) && $conf->{$nic}->{appnic} ) {
            $appNic = $nic;
            last;
        }
    }
    unless( $appNic ) {
        foreach my $nic ( @allNics ) {
            if(    exists( $conf->{$nic} )
                && exists( $conf->{$nic}->{address} )
                && ( !exists( $conf->{$nic}->{appnic} ) || !$conf->{$nic}->{appnic} ))
            {
                $appNic = $nic;
                last;
            }
        }
    }
    foreach my $nic ( @allNics ) {
        if( !$appNic && ( !exists( $conf->{$nic}->{appnic} ) || !$conf->{$nic}->{appnic} )) {
            $appNic = $nic;
        }
        unless( exists( $conf->{$nic} )) {
            $conf->{$nic} = {};
        }
        unless( exists( $conf->{$nic}->{dhcp} )) {
            $conf->{$nic}->{dhcp} = JSON::true;
            $updated = 1;
        }
        unless( exists( $conf->{$nic}->{mdns} )) {
            $conf->{$nic}->{mdns} = JSON::true;
            $updated = 1;
        }
        unless( exists( $conf->{$nic}->{ports} )) {
            $conf->{$nic}->{ports} = JSON::true;
            $updated = 1;
        }
        unless( exists( $conf->{$nic}->{ssh} )) {
            $conf->{$nic}->{ssh} = JSON::true;
            $updated = 1;
        }
        if( $conf->{$nic}->{ssh} ) {
            unless( exists( $conf->{$nic}->{sshratelimit} )) {
                $conf->{$nic}->{sshratelimit} = JSON::true;
                $updated = 1;
            }
        }
    }
    if( $appNic ) {
        $conf->{$appNic}->{appnic} = JSON::true;
    }

    my $ret = UBOS::Networking::NetConfigUtils::configure( $name, $conf, $initOnly );

    if( $updated && !$error && !$initOnly ) {
        # if we don't save at initOnly time, we don't have to worry about wildcards
        UBOS::Networking::NetConfigUtils::saveNetconfigConfFileFor( $name, $conf );
    }
    return $ret;
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'Connect to a home network as DHCP and DNS client.';
}

1;
