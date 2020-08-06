#!/usr/bin/perl
#
# Save device info to the Staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SaveDeviceInfo;

use UBOS::HostStatus;
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

    my $deviceJson = UBOS::HostStatus::allAsJson();
    my $hostId     = UBOS::HostStatus::hostId();
    my $infoDir    = "flock/$hostId/device-info";

    $deviceJson->{lastupdated} = UBOS::Utils::time2string( UBOS::Utils::now() );

    unless( -d "$staffRootDir/$infoDir" ) {
        UBOS::Utils::mkdirDashP( "$staffRootDir/$infoDir" );
    }
    UBOS::Utils::writeJsonToFile( "$staffRootDir/$infoDir/device.json", $deviceJson );
}

1;
