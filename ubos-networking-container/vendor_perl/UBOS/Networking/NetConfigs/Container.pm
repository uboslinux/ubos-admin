#!/usr/bin/perl
#
# A network configuration for a Linux container run with systemd-nspawn.
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

package UBOS::Networking::NetConfigs::Container;

use JSON;
use UBOS::Host;
use UBOS::Networking::NetConfigUtils;

my $name = 'container';

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
    unless( exists( $conf->{host0} )) {
        $conf->{host0} = {};
    }
    unless( exists( $conf->{host0}->{dhcp} )) {
        $conf->{host0}->{dhcp} = JSON::true;
        $updated = 1;
    }
    unless( exists( $conf->{host0}->{ports} )) {
        $conf->{host0}->{ports} = JSON::true;
        $updated = 1;
    }
    unless( exists( $conf->{host0}->{ssh} )) {
        $conf->{host0}->{ssh} = JSON::true;
        $conf->{host0}->{sshratelimit} = JSON::false; # not in a container
        $updated = 1;
    }
    unless( exists( $conf->{host0}->{appnic} )) {
        $conf->{host0}->{appnic} = JSON::true;
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
    return 'Networking for a systemd-nspawn container.';
}

1;
