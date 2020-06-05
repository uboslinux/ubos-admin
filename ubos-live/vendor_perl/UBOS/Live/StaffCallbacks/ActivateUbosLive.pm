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
use UBOS::HostStatus;
use UBOS::Live::UbosLive;
use UBOS::Logging;
use UBOS::Utils;
use UBOS::StaffManager;

my $skipFile    = $UBOS::StaffManager::SKIP_UBOS_LIVE_FILE;
my $accountFile = $UBOS::StaffManager::UBOS_LIVE_ACCOUNT_FILE;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'ActivateUbosLive::performAtLoad', $staffRootDir, $isActualStaffDevice );

    # activate UBOS Live unless there's a skip file

    if( -e "$staffRootDir/$skipFile" ) {
        info( 'Skipping UBOS Live: user has chosen to self-administer' );
        return 0;
    }

    my $account = undef;
    my $token   = undef;
    if( -e "$staffRootDir/$accountFile" ) {
        my $accountJson = UBOS::Utils::readJsonFromFile( "$staffRootDir/$accountFile" );
        if( $accountJson ) {
            if( exists( $accountJson->{accountid} ) && exists( $accountJson->{token} )) {
                $account = $accountJson->{accountid};
                $token   = $accountJson->{token};
            } else {
                warning( 'Account JSON file on Staff does not contain accountid or token:', $accountFile );
            }
        } else {
            warning( 'Account JSON file on Staff is invalid:', $accountFile );
        }
    }

    if( !UBOS::Live::UbosLive::registerIfNeeded( $account, $token ) ) {
        warning( 'Failed to register with UBOS Live' );
        # This is not fatal -- not associated with an account, but okay
    }

    if( UBOS::Live::UbosLive::ubosLiveActivate()) {
        return 0;

    } elsif( !UBOS::Live::UbosLive::isUbosLiveActive() ) {
        error( 'Failed to activate UBOS Live:', $@ );
        return 1;

    } # else: could not activate because it was active already
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

    # Write the UBOS Live info to the Staff

    my $hostId  = UBOS::HostStatus::hostId();
    my $infoDir = "flock/$hostId/device-info";
    my $errors  = 0;

    my $conf = $UBOS::Live::UbosLive::CONF;
    if( $conf ) {
        my $confJson = UBOS::Utils::readJsonFromFile( $conf );
        if( $confJson ) {
            unless( -d "$staffRootDir/$infoDir" ) {
                UBOS::Utils::mkdirDashP( "$staffRootDir/$infoDir" );
            }

            unless( UBOS::Utils::writeJsonToFile( "$staffRootDir/$infoDir/ubos-live.json", $confJson )) {
                error( 'Failed to write file:', "$staffRootDir/$infoDir/ubos-live.json" );
                ++$errors;
            }
        } else {
            error( $@ );
            ++$errors;
        }

    } elsif( -e "$staffRootDir/$infoDir/ubos-live.json" ) {
        unless( UBOS::Utils::deleteFile( "$staffRootDir/$infoDir/ubos-live.json" )) {
            error( 'Failed to delete file:', "$staffRootDir/$infoDir/ubos-live.json" );
            ++$errors;
        }
    }
    return $errors;
}

1;
