#!/usr/bin/perl
#
# A network configuration in which the network is off.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigs::Off;

use UBOS::Host;
use UBOS::Networking::NetConfigUtils;

my $name = 'off';

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

    my $allNics = UBOS::Host::nics();

    my $conf = {};
    foreach my $nic ( keys %$allNics ) {
        $conf->{$nic}->{state} = 'off';
    }
    return UBOS::Networking::NetConfigUtils::configure( $name, $conf, $initOnly );
}

##
# Return help text for this network configuration
# return: help text
sub help {
    return 'The network is off.';
}

1;
