#!/usr/bin/perl
#
# Staff callback to activate UBOS Live.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::StaffCallbacks::ActivateUbosLive;

use UBOS::Live::UbosLive;
use UBOS::Logging;
use UBOS::StaffManager;
use UBOS::Utils;

my $skipFile = $UBOS::StaffManager::SKIP_UBOS_LIVE_FILE;

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
        info( 'Deactivating UBOS Live: user has chosen to self-administer' );
        UBOS::Live::UbosLive::ubosLiveDeactivate();

    } # else: do not change activation status
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

    trace( 'ActivateUbosLive::performAtSave', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

1;
