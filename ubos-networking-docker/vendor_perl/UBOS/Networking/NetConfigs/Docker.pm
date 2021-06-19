#!/usr/bin/perl
#
# A network configuration for a Linux container run with Docker.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigs::Docker;

use JSON;
use UBOS::Host;
use UBOS::Networking::NetConfigUtils;

my $name = 'docker';

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
    return 1;
}

##
# Activate this network configuration.
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
# $force: do not read existing configuration, initialize netconfig from scratch
sub activate {
    my $initOnly = shift;
    my $force    = shift;

    # For Docker, we do absolutely nothing.
    # Docker wants to do its own IP address assignments, and does complicated
    # things with iptables that basically incomprehensible to anybody other than
    # them. So we do nothing.
    return 1;
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'Networking for a Docker container (does nothing, relies on Docker)';
}

1;

