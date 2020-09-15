#
# Install UBOS for a PC.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: we do nothing

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Pc;

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Install::VolumeLayouts::DiskBlockDevices;
use UBOS::Install::VolumeLayouts::DiskImage;
use UBOS::Install::Volumes::BootVolume;
use UBOS::Install::Volumes::MbrVolume;
use UBOS::Install::Volumes::RootVolume;
use UBOS::Install::Volumes::SwapVolume;
use UBOS::Logging;
use UBOS::Utils;

use base qw( UBOS::Install::AbstractPcInstaller );
use fields;

## Constructor inherited from superclass

##
# Check that the provided parameters are correct, and complete incomplete items from
# default except for the disk layout.
# return: number of errors.
sub checkCompleteParameters {
    my $self = shift;

    # override some defaults

    unless( $self->{hostname} ) {
        $self->{hostname}      = 'ubos-pc';
    }

    unless( $self->{kernelPackage} ) {
        $self->{kernelPackage} = 'linux';
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [ qw(
                ubos-networking-client ubos-networking-gateway ubos-networking-standalone
                grub mkinitcpio
                rng-tools linux-firmware
                smartmontools
                wpa_supplicant crda
                ubos-deviceclass-pc
        ) ];
    }

    unless( $self->{deviceServices} ) {
        $self->{deviceServices} = [ qw(
                haveged.service systemd-timesyncd.service smartd.service
        ) ];
    }

    unless( $self->{partitioningScheme} ) {
        $self->{partitioningScheme} = 'gpt';
    }

    return $self->SUPER::checkCompleteParameters();
}

