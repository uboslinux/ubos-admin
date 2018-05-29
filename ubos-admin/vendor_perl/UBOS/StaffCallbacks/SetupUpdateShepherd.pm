#!/usr/bin/perl
#
# If the Staff has shepherd SSH keys, configure shepherd account accordingly.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SetupUpdateShepherd;

use UBOS::Host;
use UBOS::Logging;
use UBOS::StaffManager;
use UBOS::Utils;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'SetupUpdateShepherd::performAtLoad', $staffRootDir, $isActualStaffDevice );

    return loadCurrentSshConfiguration( $staffRootDir );
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'SetupUpdateShepherd::performAtSave', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# Load SSH configuration from this directory
# $staffRootDir the root directory of the Staff
# return: number of errors
sub loadCurrentSshConfiguration {
    my $staffRootDir =shift;

    if( -e "$staffRootDir/shepherd/ssh/id_rsa.pub" ) {

        trace( 'SetupUpdateShepherd::loadCurrentSshConfiguration', $staffRootDir );

        my $sshKey = UBOS::Utils::slurpFile( "$staffRootDir/shepherd/ssh/id_rsa.pub" );
        $sshKey =~ s!^\s+!!;
        $sshKey =~ s!\s+$!!;

        unless( UBOS::StaffManager::setupUpdateShepherd( $sshKey, 0, 1 )) {
            # replace during boot
            return 1;
        }
    }
    return 0;
}

1;
