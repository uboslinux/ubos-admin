#
# Abstract superclass for Raspberry Pi installers.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: PI has /dev/hwrng, so we run rngd, and patch its
#   configuration file during ubos-install, as long as Arch ARM hasn't updated the
#   default configuration they ship, which is identical as the x86 one:
#   http://archlinuxarm.org/forum/viewtopic.php?f=60&t=8571,

use strict;
use warnings;

package UBOS::Install::AbstractRpiInstaller;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Install::VolumeLayouts::DiskImage;
use UBOS::Install::VolumeLayouts::DiskBlockDevices;
use UBOS::Install::Volumes::BootVolume;
use UBOS::Install::Volumes::RootVolume;
use UBOS::Install::Volumes::SwapVolume;
use UBOS::Logging;
use UBOS::Utils;

## Constructor inherited from superclass

##
# Check that the provided parameters are correct, and complete incomplete items from
# default except for the disk layout.
# return: number of errors.
sub checkCompleteParameters {
    my $self = shift;

    # override some defaults

    my $errors = 0;

    if( $self->{partitioningScheme} ) {
        error( 'Cannot specify a partitioning scheme with this device class' );
        ++$errors;
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [ qw(
                ubos-networking-client
                archlinuxarm-keyring
                rng-tools raspberrypi-firmware raspberrypi-bootloader raspberrypi-bootloader-x
                smartmontools
                wpa_supplicant crda
        ) ];
    }

    unless( $self->{deviceServices} ) {
        $self->{deviceServices} = [ qw(
                rngd.service systemd-timesyncd.service
        ) ];
    }

    unless( $self->{deviceKernelModules} ) {
        $self->{deviceKernelModules} = [ qw( snd-bcm2835 ) ];
    }

    $errors += $self->SUPER::checkCompleteParameters();
    return $errors;
}

##
# Check the VolumeLayout parameters, and create a VolumeLayout member.
# return: number of errors
sub checkCreateVolumeLayout {
    my $self = shift;

    # We can install to:
    # * a single file
    # * a single disk device

    my $errors = $self->_checkSingleInstallTargetOnly();
    if( $errors ) {
        return $errors;
    }

    my $defaultBootVolume = UBOS::Install::Volumes::BootVolume->new(
            'fs'          => 'vfat',
            'mkfsFlags'   => '-F32',
            'partedFs'    => 'fat32',
            'partedFlags' => [ qw( boot ) ]
    );

    my $defaultRootVolume = UBOS::Install::Volumes::RootVolume->new(); # defaults

    my $defaultSwapVolume = UBOS::Install::Volumes::SwapVolume->new(
            'size'      => 1 * 1024 * 1024 * 1024, # 1G
    );

    # No separate /ubos volume

    my $installTarget = $self->{installTargets}->[0];
    if( UBOS::Install::AbstractVolumeLayout::isFile( $installTarget )) {
        # install to file
        my @volumes = (
            $defaultBootVolume,
            $defaultRootVolume
        );
        if( defined( $self->{swap} ) && $self->{swap} == 1 ) { # defaults to no swap
            push @volumes, $defaultSwapVolume;
        }

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskImage->new(
                'mbr',
                $installTarget,
                \@volumes );


    } elsif( UBOS::Install::AbstractVolumeLayout::isDisk( $installTarget )) {
        # install to disk block device
        if( UBOS::Install::AbstractVolumeLayout::isMountedOrChildMounted( $installTarget )) {
            error( 'Cannot install to mounted disk:', $installTarget );
            ++$errors;

        } else {
            my @volumes = (
                $defaultBootVolume,
                $defaultRootVolume
            );
            if( defined( $self->{swap} ) && $self->{swap} != -1 ) { # defaults to swap
                push @volumes, $defaultSwapVolume;
            }

            $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskBlockDevices->new(
                    'mbr',
                    [ $installTarget ],
                    \@volumes );
        }

    } else {
        error( 'Install target must be a file or a disk block device for this device class:', $installTarget );
        ++$errors;
    }

    return $errors;
}

##
# Generate and save different other files if needed
# return: number of errors
sub saveOther {
    my $self = shift;

    my $ret    = 0;
    my $target = $self->{target};

    # Use hardware random generator by default

    unless( UBOS::Utils::saveFile( "$target/etc/conf.d/rngd", <<CONTENT )) {
# Changed for UBOS
RNGD_OPTS="-o /dev/random -r /dev/hwrng"
CONTENT
        ++$ret;
    }

    unless( UBOS::Utils::saveFile( "$target/etc/udev/rules.d/raspberrypi.rules", <<CONTENT )) {
SUBSYSTEM=="vchiq|input", MODE="0777"
KERNEL=="mouse*|mice|event*", MODE="0777"
CONTENT
        ++$ret;
    }

    return $ret;
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    trace( "Executing addConfigureNetworkingToScript" );

    $$chrootScriptP .= "ubos-admin setnetconfig --skip-check-ready --init-only client\n";

    return 0;
}

1;