##
# Check the VolumeLayout parameters, and create a VolumeLayout member.
# return: number of errors
sub checkCreateVolumeLayout {
    my $self = shift;

    trace( 'X86_64::checkCreateVolumeLayout' );

    # We can install to:
    # * an enumeration of block devices for the various roles (e.g. boot, root, ubos, swap)
    #   and raid between them where appropriate
    # * a single image file
    # * one or more disk devices (raid mode)

    my $errors = 0;

    if(    @{$self->{bootloaderDevices}}
        || @{$self->{bootPartitions}}
        || @{$self->{rootPartitions}}
        || @{$self->{ubosPartitions}}
        || @{$self->{swapPartitions}} )
    {
    # enumeration of block devices for the various roles

        if( $self->{swap} ) { # defaults to no swap
            error( 'Invalid invocation: --noswap cannot be used if specifying partitions' );
            ++$errors;
        }
        if( @{$self->{installTargets}} ) {
            error( 'Invalid invocation: either specify entire disks, or specific devices for partitions; do not mix' );
            ++$errors;
        }
        if( @{$self->{bootloaderDevices}} != 1 ) {
            error( 'Invalid invocation: Exactly one --bootloaderdevice must be provided when specifying partitions' );
            ++$errors;
        }

        unless( @{$self->{rootPartitions}} ) {
            error( 'Invalid invocation: A --rootpartition must be provided when specifying partitions' );
            ++$errors;
        }
        foreach my $device ( @{$self->{bootloaderDevices}} ) {
            if(    !UBOS::Install::AbstractVolumeLayout::isDisk( $device )
                && !UBOS::Install::AbstractVolumeLayout::isLoopDevice( $device ))
            {
                error( 'Provided bootloaderdevice is not a disk:', $device );
                ++$errors;
            }
        }
        if( $errors ) {
            goto DONE;
        }

        my %haveAlready = ();
        foreach my $device (
                @{$self->{bootPartitions}},
                @{$self->{rootPartitions}},
                @{$self->{ubosPartitions}},
                @{$self->{swapPartitions}} )
        {
            if( $haveAlready{$device}) {
                error( 'Specified more than once:', $device );
                ++$errors;
            }

            unless( UBOS::Install::AbstractVolumeLayout::isPartition( $device )) {
                error( 'Not a partition:', $device );
                ++$errors;
            }
            if( UBOS::Install::AbstractVolumeLayout::isMountedOrChildMounted( $device )) {
                error( 'Cannot install to mounted disk:', $device );
                ++$errors;
            }
            $haveAlready{$device} = 1;
        }
        if( $errors ) {
            goto DONE;
        }

        my @volumes = ();

        if( @{$self->{bootPartitions}} ) {
            push @volumes, UBOS::Install::Volumes::BootVolume->new( $self->{bootPartitions} );
        }

        push @volumes, UBOS::Install::Volumes::RootVolume->new( @{$self->{rootPartitions}} );

        if( @{$self->{ubosPartitions}} ) {
            push @volumes, UBOS::Install::Volumes::UbosVolume->new( $self->{ubosPartitions} );
        }
        if( @{$self->{swapPartitions}} ) {
            push @volumes, UBOS::Install::Volumes::SwapVolume->new( $self->{swapPartitions} );
        }

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::PartitionBlockDevicesWithBootSector->new(
                    $self->{bootLoaderDevice},
                    \@volumes );


    } elsif(    @{$self->{installTargets}} == 1
             && UBOS::Install::AbstractVolumeLayout::isFile( $self->{installTargets}->[0] ))
    {
    # a single image file
        my $installTarget = $self->{installTargets}->[0];

        my @volumes = ();
        if( 'gpt' eq $self->{partitioningScheme} ) {
            push @volumes, UBOS::Install::Volumes::MbrVolume->new()
        }

        push @volumes, UBOS::Install::Volumes::BootVolume->new();
        push @volumes, UBOS::Install::Volumes::RootVolume->new();

        if( defined( $self->{swap} ) && $self->{swap} == 1 ) { # defaults to no swap
            push @volumes, UBOS::Install::Volumes::SwapVolume->new();
        }

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskImage->new(
                $self->{partitioningScheme},
                $installTarget,
                \@volumes );

    } else {
    # one or more disk devices (raid mode)

        my %haveAlready = ();
        foreach my $device ( @{$self->{installTargets}} ) {
            if( $haveAlready{$device} ) {
                error( 'Specified more than once:', $device );
                ++$errors;
            }
            unless( UBOS::Install::AbstractVolumeLayout::isDisk( $device )) {
                error( 'Not a disk block device:', $device );
                ++$errors;
            }

            if( UBOS::Install::AbstractVolumeLayout::isMountedOrChildMounted( $device )) {
                error( 'Cannot install to mounted disk:', $device );
                ++$errors;
            }
            $haveAlready{$device} = 1;
        }
        if( $errors ) {
            goto DONE;
        }

        my @volumes = ();
        if( 'gpt' eq $self->{partitioningScheme} ) {
            push @volumes, UBOS::Install::Volumes::MbrVolume->new()
        }
        push @volumes, UBOS::Install::Volumes::BootVolume->new();
        push @volumes, UBOS::Install::Volumes::RootVolume->new();

        if( defined( $self->{swap} ) && $self->{swap} == 1 ) { # defaults to no swap
            push @volumes, UBOS::Install::Volumes::SwapVolume->new();
        }

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskBlockDevices->new(
                $self->{partitioningScheme},
                $self->{installTargets},
                \@volumes );
    }

    DONE:
    return $errors;
}

##
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;

    my $errors = 0;

    $errors += $self->installGrub(
            $pacmanConfigFile,
            {
                'target'         => 'i386-pc',
                'boot-directory' => $self->{target} . '/boot'
            } );

    if( 'gpt' eq $self->{partitioningScheme} ) {
        $errors += $self->installSystemdBoot( $pacmanConfigFile );
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
# Returns the arch for this device.
# return: the arch
sub arch {
    return 'x86_64';
}

##
# Returns the device class
sub deviceClass {
    return 'pc';
}

##
# Help text
sub help {
    return 'Root disk for PC (x86_64)';
}
1;
