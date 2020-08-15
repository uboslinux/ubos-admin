#!/usr/bin/perl
#
# Save the SSH host keys to the Staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SaveSshHostKeys;

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

    trace( 'SaveSshHostKey::performAtLoad', $staffRootDir, $isActualStaffDevice );

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

    trace( 'SaveSshHostKey::performAtSave', $staffRootDir, $isActualStaffDevice );

    return saveSshHostKeys( $staffRootDir );
}

##
# Save the SSH Host keys to the Staff
# $staffRootDir the root directory of the Staff
# return: number of errors
sub saveSshHostKeys {
    my $staffRootDir = shift;

    my $hostId = UBOS::HostStatus::hostId();
    my $sshDir = "flock/$hostId/ssh";

    unless( -d "$staffRootDir/$sshDir" ) {
        UBOS::Utils::mkdirDashP( "$staffRootDir/$sshDir" );
    }

    # Host ssh key info
    foreach my $pubKeyFile ( glob "/etc/ssh/ssh_host_*.pub" ) {
#HostKey /etc/ssh/ssh_host_rsa_key
#HostKey /etc/ssh/ssh_host_dsa_key
#HostKey /etc/ssh/ssh_host_ecdsa_key
#HostKey /etc/ssh/ssh_host_ed25519_key
        my $shortPubKeyFile = $pubKeyFile;
        $shortPubKeyFile =~ s!^(.*/)!!;

        my $pubKey = UBOS::Utils::slurpFile( $pubKeyFile );
        UBOS::Utils::saveFile( "$staffRootDir/$sshDir/$shortPubKeyFile", $pubKey );
    }
    return 0;
}

1;
