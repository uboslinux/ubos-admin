#!/usr/bin/perl
#
# A network configuration for the EspressoBIN.
#
# This file is part of ubos-networking-espressobin.
# (C) 2012-2017 Indie Computing Corp.
#
# ubos-networking-espressobin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-networking-espressobin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-networking-espressobin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigs::PublicEspressobin;

use JSON;
use UBOS::Logging;
use UBOS::Networking::GatewayUtils;
use UBOS::Networking::NetConfigUtils;

my $name = 'public-espressobin';

# The gateway devices.
# These are regexes.
my @defaultGatewayNicPatterns = (
    'wan.*'
);

# the parent interface devices.
my @defaultSwitchNicPatterns = (
    'eth0'
);

##
# Determine whether this network configuration could currently be activated.
# This return false, if, for example, this network configuration requires two
# ethernet interfaces, but the device has only one ethernet interface attached.
# This will also return true if this configuration is currently active.
# return: 1 or 0
sub isPossible {
    return UBOS::Networking::GatewayUtils::isPossible(
            \@defaultGatewayNicPatterns,
            \@defaultSwitchNicPatterns );
}

##
# Activate this network configuration.
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
# $force: do not read existing configuration, initialize netconfig from scratch
sub activate {
    my $initOnly = shift;
    my $force    = shift;

    return UBOS::Networking::GatewayUtils::activate(
            $name,
            $initOnly,
            $force,
            {
                'dhcp'         => JSON::true,
                'dns'          => JSON::false, # do not listen to DNS queries from upstream
                'forward'      => JSON::true,
                'masquerade'   => JSON::true,
                'ports'        => JSON::true,
                'ssh'          => JSON::true,
                'sshratelimit' => JSON::true
            },
            {
                'dns'          => JSON::true, # listen to DNS queries from the LAN
                'dhcpserver'   => JSON::true,
                'forward'      => JSON::true,
                'mdns'         => JSON::true,
                'ports'        => JSON::true,
                'ssh'          => JSON::true,
                'sshratelimit' => JSON::true
            },
            \@defaultGatewayNicPatterns,
            \@defaultSwitchNicPatterns );
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'EspressoBIN with as a home router. Apps accessible over the internet.';
}

1;
