#!/usr/bin/perl
#
# Manages the configuration of the host using a config drive, called the
# ubos staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

#
# Comments:
# Cannot check that device is removable: some USB disks have that at 0
# We accept partitions or entire disks
# We also accept a directory called /UBOS-STAFF, to support containerization
#

use strict;
use warnings;

package UBOS::StaffManager;

use File::Temp;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Utils;

my $LABEL                    = 'UBOS-STAFF';
my $STAFF_BOOT_CALLBACKS_DIR = '/etc/ubos/staff-boot-callbacks';

# Name of the file that needs to be on the root of the UBOS Staff to
# skip registering for UBOS Live.
our $SKIP_UBOS_LIVE_FILE = 'I-ADMINISTER-MY-UBOSBOX-MYSELF.txt';

##
# Invoked during boot.
# 1. Initialize the configuration if there's a staff device attached
# 2. Deploy site templates if needed
# return: number of errors
sub performBootActions {
    trace( 'StaffManager::initializeIfNeeded' );

    unless( UBOS::Host::vars()->getResolve( 'host.readstaffonboot', 1 )) {
        return 0;
    }

    my $device = guessStaffDevice();

    my $target;
    my $isActualStaffDevice;

    if( $device ) {
        trace( 'Staff device:', $device );

        if( mountDevice( $device, \$target )) {
            error( 'Failed to mount:', $device, $target );
            return 1;
        }
        $isActualStaffDevice = 1;

    } else  {
        my $out;
        if( UBOS::Utils::myexec( 'systemd-detect-virt', undef, \$out, \$out ) == 0 ) {
            # container/cloud case
            if( -d "/$LABEL" ) {
                $target              = "/$LABEL";
                $isActualStaffDevice = 0;

            } else {
                trace( 'No staff device found' );
                return 0;
            }
        } else {
            # regular computer, but no staff device
            return 0;
        }
    }

    my $errors = 0;
    if( loadCurrentConfiguration( $target, $isActualStaffDevice )) {
        error( 'Loading current configuration failed from', $device, $target );
        ++$errors;
    }

    if( saveCurrentConfiguration( $target, $isActualStaffDevice )) {
        error( 'Saving current configuration failed to', $device, $target );
        ++$errors;
    }

    if( $device ) {
        if( unmountDevice( $device, $target )) {
            error( 'Failed to unmount:', $device, $target );
            ++$errors;
        }
    }

    return $errors;
}

##
# Check that a candidate device is indeed a staff device
# $device: the candidate device, may be disk or partition
# $label: if 1, do not require the UBOS-STAFF label but rename if needed
# return: the $device if partition, or the partition device on $device, or undef
sub checkStaffDevice {
    my $device = shift;
    my $label  = shift;

    trace( 'StaffManager::checkStaffDevice', $device, $label );

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
    my $retFsLabel;

    # NAME="sda" TYPE="disk" FSTYPE="" LABEL=""
    # NAME="sda1" TYPE="part" FSTYPE="ext4" LABEL=""
    # NAME="sda2" TYPE="part" FSTYPE="vfat" LABEL=""

    while( $out =~ m!NAME="([^"]+)"\s+TYPE="([^"]+)"\s+FSTYPE="([^"]*)"\s+LABEL="([^"]*)"!g ) {
        my( $name, $type, $fstype, $fsLabel ) = ( "/dev/$1", $2, $3, $4 );
        unless( $fstype eq 'vfat' ) {
            next;
        }
        if( !$label && $fsLabel ne $LABEL ) {
            next;
        }
        if( $ret ) {
            $@ = 'More than one partition suitable as UBOS staff found: ' . $ret . ' ' . $name;
            return undef;
        }
        $ret        = $name;
        $retFsLabel = $fsLabel;
    }

    if( $ret ) {
        if( $label && ( !defined( $retFsLabel ) || ( $retFsLabel ne $LABEL ))) {
            labelDeviceAsStaff( $ret );
        }
    } else {
        $@ = 'No partition suitable as UBOS staff found on: ' . $device;
    }

    return $ret;
}

##
# Guess the name of the staff device
# return: device, or undef
sub guessStaffDevice {

    trace( 'StaffManager::guessStaffDevice' );

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
            $@ = 'More than one device found that is suitable as UBOS Staff: ' . $ret . ' ' . $name;
            return undef;
        }
        $ret = $name;
    }
    unless( $ret ) {
        $@ = 'No device found that is suitable as a UBOS Staff.';
    }

    return $ret;
}

