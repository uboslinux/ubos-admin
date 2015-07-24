#!/usr/bin/perl
#
# A network configuration for a device that obtains an IP address via
# DHCP from one interface, and manages a local network with local IP addresses
# issued by its DHCP server, with Network Address Translation, on all others.
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

package UBOS::Networking::NetConfigs::Gateway;

##
# Determine whether this network configuration could currently be activated.
# This return false, if, for example, this network configuration requires two
# ethernet interfaces, but the device has only one ethernet interface attached.
# This will also return true if this configuration is currently active.
# return: 1 or 0
sub isPossible {
    my $allNics = UBOS::Host::nics();
    
    return ( keys %$allNics ) > 1;
}

##
# Activate this network configuration.
sub activate {
    UBOS::Networking::NetConfigUtils::setNetConfig(
            'gateway',
            [ UBOS::Networking::NetConfigUtils::determineUpstreamNic() ],
            1 );
}



##
# Return help text for this network configuration
# return: help text
sub help {
    return 'Act as a home router with an upstream connection and a local network.';
}

1;