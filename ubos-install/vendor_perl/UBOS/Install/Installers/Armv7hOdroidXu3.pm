#
# Install UBOS on an SD Card for an Odroid XU3, XU4 or HC2.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Armv7hOdroidXu3;

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
        $self->{hostname}      = 'linux-odroid-xu3';
    }

    unless( $self->{kernelPackage} ) {
        $self->{kernelPackage} = 'linux-odroid-xu3';
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

    unless( $self->{deviceServices} ) {
        $self->{deviceServices} = [ qw(
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

    my $defaultBootVolume = UBOS::Install::Volumes::BootVolume->new(
            'fs'          => 'ext4',
            'partedFs'    => 'ext4',
            'partedFlags' => [ qw( boot ) ]
    );

    my $defaultRootVolume = UBOS::Install::Volumes::RootVolume->new();
    my $defaultSwapVolume = UBOS::Install::Volumes::SwapVolume->new(
            'size'        => 1 * 1024 * 1024 * 1024, # 1G
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

    my $errors        = 0;
    my $target        = $self->{target};
    my $installTarget = $self->{installTargets}->[0];

    trace( "Installing bootloader" );

    my $kernelPars = $self->getAllKernelParameters();
    my $bootTxt    = UBOS::Utils::slurpFile( "$target/boot/boot.txt" );
    if( $bootTxt ) {
        # setenv bootargs "console=tty1 console=ttySAC2,115200n8 root=PARTUUID=${uuid} rw rootwait smsc95xx.macaddr=${macaddr} ${videoconfig}"

        unless( $bootTxt =~ s!setenv bootargs "(.*)"$!setenv bootargs "$1 $kernelPars"!m ) {
            error( 'Failed to add kernel parameters' );
            ++$errors;
        }
        unless( UBOS::Utils::saveFile( "$target/boot/boot.txt", $bootTxt, 0644, 'root', 'root' )) {
            ++$errors;
        }
    } else {
        ++$errors;
    }

    # invoke mkscr, but mkscr is just a brief shell script invoking this, but with the wrong path ($target)
    if( UBOS::Utils::myexec( "cd $target/boot && $target/usr/bin/mkimage -A arm -O linux -T script -C none -n \"U-Boot boot script\" -d boot.txt boot.scr" )) {
        ++$errors;
    }

    if( UBOS::Utils::myexec( "cd $target/boot && $target/boot/sd_fusing.sh $installTarget" )) {
        ++$errors;
    }


    return $errors;
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
