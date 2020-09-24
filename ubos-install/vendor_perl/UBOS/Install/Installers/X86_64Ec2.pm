#
# Install UBOS for Amazon EC2
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: haveged for artificial entropy.
# * cloud-init for ssh keys
# * we use linux-ec2 as the name for the kernel, but we do not use
#   mkinitcpio's linux-ec2.preset but plain linux.preset instead

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Ec2;

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Install::VolumeLayouts::DiskImage;
use UBOS::Install::VolumeLayouts::DiskBlockDevices;
use UBOS::Install::Volumes::BootVolume;
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
        $self->{hostname} = 'ubos-es2';
    }

    unless( $self->{kernelPackage} ) {
        $self->{kernelPackage} = 'linux-ec2';
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [ qw(
                ubos-networking-cloud
                archlinux-keyring ec2-keyring
                grub mkinitcpio
                ubos-deviceclass-ec2
        ) ];
    }

    unless( $self->{deviceServices} ) {
        $self->{deviceServices} = [ qw(
                haveged.service systemd-timesyncd.service
        ) ];
    }

    unless( $self->{partitioningScheme} ) {
        $self->{partitioningScheme} = 'mbr';
    }

    return $self->SUPER::checkCompleteParameters();
}

##
# Check the VolumeLayout parameters, and create a VolumeLayout member.
# return: number of errors
sub checkCreateVolumeLayout {
    my $self = shift;

    # We can install to:
    # * a single block device

    my $errors = $self->_checkSingleInstallTargetOnly();
    if( $errors ) {
        return $errors;
    }

    my $installTarget = $self->{installTargets}->[0];
    if( UBOS::Install::AbstractVolumeLayout::isBlockDevice( $installTarget )) {
        # install to file

        my @volumes = (
            UBOS::Install::Volumes::RootVolume->new()
        );
        if( defined( $self->{swap} ) && $self->{swap} != -1 ) { # defaults to swap
            push @volumes, UBOS::Install::Volumes::SwapVolume->new( 4 * 1024 * 1024 * 1024 ); # 4G
        }

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskBlockDevices->new(
                $self->{partitioningScheme},
                $self->{installTargets},
                \@volumes );

    } else {
        error( 'Install target must be a block device for this device class:', $installTarget );
        ++$errors;
    }

    return $errors;
}

##
# Install a Ram disk -- overridden for EC2 so we can get the -ec2 kernel
# $kernelPostfix: allows us to add -ec2 to EC2 kernels
# return: number of errors
sub installRamdisk {
    my $self = shift;

    return $self->SUPER::installRamdisk( '-ec2' );
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    trace( "Executing addConfigureNetworkingToScript" );

    $$chrootScriptP .= "ubos-admin setnetconfig --skip-check-ready --init-only cloud\n";

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
    return 'ec2';
}

##
# Help text
sub help {
    return 'Amazon EC2 disk image (needs additional conversion to AMI)';
}

1;