##
# Format a device as a suitable UBOS Staff device
# $device: the device to be formatted
# return: the $device if partition, or the partition device on $device, or undef
sub formatStaffDevice {
    my $device = shift;

    $device = UBOS::Utils::absReadlink( $device ); # udev may not be fast enough for this script, so go to /dev/sdX

    unless( -b $device ) {
        fatal( 'Not a block device:', $device );
    }


    # If this is a device without a partition table, create one
    my $out;
    UBOS::Utils::myexec( "lsblk -o NAME,TYPE --json -n '$device'", undef, \$out );

    my $json = UBOS::Utils::readJsonFromString( $out );

    if( $json && exists( $json->{blockdevices} ) && @{$json->{blockdevices}} ) {
        my $type = $json->{blockdevices}->[0]->{type};

        unless( $type eq 'part' ) {
            my $fdiskScript = '';
            $fdiskScript .= <<END; # clear out everything, create single partition of type b=FAT32
o
n
p




t
b
w
END

            trace( 'fdisk script for', $device, ':', $fdiskScript );

            if( UBOS::Utils::myexec( "fdisk '" . $device . "'", $fdiskScript, \$out, \$out )) {
                error( 'fdisk failed', $out );
                return undef;
            }
            $device = $device . '1';
        }
    }

    if( UBOS::Utils::myexec( "mkfs.vfat '$device' -n UBOS-STAFF", undef, \$out, \$out )) {
        error( 'mkfs.vfat failed:', $out );
        return undef;
    }

    return $device;
}

##
# Load configuration from this directory
# $target: the target directory from which to read (root directory of stick)
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub loadCurrentConfiguration {
    my $target              = shift;
    my $isActualStaffDevice = shift;

    trace( 'StaffManager::loadCurrentConfiguration', $target, $isActualStaffDevice );

    return UBOS::Utils::invokeCallbacks( $STAFF_BOOT_CALLBACKS_DIR, 1, 'performAtLoad', $target, $isActualStaffDevice );
}

##
# Save current configuration to this directory
# $target: the target directory for the save (root directory of stick)
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub saveCurrentConfiguration {
    my $target              = shift;
    my $isActualStaffDevice = shift;

    trace( 'StaffManager::saveCurrentConfiguration', $target, $isActualStaffDevice );

    return UBOS::Utils::invokeCallbacks( $STAFF_BOOT_CALLBACKS_DIR, 0, 'performAtSave', $target, $isActualStaffDevice );
}

##
# Create or update the shepherd user
# $key: the public ssh key which is allowed to log in, if any
# $add: if true, add the keys
# $force: if true, replace an existing key
# return: 1 if ok
sub setupUpdateShepherd {
    my $key   = shift;
    my $add   = shift;
    my $force = shift;

    my $homeShepherd = UBOS::Host::vars()->getResolve( 'host.homeshepherd', '/var/shepherd' );
    if( UBOS::Utils::ensureOsUser( 'shepherd', undef, 'UBOS shepherd user', $homeShepherd )) {

        trace( 'StaffManager::setupUpdateShepherd', $key, $add, $force );

        my $authKeyFile = "$homeShepherd/.ssh/authorized_keys";
        unless( -d "$homeShepherd/.ssh" ) {
            UBOS::Utils::mkdir( "$homeShepherd/.ssh", 0700, 'shepherd', 'shepherd' );
        }
        if( $key ) {
            my $authorizedKeys;
            if( -e $authKeyFile ) {
                $authorizedKeys = UBOS::Utils::slurpFile( $authKeyFile );
                if( $add ) {
                    $authorizedKeys .= "\n" . $key;
                } elsif( $force ) {
                    $authorizedKeys = $key;
                } else {
                    error( 'There is already a key on this account. Use --add or --force to add or overwrite.' );
                    return 0;
                }
            } else {
                $authorizedKeys = $key;
            }
            UBOS::Utils::saveFile( $authKeyFile, $authorizedKeys, 0644, 'shepherd', 'shepherd' );
        }

        unless( UBOS::Utils::saveFile( '/etc/sudoers.d/shepherd', <<'CONTENT', 0600, 'root', 'root' )) {
shepherd ALL = NOPASSWD: \
    /usr/bin/docker *, \
    /usr/bin/journalctl *, \
    /usr/bin/mkdir *, \
    /usr/bin/mount *, \
    /usr/bin/pacman *, \
    /usr/bin/pacman-key *, \
    /usr/bin/smartctl *, \
    /usr/bin/systemctl *, \
    /usr/bin/ubos-admin *, \
    /usr/bin/ubos-install *, \
    /usr/bin/umount *, \
    /usr/bin/snapper *, \
    /usr/bin/storj-gateway *, \
    /usr/bin/storj-gateway-credentials *, \
    /usr/bin/storj-identity *, \
    /usr/bin/storj-linksharing *, \
    /usr/bin/storj-uplink *, \
    /usr/bin/su *, \
    /bin/bash *
CONTENT
            # If you change this, also change ubos-cloud.cfg in cloud-init

            return 0;
        }
        return 1;
    }
    return 0;
}

