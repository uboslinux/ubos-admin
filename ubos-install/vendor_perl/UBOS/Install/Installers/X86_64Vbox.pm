#
# Install UBOS for a 64-bit PC emulated in VirtualBox.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: haveged for artificial entropy. VirtualBox does not
#   currently have any support for (virtual) hardware random devices:
#   https://www.virtualbox.org/pipermail/vbox-dev/2015-March/012909.html

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Vbox;

#use UBOS::Install::AbstractVolumeLayout;
#use UBOS::Install::VolumeLayouts::DiskImage;
#use UBOS::Install::Volumes::RootVolume;
#use UBOS::Install::Volumes::SwapVolume;
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
        $self->{hostname} = 'ubos-vbox-pc';
    }

    unless( $self->{kernelPackage} ) {
        $self->{kernelPackage} = 'linux';
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [ qw(
                ubos-networking-client
                grub mkinitcpio
                virtualbox-guest-utils
                ubos-deviceclass-vbox
        ) ];
    }

    unless( $self->{deviceServices} ) {
        $self->{deviceServices} = [ qw(
                haveged.service vboxservice.service  systemd-timesyncd.service
        ) ];
    }

    $self->{packagedbs}->{'virt'} = '$depotRoot/$channel/$arch/virt';

    return $self->SUPER::checkCompleteParameters();
}

##
# Check the VolumeLayout parameters, and create a VolumeLayout member.
# return: number of errors
sub checkCreateVolumeLayout {
    my $self = shift;

    # We can install to:
    # * a single file

    my $errors = $self->_checkSingleInstallTargetOnly();
    if( $errors ) {
        return $errors;
    }

    if( $self->{swap} ) {
        error( 'Cannot use --swap with this device class' );
        return 1;
    }

    my $installTarget = $self->{installTargets}->[0];
    if( UBOS::Install::AbstractVolumeLayout::isFile( $installTarget )) {
        # install to file

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskImage->new(
                $self->{partitioningScheme},
                $installTarget,
                [
                    UBOS::Install::Volumes::RootVolume->new() # defaults
                ] );

    } else {
        error( 'Install target must be a file for this device class:', $installTarget );
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
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'x86_64';
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'vbox';
}

##
# Help text
sub help {
    return 'Virtual root disk for VirtualBox (needs additional conversion to .vmdk)';
}

1;
