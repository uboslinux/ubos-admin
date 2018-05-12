#!/usr/bin/perl
#
# Generate an SSH key pair and save it to the Staff.
# Do not provision a shepherd account (that's a separate operation).
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::GenerateShepherdKeyPair;

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

    trace( 'GenerateShepherdKeyPair::performAtLoad', $staffRootDir, $isActualStaffDevice );

    if( $isActualStaffDevice ) {
        return generateShepherdKeyPair( $staffRootDir );
    } else {
        # not for cloud, container
        return 0;
    }
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'GenerateShepherdKeyPair::performAtSave', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# If this is a valid staff device, but it does not have a key for the shepherd,
# and it hasn't been disabled, generate a key pair.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub generateShepherdKeyPair {
    my $staffRootDir = shift;

    unless( UBOS::Host::vars()->getResolve( 'host.initializestaffonboot', 1 )) {
        return 0; # disabled
    }

    trace( 'GenerateShepherdKeyPair::generateShepherdKeyPair', $staffRootDir );

    my $errors = 0;
    unless( -e "$staffRootDir/shepherd/ssh/id_rsa.pub" ) {
        unless( -d "$staffRootDir/shepherd/ssh" ) {
            UBOS::Utils::mkdirDashP( "$staffRootDir/shepherd/ssh" );
        }

        my $out;
        my $err;
        if( UBOS::Utils::myexec( "ssh-keygen -C 'UBOS shepherd' -N '' -f '$staffRootDir/shepherd/ssh/id_rsa'", undef, \$out, \$err )) {
            error( 'SSH key generation failed:', $out, $err );
            $errors += 1;
        }
    }
    return $errors;
}

1;
