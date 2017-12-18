#!/usr/bin/perl
#
# Manages the configuration of the host using a config drive, called the
# ubos staff.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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
# We also accept a directory called /UBOS-STAFF, to support containerization
#

use strict;
use warnings;

package UBOS::ConfigurationManager;

use File::Temp;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $LABEL = 'UBOS-STAFF';

##
# 1. Initialize the configuration if there's a configuration device attached
# 2. Deploy site templates if needed
sub initializeIfNeeded {
    trace( 'ConfigurationManager::initializeIfNeeded' );

    if( UBOS::Host::config()->get( 'host.readstaffonboot', 1 )) {
        my $device = guessConfigurationDevice();

        my $targetFile = undef; # must be out here so unlinking happens at end of function
        my $target     = undef;
        my $init       = 0;
        if( $device ) {
            trace( 'Staff device:', $device );

            my $tmpDir  = UBOS::Host()->config( 'host.tmp', '/tmp' );
            $targetFile = File::Temp->newdir( DIR => $tmpDir, UNLINK => 1 );
            $target     = $targetFile->dirname;

            if( UBOS::Utils::myexec( "mount -t vfat '$device' '$target'" )) {
                error( 'Failed to mount:', $device, $target );
                return;
            }
            $init = 1;

        } else {
            if( -d "/$LABEL" ) {
                $target = "/$LABEL";
                # don't init
            } else {
                trace( 'No staff device found' );
                return;
            }
        }

        if( $init && UBOS::Host::config()->get( 'host.initializestaffonboot', 1 )) {
            if( initializeConfigurationIfNeeded( $target )) {
                error( 'Initialization staff device failed:', $device, $target );
            }
        }

        if( loadCurrentConfiguration( $target )) {
            error( 'Loading current configuration failed from', $device, $target );
        }

        if( $device ) {
            if( UBOS::Utils::myexec( "umount '$target'" )) {
                error( 'Failed to unmount:', $device, $target );
            }
        }
    }

    return;
}

##
# Check that a candidate device is indeed a configuration device
# $device: the candidate device, may be disk or partition
# return: the $device if partition, or the partition device on $device, or undef
sub checkConfigurationDevice {
    my $device = shift;

    trace( 'ConfigurationManager::checkConfigurationDevice', $device );

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
        $ret = $name;
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

    trace( 'ConfigurationManager::guessConfigurationDevice' );

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

    trace( 'ConfigurationManager::saveCurrentConfiguration', $target );

    my $keyFingerprint = UBOS::Host::gpgHostKeyFingerprint();
    my $sshDir         = "flock/$keyFingerprint/ssh";

    unless( -d "$target/$sshDir" ) {
        UBOS::Utils::mkdirDashP( "$target/$sshDir" );
    }
#HostKey /etc/ssh/ssh_host_rsa_key
#HostKey /etc/ssh/ssh_host_dsa_key
#HostKey /etc/ssh/ssh_host_ecdsa_key
#HostKey /etc/ssh/ssh_host_ed25519_key
    foreach my $pubKeyFile ( glob "/etc/ssh/ssh_host_*.pub" ) {
        my $shortPubKeyFile = $pubKeyFile;
        $shortPubKeyFile =~ s!^(.*/)!!;

        my $pubKey = UBOS::Utils::slurpFile( $pubKeyFile );
        UBOS::Utils::saveFile( "$target/$sshDir/$shortPubKeyFile", $pubKey );
    }

    return 0;
}

##
# If this is a valid staff device, but it has not been initialized, initialize
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub initializeConfigurationIfNeeded {
    my $target = shift;

    trace( 'ConfigurationManager::initializeConfigurationIfNeeded', $target );

    my $errors = 0;
    unless( -e "$target/shepherd/ssh/id_rsa.pub" ) {
        unless( -d "$target/shepherd/ssh" ) {
            UBOS::Utils::mkdirDashP( "$target/shepherd/ssh" );
        }

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

    trace( 'ConfigurationManager::loadCurrentConfiguration', $target );

    if( -e "$target/shepherd/ssh/id_rsa.pub" ) {
        my $sshKey = UBOS::Utils::slurpFile( "$target/shepherd/ssh/id_rsa.pub" );
        $sshKey =~ s!^\s+!!;
        $sshKey =~ s!\s+$!!;

        setupUpdateShepherd( 0, $sshKey );
    }

    my $destDir = UBOS::Host::config()->get( 'host.deploysitetemplatesonbootdir', undef );
    if( -d $destDir ) {
        # site templates for all hosts into which the device is plugged
        # copy templates and leave the original in place
        if( -d "$target/shepherd/site-templates" ) {
            if( opendir( DIR, "$target/shepherd/site-templates" )) {
                while( my $entry = readdir DIR ) {
                    if( $entry ne '.' && $entry ne '..' ) {
                        UBOS::Utils::copyRecursively( "$target/shepherd/site-templates/$entry", "$destDir/" );
                    }
                }
                closedir DIR;
            }
        }

        # site templates only for a specific host
        # copy templates and remove the original
        my $keyFingerprint = UBOS::Host::gpgHostKeyFingerprint();
        my $templateDir    = "$target/flock/$keyFingerprint/site-templates";
        if( -d $templateDir ) {
            if( opendir( DIR, $templateDir )) {
                my @done = ();
                while( my $entry = readdir DIR ) {
                    if( $entry ne '.' && $entry ne '..' ) {
                        UBOS::Utils::copyRecursively( "$templateDir/$entry", "$destDir/" );
                        push @done, "$templateDir/$entry";
                    }
                }
                closedir DIR;
                UBOS::Utils::deleteFile( @done );
            }
        }
    }
    return 0;
}

##
# Create or update the shepherd user
# $add: if true, add the keys
# @keys: the public ssh keys that are allowed to log on, if any
sub setupUpdateShepherd {
    my $add  = shift;
    my @keys = @_;

    if( UBOS::Utils::ensureOsUser( 'shepherd', undef, 'UBOS shepherd user', '/var/shepherd' )) {
        my $authKeyFile = '/var/shepherd/.ssh/authorized_keys';
        unless( -d '/var/shepherd/.ssh' ) {
            UBOS::Utils::mkdir( "/var/shepherd/.ssh", 0700, 'shepherd', 'shepherd' );
        }
        my $authorizedKeys;
        if( $add && -e $authKeyFile ) {
            $authorizedKeys = UBOS::Utils::slurpFile( $authKeyFile );
        }
        if( @keys ) {
            $authorizedKeys .= join( "\n", @keys ) . "\n";
        }

        if( defined( $authorizedKeys )) {
            UBOS::Utils::saveFile( $authKeyFile, $authorizedKeys, 0644, 'shepherd', 'shepherd' );
        }

        UBOS::Utils::saveFile( '/etc/sudoers.d/shepherd', <<'CONTENT', 0600, 'root', 'root' );
shepherd ALL = NOPASSWD: \
    /usr/bin/journalctl *, \
    /usr/bin/mkdir *, \
    /usr/bin/mount *, \
    /usr/bin/pacman *, \
    /usr/bin/reboot *, \
    /usr/bin/shutdown *, \
    /usr/bin/smartctl *, \
    /usr/bin/systemctl *, \
    /usr/bin/ubos-admin *, \
    /usr/bin/ubos-install *, \
    /usr/bin/umount *, \
    /usr/bin/snapper *, \
    /usr/bin/su *, \
    /bin/bash *
CONTENT
    }
}

1;
