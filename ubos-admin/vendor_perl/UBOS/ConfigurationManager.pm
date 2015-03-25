#!/usr/bin/perl
#
# Manages the configuration of the host using a config drive, called the
# ubos staff.
#
# This file is part of ubos-admin.
# (C) 2012-2015 Indie Computing Corp.
#
# ubos-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.
#

#
# Comments:
# Cannot check that device is removable: some USB disks have that at 0
# We accept partitions or entire disks

use strict;
use warnings;

package UBOS::ConfigurationManager;

use File::Temp;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $LABEL = 'UBOS-STAFF';

##
# Initialize the configuration if there's a configuration device attached
sub initializeIfNeeded {
    unless( UBOS::Host::config()->get( 'ubos.readstaffonboot', 1 )) {
        debug( 'Not looking for staff, ubos.readstaffonboot is false' );
        return;
    }

    my $device = guessConfigurationDevice();
    unless( $device ) {
        debug( 'No staff device found' );
        return;
    }

    debug( 'Staff device:', $device );

    my $targetFile = File::Temp->newdir( DIR => '/var/run', UNLINK => 1 );
    my $target     = $targetFile->dirname;

    if( UBOS::Utils::myexec( "mount -t vfat '$device' '$target'" )) {
        error( 'Failed to mount:', $device, $target );
        return;
    }

    if( UBOS::Host::config()->get( 'ubos.initializestaffonboot', 1 )) {
        if( initializeConfigurationIfNeeded( $target )) {
            error( 'Initialization staff device failed:', $device, $target );
        }
    }
    
    if( loadCurrentConfiguration( $target )) {
        error( 'Loading current configuration failed from', $device, $target );
    }

    if( UBOS::Utils::myexec( "umount '$target'" )) {
        error( 'Failed to unmount:', $device, $target );
    }
    return;
}

##
# Check that a candidate device is indeed a configuration device
# $device: the candidate device, may be disk or partition
# return: the $device if partition, or the partition device on $device, or undef
sub checkConfigurationDevice {
    my $device = shift;

    unless( -b $device ) {
        $@ = 'Not a valid UBOS staff device: ' . $device;
        return undef;
    }
     
    my $out;
    my $err;
    if( UBOS::Utils::myexec( "lsblk --pairs --output NAME,TYPE,FSTYPE,LABEL '$device'", undef, \$out, \$err )) {
        fatal( 'lsblk on device failed:', $device, $out, $err );
    }
    my $ret;

    # NAME="sda" TYPE="disk" FSTYPE="" LABEL=""
    # NAME="sda1" TYPE="part" FSTYPE="ext4" LABEL=""
    # NAME="sda2" TYPE="part" FSTYPE="vfat" LABEL=""

    while( $out =~ m!NAME="([^"]+)"\s+TYPE="([^"]+)"\s+FSTYPE="([^"]+)"\s+LABEL="([^"]+)"!g ) {
        my( $name, $type, $fstype, $label ) = ( "/dev/$1", $2, $3, $4 );
        unless( $fstype eq 'vfat' ) {
            next;
        }
        unless( $label eq $LABEL ) {
            next;
        }
        if( $ret ) {
            $@ = 'More than one suitable partition found: ' . $ret . ' ' . $name;
            return undef;
        }
        $ret = "/dev/$name";
    }
    unless( $ret ) {
        $@ = 'No suitable partition found on: ' . $device;
    }

    return $ret;
}

##
# Guess the name of the configuration device
# return: device, or undef
sub guessConfigurationDevice {

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "lsblk --pairs --output NAME,TYPE,FSTYPE,LABEL", undef, \$out, \$err )) {
        fatal( 'lsblk failed:', $out, $err );
    }

    my $ret;
                
    # NAME="sda" TYPE="disk" FSTYPE="" LABEL=""
    # NAME="sda1" TYPE="part" FSTYPE="ext4" LABEL=""
    # NAME="sda2" TYPE="part" FSTYPE="vfat" LABEL=""

    while( $out =~ m!NAME="([^"]+)"\s+TYPE="([^"]+)"\s+FSTYPE="([^"]+)"\s+LABEL="([^"]+)"!g ) {
        my( $name, $type, $fstype, $label ) = ( "/dev/$1", $2, $3, $4 );
        unless( $fstype eq 'vfat' ) {
            next;
        }
        unless( $label eq $LABEL ) {
            next;
        }
        if( $ret ) {
            $@ = 'More than one suitable partition found: ' . $ret . ' ' . $name;
            return undef;
        }
        $ret = $name;
    }
    unless( $ret ) {
        $@ = 'No suitable partition found.';
    }

    return $ret;
}

##
# Save current configuration to this directory
# $target: the target directory for the save (root directory of stick)
# return: number of errors
sub saveCurrentConfiguration {
    my $target = shift;

    my $keyFingerprint = UBOS::Host::gpgHostKeyFingerprint();
    my $sshDir         = "flock/$keyFingerprint/ssh";

    unless( -d "$target/$sshDir" ) {
        UBOS::Utils::mkdirDashP( "$target/$sshDir" );
    }

    my $sshHostKey = UBOS::Utils::slurpFile( '/etc/ssh/ssh_host_key.pub' );
    UBOS::Utils::saveFile( "$target/$sshDir/ssh_host_key.pub", $sshHostKey );

    return 0;
}

##
# If this is a valid staff device, but it has not been initialized, initialize
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub initializeConfigurationIfNeeded {
    my $target = shift;

    my $errors = 0;
    unless( -e "$target/shepherd/ssh/id_rsa.pub" ) {
        my $out;
        my $err;
        if( UBOS::Utils::myexec( "ssh-keygen -N '' -f '$target/shepherd/ssh/id_rsa'", undef, \$out, \$err )) {
            error( 'SSH key generation failed:', $out, $err );
            $errors += 1;
        }
    }
    return $errors;
}

##
# Load configuration from this directory
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub loadCurrentConfiguration {
    my $target = shift;

    if( -e "$target/shepherd/ssh/id_rsa.pub" ) {
        my $sshKey = UBOS::Utils::slurpFile( "$target/shepherd/ssh/id_rsa.pub" );
        $sshKey =~ s!^\s+!!;
        $sshKey =~ s!\s+$!!;

        if( UBOS::Host::ensureOsUser( 'shepherd' )) {
            unless( -d '/home/shepherd/.ssh' ) {
                UBOS::Utils::mkdir( "/home/shepherd/.ssh", 0700, 'shepherd', 'shepherd' );
            }
            my $authorizedKeys = '';
            if( -e "/home/shepherd/.ssh/authorized_keys" ) {
                $authorizedKeys = UBOS::Utils::slurpFile( "/home/shepherd/.ssh/authorized_keys" );
            }
            if( $authorizedKeys !~ m!\Q$sshKey\E! ) {
                $authorizedKeys .= $sshKey . "\n";
            }
            UBOS::Utils::saveFile( "/home/shepherd/.ssh/authorized_keys", $authorizedKeys, 0644, 'shepherd', 'shepherd' );

            UBOS::Utils::saveFile( '/etc/sudoers.d/shepherd', <<CONTENT, '0600', 'root', 'root' );
shepherd ALL = NOPASSWD: /usr/bin/ubos-admin *, /usr/bin/systemctl *, /usr/bin/journalctl *, /usr/bin/pacman *, /usr/bin/reboot *, /usr/bin/shutdown *, /bin/bash *
CONTENT
        }
    }
    return 0;
}

1;