##
# Completely erase all files in a directory and initialize with the staff structure
# $dir: the directory
# $shepherdKey: public ssh key for the shepherd, if any
# $wifis: hash of WiFi network client information
# $siteTemplates: hash of template name to site template JSON
# $noUbosLive: if true, put the skip file at the root of the device
# return: number of errors
sub initDirectoryAsStaff {
    my $dir           = shift;
    my $shepherdKey   = shift;
    my $wifis         = shift;
    my $siteTemplates = shift;
    my $noUbosLive    = shift;

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

    if( $shepherdKey ) {
        # no need to care about permissions, this is DOS
        UBOS::Utils::saveFile( "$dir/shepherd/ssh/id_rsa.pub", "$shepherdKey\n" );
    }

    UBOS::Utils::mkdirDashP( "$dir/wifi" );
    foreach my $ssid ( keys %$wifis ) {
        my $values  = $wifis->{$ssid};
        my $content = join( '', map { $_ . '="' . $values->{$_} . '"' . "\n" } keys %$values );
        # There is no documentation on whether to escape this, but wpa_passphrase does not
        # escape things in its commented-out output, so we do the same
        UBOS::Utils::saveFile( "$dir/wifi/$ssid.conf", $content );
    }
    UBOS::Utils::saveFile( "$dir/wifi/README", <<CONTENT );
This directory can hold information about one or more WiFi networks.
Each WiFi network must be described in a separate file and must be named
<ssid>.conf if <ssid> is the SSID of the network.

For details, go to https://ubos.net/staff

CONTENT

    UBOS::Utils::mkdirDashP( "$dir/site-templates" );
    foreach my $siteTemplateName ( keys %$siteTemplates ) {
        my $siteTemplateJson = $siteTemplates->{$siteTemplateName};

        UBOS::Utils::writeJsonToFile( "$dir/site-templates/$siteTemplateName.json", $siteTemplateJson );
    }
    UBOS::Utils::saveFile( "$dir/site-templates/README", <<CONTENT );
This directory can hold one or more Site JSON templates, which will be instantiated
and deployed upon boot.

For details, go to https://ubos.net/staff

CONTENT

    if( $noUbosLive ) {
         UBOS::Utils::saveFile( "$dir/$SKIP_UBOS_LIVE_FILE", <<CONTENT );
You have chosen to administer your UBOSbox yourself and not use UBOS Live.

That's perfectly fine, but you are on your own performing upgrades etc :-)

If you change your mind:
* delete this file from your UBOS Staff,
* make sure package ubos-live is installed on your UBOSbox,
* reboot your UBOSbox with the UBOS Staff present,
* then put your UBOS Staff into a computer with a web browser, click
  on the UBOS-STAFF.html file and follow the registration flow from there.

CONTENT
    }
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
# Helper method to mount a device
# $device: name of the device, e.g. /dev/sdc1
# $targetP: writes the tmp directory object into this var (not the name)
# return: number of errors
sub mountDevice {
    my $device  = shift;
    my $targetP = shift;

    my $tmpDir    = UBOS::Host::vars()->getResolve( 'host.tmp', '/tmp' );
    $$targetP     = File::Temp->newdir( DIR => $tmpDir, UNLINK => 1 );
    my $targetDir = $$targetP->dirname;
    my $errors    = 0;

    debugAndSuspend( 'Mount staff device', $device, 'to', $targetDir );
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
