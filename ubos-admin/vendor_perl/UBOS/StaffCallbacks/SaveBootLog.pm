#!/usr/bin/perl
#
# Save the current boot log to the Staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SaveBootLog;

use UBOS::Host;
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

    trace( 'SaveBootLog::performAtLoad', $staffRootDir, $isActualStaffDevice );

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

    trace( 'SaveBootLog::performAtSave', $staffRootDir, $isActualStaffDevice );

    if( $isActualStaffDevice ) {
        return saveBootLog( $staffRootDir );
    } else {
        return 0;
    }
}

##
# Save boot log to the Staff.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub saveBootLog {
    my $staffRootDir = shift;

    my $hostId     = UBOS::HostStatus::hostId();
    my $bootLogDir = "flock/$hostId/bootlog";

    unless( -d "$staffRootDir/$bootLogDir" ) {
        UBOS::Utils::mkdirDashP( "$staffRootDir/$bootLogDir" );
    }
    my $name;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime( UBOS::Utils::now() );
    my $now = sprintf( "%04d%02d%02d-%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec );

    UBOS::Utils::myexec( "journalctl --boot > $staffRootDir/$bootLogDir/$now.txt" );

    return 0;
}

1;
