#!/usr/bin/perl
#
# A network configuration for a device that expects a network controller
# on the network that provides network services such as DHCP, DNS etc.
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

package UBOS::Networking::NetConfigs::Client;

use JSON;
use UBOS::Host;
use UBOS::Networking::NetConfigUtils;

my $name       = 'client';
my @etherGlobs = qw( en* eth* );
my @wlanGlobs  = qw( wifi* wl* );

##
# Determine whether this network configuration could currently be activated.
# This return false, if, for example, this network configuration requires two
# ethernet interfaces, but the device has only one ethernet interface attached.
# This will also return true if this configuration is currently active.
# return: 1 or 0
sub isPossible {
    my $allNics = UBOS::Host::nics();
    
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
        @allNics = sort keys %{ UBOS::Host::nics() };
    }

    my $conf    = undef;
    my $error   = 0;
    my $updated = 0;

    if( $force ) {
        $updated = 1;
    } else {
        $conf = UBOS::Networking::NetConfigUtils::readNetconfigConfFileFor( $name );
    }
    unless( $conf ) {
        $conf  = {};
        $error = 1;
    }

    foreach my $nic ( @allNics ) {
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
