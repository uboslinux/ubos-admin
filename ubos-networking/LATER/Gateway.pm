#!/usr/bin/perl
#
# A network configuration for a gateway device. The gateway device expects
# to be connected to an upstream network that provides network services
# such as DHCP and DNS. It also provides DHCP and DNS services to its
# own local network, which is connected on a different network interface.
# The device also acts as a router with firewall and NAT.
#
# This file is part of indiebox-networking.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-networking is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-networking is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-networking.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Networking::NetConfigs::Gateway;

##
# Determine whether this network configuration is currently active.
# return: 1 or 0
sub isActive {
    my( $primaryNicName, $primaryNicValue ) = IndieBox::Networking::NetConfigUtils::getPrimaryKnownNic();

    IndieBox::Networking::NetConfigUtils::isNetConfig( [ $primaryNicName ], 1 );
}

##
# Determine whether this network configuration could currently be activated.
# This return false, if, for example, this network configuration requires two
# ethernet interfaces, but the device has only one ethernet interface attached.
# This will also return true if this configuration is currently active.
# return: 1 or 0
sub isPossible {
    my $allNics = IndieBox::Networking::NetConfigUtils::getAllNics();
    
    return ( keys %$allNics ) > 1;
}

##
# Activate this network configuration.
sub activate {
    my( $primaryNicName, $primaryNicValue ) = IndieBox::Networking::NetConfigUtils::getPrimaryKnownNic();

    IndieBox::Networking::NetConfigUtils::setNetConfig( [ $primaryNicName ], 1 );
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'Be a network gateway with local IP addresses, firewall, local DNS and DHCP.';
}

1;
