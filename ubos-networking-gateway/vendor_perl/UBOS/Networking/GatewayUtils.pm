#!/usr/bin/perl
#
# Factors out some code common to Gateway netconfigs. This is not an
# abstract superclass because netconfigs don't use inheritance, but it
# sort of acts like one.
#
# This file is part of ubos-networking.
# (C) 2012-2015 Indie Computing Corp.
#
# ubos-networking is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-networking is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-networking.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Networking::GatewayUtils;

use JSON;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;

# Candidates for gateway devices, in order, if none has been specified.
# These are regexes
my @gatewayNicPatterns = (
    'en.*',
    'eth.*',
    'wifi.*',
    'wlan.*'
);

##
# Determine whether this network configuration could currently be activated.
# This return false, if, for example, this network configuration requires two
# ethernet interfaces, but the device has only one ethernet interface attached.
# This will also return true if this configuration is currently active.
# return: 1 or 0
sub isPossible {
    my $allNics = UBOS::Host::nics();
    
    if( keys %$allNics < 2 ) { # not enough nics
        return 0;
    }
    foreach my $gatewayNicPattern ( @gatewayNicPatterns ) {
        my @gateways = grep { m!$gatewayNicPattern! } keys %$allNics;
        if( @gateways ) {
            return 1;
        }
    }
    return 0; # none of the found nics match the pattern
}

##
# Activate this network configuration.
# $name: name of the network configuration
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
# $force: do not read existing configuration, initialize netconfig from scratch
# $upstreamConfig: parameters for the upstream interface
# $lanConfig: parameters for the local network interfaces
sub activate {
    my $name           = shift;
    my $initOnly       = shift;
    my $force          = shift;
    my $upstreamConfig = shift;
    my $lanConfig      = shift;

    my $allNics = UBOS::Host::nics();

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

    # have we identified at least one gateway device?
    my $haveGateway = 0;
    foreach my $nic ( keys %$allNics ) {
        if( exists( $conf->{$nic} )) {
            if( exists( $conf->{$nic}->{masquerade} ) && $conf->{$nic}->{masquerade} ) {
                $haveGateway = 1;
                last;
            }
        }
    }
    unless( $haveGateway ) {
        my @gateways;
        foreach my $gatewayNicPattern ( @gatewayNicPatterns ) {
            @gateways = grep { m!$gatewayNicPattern! } sort UBOS::Networking::NetConfigUtils::compareNics keys %$allNics;
            if( @gateways ) {
                last;
            }
        }
        unless( @gateways ) {
            error( 'Unable to find a suitable gateway interface' );
            return 0;
        }
            
        my $gateway = shift @gateways;
        $conf->{$gateway} = $upstreamConfig; # overwrite what might have been there before
        $updated = 1;
    }
    $conf->{$gateway}->{appnic} = JSON::true;

    foreach my $nic ( keys %$allNics ) {
        unless( exists( $conf->{$nic} )) {
            my( $ip, $prefixsize ) = UBOS::Networking::NetConfigUtils::findUnusedNetwork( $conf );
            if( $ip ) {
                foreach my $key ( keys %$lanConfig ) {
                    $conf->{$nic}->{$key} = $lanConfig->{$key};
                }
                $conf->{$nic}->{address}    = $ip;
                $conf->{$nic}->{prefixsize} = $prefixsize;

                $updated = 1;
            } else {
                warning( 'Cannot find unallocated network for interface', $nic );
            }
        }
    }

    my $ret = UBOS::Networking::NetConfigUtils::configure( $name, $conf, $initOnly );

    if( $updated && !$error ) {
        UBOS::Networking::NetConfigUtils::saveNetconfigConfFileFor( $name, $conf );
    }
    return $ret;
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'Act as a home router with an upstream connection and a local network.';
}

1;
