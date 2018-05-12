#!/usr/bin/perl
#
# Save device info to the Staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SaveDeviceInfo;

use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'SaveDeviceInfo::performAtLoad', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'SaveDeviceInfo::performAtSave', $staffRootDir, $isActualStaffDevice );

    return saveDeviceInfo( $staffRootDir );
}

##
# Save device info to the Staff.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub saveDeviceInfo {
    my $staffRootDir = shift;

    my $hostId      = UBOS::Host::hostId();
    my $infoDir     = "flock/$hostId/device-info";
    my $deviceClass = UBOS::Host::deviceClass();
    my $nics        = UBOS::Host::nics();

    my $deviceJson = {
        'arch'        => UBOS::Utils::arch(),
        'hostid'      => $hostId,
        'hostname'    => UBOS::Host::hostname()
    };
    if( $deviceClass ) {
        $deviceJson->{deviceclass} = $deviceClass;
    }
    foreach my $nic ( keys %$nics ) {
        my @allIp = UBOS::Host::ipAddressesOnNic( $nic );
        $deviceJson->{nics}->{$nic}->{ipv4address} = [ grep { UBOS::Utils::isIpv4Address( $_ ) } @allIp ];
        $deviceJson->{nics}->{$nic}->{ipv6address} = [ grep { UBOS::Utils::isIpv6Address( $_ ) } @allIp ];
        $deviceJson->{nics}->{$nic}->{macaddress}  = UBOS::Host::macAddressOfNic( $nic );
        foreach my $entry ( qw( type operational )) { # not all entries
            $deviceJson->{nics}->{$nic}->{$entry} = $nics->{$nic}->{$entry};
        }
    }

    unless( -d "$staffRootDir/$infoDir" ) {
        UBOS::Utils::mkdirDashP( "$staffRootDir/$infoDir" );
    }
    UBOS::Utils::writeJsonToFile( "$staffRootDir/$infoDir/device.json", $deviceJson );
}

1;
