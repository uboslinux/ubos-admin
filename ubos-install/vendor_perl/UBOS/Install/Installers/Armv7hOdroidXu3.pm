#
# Install UBOS on an SD Card for an Odroid XU3, XU4 or HC2.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Armv7hOdroidXu3;

#use UBOS::Install::AbstractVolumeLayout;
#use UBOS::Install::VolumeLayouts::DiskImage;
#use UBOS::Install::VolumeLayouts::DiskBlockDevices;
#use UBOS::Install::Volumes::BootVolume;
#use UBOS::Install::Volumes::RootVolume;
#use UBOS::Install::Volumes::SwapVolume;
use UBOS::Logging;
use UBOS::Utils;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

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

    unless( $self->{hostname} ) {
        $self->{hostname}      = 'linux-odroid-xu3';
    }

    unless( $self->{kernelpackage} ) {
        $self->{kernelpackage} = 'linux-odroid-xu3';
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [ qw(
                ubos-networking-client ubos-networking-standalone
                archlinuxarm-keyring
                uboot-odroid-xu3 uboot-tools
                smartmontools
                wpa_supplicant crda
                ubos-deviceclass-odroidxu3
        ) ];
    }

    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw(
                systemd-timesyncd.service
        ) ];
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

#    my $defaultBootVolume = UBOS::Install::Volumes::BootVolume( {
#            'fs'        => 'ext4',
#            'size'      => 128 * 1024 * 1024, # 128M
#            'mbrBoot'   => 1
#    } );

    my $defaultRootVolume = UBOS::Install::Volumes::RootVolume(
            'fs'         => 'ext4'
    );

    my $defaultSwapVolume = UBOS::Install::Volumes::SwapVolume( {
            'size'      => 4 * 1024 * 1024 * 1024, # 4G
    } );

    # No separate /ubos volume

    my $installTarget = $self->{installTargets}->[0];
    if( UBOS::Install::AbstractVolumeLayout::isFile( $installTarget )) {
        # install to file
        my @volumes = (
#            $defaultBootVolume,
            $defaultRootVolume
        );
        if( defined( $self->{swap} ) && $self->{swap} == 1 ) { # defaults to no swap
            push @volumes, $defaultSwapVolume;
        }

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskImage->new(
                'msdos',
                $installTarget,
                \@volumes );


    } elsif( UBOS::Install::AbstractVolumeLayout::isDisk( $installTarget )) {
        # install to disk block device
        if( UBOS::Install::AbstractVolumeLayout::isMountedOrChildMounted( $installTarget )) {
            error( 'Cannot install to mounted disk:', $installTarget );
            ++$errors;

        } else {
            my @volumes = (
#                $defaultBootVolume,
                $defaultRootVolume
            );
            if( defined( $self->{swap} ) && $self->{swap} != -1 ) { # defaults to swap
                push @volumes, $defaultSwapVolume;
            }

            $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskBlockDevices->new(
                    'msdos',
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
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;

    error( 'FIXME' );

    return 0;
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    trace( "Executing addConfigureNetworkingToScript" );

    $$chrootScriptP .= "ubos-admin setnetconfig --skip-check-ready --init-only espressobin\n";

    return 0;
}

##
# return: the arch for this device
sub arch {
    return 'armv7h';
}

##
# return: the device class
sub deviceClass {
    return 'odroid-xu3';
}

##
# Help text
sub help {
    return 'SD card for Odroid-XU3/XU4/HC1/HC2';
}

1;
