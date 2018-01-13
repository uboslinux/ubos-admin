#!/usr/bin/perl
#
# A network configuration for the EspressoBIN.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigs::Espressobin;

use JSON;
use UBOS::Logging;
use UBOS::Networking::GatewayUtils;
use UBOS::Networking::NetConfigUtils;

my $name = 'espressobin';

# The gateway devices.
# These are regexes.
my @defaultGatewayNicPatterns = (
    'wan.*'
);

# The parent interface device.
my @defaultSwitchNicPatterns = (
    'eth0'
);

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
                'ssh'          => JSON::true,
                'sshratelimit' => JSON::true,
                'bindcarrier'  => $defaultSwitchNicPatterns[0]
            },
            {
                'dns'          => JSON::true, # listen to DNS queries from the LAN
                'dhcpserver'   => JSON::true,
                'forward'      => JSON::true,
                'mdns'         => JSON::true,
                'ports'        => JSON::true,
                'ssh'          => JSON::true,
                'sshratelimit' => JSON::true,
                'bindcarrier'  => $defaultSwitchNicPatterns[0]
            },
            \@defaultGatewayNicPatterns,
            \@defaultSwitchNicPatterns );
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'EspressoBIN with as a home router. Apps on local network only.';
}

1;
