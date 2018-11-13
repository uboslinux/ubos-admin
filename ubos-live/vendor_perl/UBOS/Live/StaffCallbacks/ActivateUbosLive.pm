#!/usr/bin/perl
#
# Staff callback to activate UBOS Live.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::StaffCallbacks::ActivateUbosLive;

use UBOS::Host;
use UBOS::Live::UbosLive;
use UBOS::Logging;
use UBOS::Utils;
use UBOS::StaffManager;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'ActivateUbosLive::performAtLoad', $staffRootDir, $isActualStaffDevice );

    return activateUbosLive( $staffRootDir );
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'ActivateUbosLive::performAtSave', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# Activate UBOS Live in this Staff callback.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub activateUbosLive {
    my $staffRootDir = shift;

    my $skipFile = $UBOS::StaffManager::SKIP_UBOS_LIVE_FILE;

    if( -e "$staffRootDir/$skipFile" ) {
        info( 'Skipping UBOS Live: user has chosen to self-administer' );
        return 0;
    }
    if( UBOS::Live::UbosLive::isUbosLiveActive()) {
        return 0;
    }

    my $hostId  = UBOS::Host::hostId();
    my $infoDir = "flock/$hostId/device-info";

    unless( -d "$staffRootDir/$infoDir" ) {
        UBOS::Utils::mkdirDashP( "$staffRootDir/$infoDir" );
    }

    my $token = UBOS::Live::UbosLive::generateRegistrationToken();
    unless( UBOS::Live::UbosLive::registerWithUbosLive( $token )) {
        my $json = {
            'token' => $token
        };

        unless( UBOS::Utils::writeJsonToFile( "$staffRootDir/$infoDir/ubos-live.json", $json )) {
            warning( 'Failed to write file:', "$staffRootDir/$infoDir/ubos-live.json" );
        }

        if( UBOS::Live::UbosLive::startUbosLive()) {
            return 0;
        } else {
            error( 'Failed to start UBOS Live:', $@ );
            return 1;
        }

    } else {
        error( $@ );
        return 1;
    }
}

1;
