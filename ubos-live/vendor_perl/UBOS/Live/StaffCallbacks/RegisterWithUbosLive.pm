#!/usr/bin/perl
#
# Register with UBOS Live.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::StaffCallbacks::RegisterWithUbosLive;

use UBOS::Host;
use UBOS::Live::UbosLive;
use UBOS::Logging;
use UBOS::Utils;

# Name of the file that needs to be on the root of the UBOS Staff to
# skip registering for UBOS Live.
my $SKIP_FILE = 'I-ADMINISTER-MY-DEVICE-MYSELF';

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'RegisterWithUbosLive::performAtLoad', $staffRootDir, $isActualStaffDevice );

    return registerWithUbosLive( $staffRootDir );
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'RegisterWithUbosLive::performAtSave', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# Register with UBOS Live.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub registerWithUbosLive {
    my $staffRootDir = shift;

    if( -e "$staffRootDir/$SKIP_FILE" ) {
        return 0;
    }
    if( UBOS::Live::UbosLive::isRegisteredWithUbosLive()) {
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
