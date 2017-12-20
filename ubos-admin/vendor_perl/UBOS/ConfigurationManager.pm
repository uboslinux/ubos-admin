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
# Invoked during boot.
# 1. Initialize the configuration if there's a configuration device attached
# 2. Deploy site templates if needed
sub performBootActions {
    trace( 'ConfigurationManager::initializeIfNeeded' );

    if( UBOS::Host::config()->get( 'host.readstaffonboot', 1 )) {
        my $device = guessConfigurationDevice();

        my $target     = undef;
        my $init       = 0;
        if( $device ) {
            trace( 'Staff device:', $device );

            if( mountDevice( $device, \$target )) {
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
            if( _generateShepherdKeyPair( $target )) {
                error( 'Generation of shepherd key pair on staff device failed:', $device, $target );
            }
        }

        if( loadCurrentConfiguration( $target )) {
            error( 'Loading current configuration failed from', $device, $target );
        }

        if( $device ) {
            if( unmountDevice( $device, $target )) {
                error( 'Failed to unmount:', $device, $target );
            }
        }
    }

    return;
}

##
# Check that a candidate device is indeed a configuration device
# $device: the candidate device, may be disk or partition
# $ignoreLabel: if 1, do not check for UBOS-STAFF label
# return: the $device if partition, or the partition device on $device, or undef
sub checkConfigurationDevice {
    my $device      = shift;
    my $ignoreLabel = shift;

    trace( 'ConfigurationManager::checkConfigurationDevice', $device, $ignoreLabel );

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
        if( !$ignoreLabel && $label ne $LABEL ) {
            next;
        }
        if( $ret ) {
            $@ = 'More than one partition suitable as UBOS staff found: ' . $ret . ' ' . $name;
            return undef;
        }
        $ret = $name;
    }
    unless( $ret ) {
        $@ = 'No partition suitable as UBOS staff found on: ' . $device;
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
# Completely erase all files in a directory and initialize with the staff structure
# $dir: the directory
# $keys: array of public ssh keys for the shepherd
# $wifis: hash of WiFi network client information
# return: number of errors
sub initDirectoryAsStaff {
    my $dir   = shift;
    my $keys  = shift;
    my $wifis = shift;

    my $errors = 0;

    # Delete existing content first
    unless( opendir( DIR, $dir )) {
        ++$errors;
        error( $! );
    }

    my @toDelete;
    while( my $file = readdir( DIR )) {
        if( $file ne '.' && $file ne '..' ) {
            push @toDelete, "$dir/$file";
        }
    }
    closedir( DIR );

    UBOS::Utils::deleteRecursively( @toDelete );

    # Now put new files in
    UBOS::Utils::mkdirDashP( "$dir/shepherd/ssh" );
    UBOS::Utils::saveFile( "$dir/shepherd/ssh/README", <<CONTENT );
This directory holds the public ssh key of the shepherd account. The file
must be named "id_rsa.pub" (no quotes). It may also hold the corresponding
private key, named "id_rsa" (no quotes).

For details, go to https://ubos.net/staff

CONTENT

    if( @$keys ) {
        # no need to care about permissions, this is DOS
        UBOS::Utils::saveFile( "$dir/shepherd/ssh/id_rsa.pub", join( "\n", @$keys ));
    }

    UBOS::Utils::mkdirDashP( "$dir/wifi" );
    foreach my $ssid ( keys %$wifis ) {
        my $values  = $wifis->{$ssid};
        my $content = join( '', map { $_ . '="' . _escape( $values-{$_} ) . '"' . "\n" } %$values );
        UBOS::Utils::saveFile( "$dir/wifi/$ssid.conf", $content );
    }
    UBOS::Utils::saveFile( "$dir/wifi/README", <<CONTENT );
This directory can hold information about one or more WiFi networks.
Each WiFi network must be described in a separate file and must be named
<ssid>.conf if <ssid> is the SSID of the network.

For details, go to https://ubos.net/staff

CONTENT

    return $errors;
}

##
# Label a device as being a staff device
# $device: the device
# return: number of errors
sub labelDeviceAsStaff {
    my $device = shift;

    my $out;
    my $errors = 0;

    if( UBOS::Utils::myexec( "dosfslabel '$device'", undef, \$out )) {
        error( 'Cannot read DOS filesystem label from device:', $device );
        ++$errors;
    }
    unless( $out =~ m!$LABEL! ) {
        # There might be a lot more output than just the label, such as
        # error messages. Unfortunately they are printed to stdout with
        # no clear distinction between label and message

        if( UBOS::Utils::myexec( "dosfslabel '$device' $LABEL" )) {
            error( 'Cannot change DOS filesystem label of device:', $device );
        }
    }

    return $errors;
}

##
# If this is a valid staff device, but it does not have a key for the shepherd,
# generate a key pair.
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub _generateShepherdKeyPair {
    my $target = shift;

    trace( 'ConfigurationManager::_generateShepherdKeyPair', $target );

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

    if( -d "$target/wifi" ) {
        my $out;
        if( UBOS::Utils::myexec( "pacman -Qi wpa_supplicant", undef, \$out, \$out )) {
            error( 'Cannot provision WiFi from staff device: package wpa_supplicant is not installed' );

        } else {
            my $confs    = UBOS::Utils::readFilesInDirectory( $target, '*.conf' );
            my $wlanNics = UBOS::Host::wlanNics();

            if(( keys %$confs ) && ( keys %$wlanNics )) {
                unless( -d "$target/etc/wpa_supplicant" ) {
                    UBOS::Utils::mkdir( "$target/etc/wpa_supplicant" );
                }
                my $content = <<CONTENT;
eapol_version=1
ap_scan=1
fast_reauth=1

CONTENT
                $content .= join( "\n", map { "network={\n" . $_ . "}\n" } values %$confs );
                foreach my $nic ( keys %$wlanNics ) {
                    UBOS::Utils::saveFile( "$target/etc/wpa_supplicant-$nic.conf", $content );

                    UBOS::Utils::myexec( 'systemctl is-enabled wpa_supplicant@' . $nic . ' > /dev/null || systemctl enable wpa_supplicant@' . $nic, undef, \$out, \$out );
                    UBOS::Utils::myexec( 'systemctl is-active  wpa_supplicant@' . $nic . ' > /dev/null || systemctl start  wpa_supplicant@' . $nic, undef, \$out, \$out );
                }
            }
        }
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

##
# Helper method to mount a device
# $device: name of the device, e.g. /dev/sdc1
# $targetP: writes the tmp directory object into this var (not the name)
# return: number of errors
sub mountDevice {
    my $device  = shift;
    my $targetP = shift;
    
    my $tmpDir    = UBOS::Host()->config( 'host.tmp', '/tmp' );
    $$targetP     = File::Temp->newdir( DIR => $tmpDir, UNLINK => 1 );
    my $targetDir = $$targetP->dirname;
    my $errors    = 0;

    debugAndSuspend( 'Mount configuration device', $device, 'to', $targetDir );
    if( UBOS::Utils::myexec( "mount -t vfat '$device' '$targetDir'" )) {
        ++$errors;
    }
    return $errors;
}

##
# Helper method to unmount a mounted device
# $device: name of the device, e.g. /dev/sdc1
# $target: the tmp directory object (not the name)
# return: number of errors
sub unmountDevice {
    my $device = shift;
    my $target = shift;

    my $targetDir = $target->dirname;
    my $errors    = 0;

    debugAndSuspend( 'Unmount', $targetDir );
    if( UBOS::Utils::myexec( "umount '$targetDir'" )) {
        ++$errors;
    }

    return $errors;
}

1;
