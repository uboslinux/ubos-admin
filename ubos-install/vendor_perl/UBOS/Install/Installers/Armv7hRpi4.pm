#
# Install UBOS on an SD Card or disk for a Raspberry Pi 4.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Armv7hRpi4;

use base qw( UBOS::Install::AbstractRpiInstaller );
use fields;

use UBOS::Install::AbstractVolumeLayout;
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

    unless( $self->{hostname} ) {
        $self->{hostname}      = 'ubos-raspberry-pi4';
    }

    unless( $self->{kernelpackage} ) {
        $self->{kernelpackage} = 'linux-raspberrypi4';
    }

    my $errors = $self->SUPER::checkComplete();

    push @{$self->{devicePackages}}, 'ubos-deviceclass-rpi4';

    return $errors;
}

##
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# $diskLayout: the disk layout
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;

    info( 'Installing boot loader' );

    # Copied from the ArchLinuxARM Raspberry Pi 4 image

    my $addParString = '';
    if( defined( $self->{additionalkernelparameters} )) {
        map { $addParString .= ' ' . $_ } @{$self->{additionalkernelparameters}};
    }

    my $rootPartUuid = UBOS::Install::AbstractVolumeLayout::determinePartUuid( $self->{diskLayout}->getRootDeviceNames() );

    my $cmdline = 'root=PARTUUID=' . $rootPartUuid; # 'root=/dev/mmcblk0p2';
    $cmdline .= <<CONTENT;
 rw rootwait rootfstype=btrfs console=ttyAMA0,115200 console=tty1 kgdboc=ttyAMA0,115200 selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 elevator=noop$addParString
CONTENT

    UBOS::Utils::saveFile( $self->{target} . '/boot/cmdline.txt', $cmdline, 0644, 'root', 'root' );

    UBOS::Utils::saveFile( $self->{target} . '/boot/config.txt', <<CONTENT, 0644, 'root', 'root' );
# See /boot/overlays/README for all available options

gpu_mem=64
initramfs initramfs-linux.img followkernel

CONTENT

    return 0;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    return 'armv7h';
}

##
# Returns the device class
sub deviceClass {
    return 'rpi4';
}

##
# Help text
sub help {
    return 'SD card or USB disk for Raspberry Pi 4';
}

1;
