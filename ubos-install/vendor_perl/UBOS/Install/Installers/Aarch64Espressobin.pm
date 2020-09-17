#
# Install UBOS for ESPRESSObin
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: we do nothing

use strict;
use warnings;

package UBOS::Install::Installers::Aarch64Espressobin;

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Install::VolumeLayouts::DiskImage;
use UBOS::Install::VolumeLayouts::DiskBlockDevices;
use UBOS::Install::Volumes::BootVolume;
use UBOS::Install::Volumes::RootVolume;
use UBOS::Install::Volumes::SwapVolume;
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
        $self->{hostname}      = 'ubos-espressobin';
    }

    unless( $self->{kernelPackage} ) {
        $self->{kernelPackage} = 'linux-espressobin';
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [ qw(
                ubos-networking-client ubos-networking-espressobin ubos-networking-standalone
                archlinuxarm-keyring
                uboot-tools espressobin-uboot-config espressobin-ubos-state
                smartmontools
                wpa_supplicant crda
                ubos-deviceclass-espressobin
        ) ];
    }

    unless( $self->{deviceServices} ) {
        $self->{deviceServices} = [ qw(
                haveged.service systemd-timesyncd.service
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

    my $defaultBootVolume = UBOS::Install::Volumes::BootVolume->new(
            'fs'          => 'ext4',
            'mkfsFlags'   => '-O ^metadata_csum,^64bit',
            'partedFs'    => 'ext4',
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
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;

    # don't do anything here. All contained in uboot-espressobin-config
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
    return 'aarch64';
}

##
# return: the device class
sub deviceClass {
    return 'espressobin';
}

##
# Help text
sub help {
    return 'Boot disk for ESPRESSObin';
}

1;
