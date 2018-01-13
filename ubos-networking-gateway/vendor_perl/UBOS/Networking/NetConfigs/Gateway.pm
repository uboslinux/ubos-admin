#!/usr/bin/perl
#
# A network configuration for a device that obtains an IP address via
# DHCP from one interface, and manages a local network with local IP addresses
# issued by its DHCP server, with Network Address Translation, on all others.
# Does not allow any inbound connections from the upstream interface.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigs::Gateway;

use JSON;
use UBOS::Logging;
use UBOS::Networking::GatewayUtils;
use UBOS::Networking::NetConfigUtils;

my $name = 'gateway';

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
    return UBOS::Networking::GatewayUtils::isPossible();
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
            } );
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'Home router with an upstream connection and a local network. Apps on local network only.';
}

1;
