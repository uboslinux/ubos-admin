#!/usr/bin/perl
#
# Save the Site JSONs to the Staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SaveSitesJson;

use UBOS::Host;
use UBOS::Utils;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

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

    return saveSitesJson( $staffRootDir );
}

##
# Save the Sites JSON to the Staff.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub saveSitesJson {
    my $staffRootDir = shift;

    my $sites   = UBOS::Host::sites();
    my $hostId  = UBOS::Host::hostId();
    my $infoDir = "flock/$hostId/device-info";

    my $sitesJson = {};
    foreach my $siteId ( keys %$sites ) {
        $sitesJson->{$siteId} = $sites->{$siteId}->siteJson;
    }

    unless( -d "$staffRootDir/$infoDir" ) {
        UBOS::Utils::mkdirDashP( "$staffRootDir/$infoDir" );
    }
    UBOS::Utils::writeJsonToFile( "$staffRootDir/$infoDir/sites.json", $sitesJson );

    return 0;
}

1;
