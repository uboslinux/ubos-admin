#
# Abstract superclass for Docker installers.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::AbstractDockerInstaller;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Install::VolumeLayouts::DiskImage;
use UBOS::Install::Volumes::RootVolume;
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

    unless( $self->{hostname} ) {
        $self->{hostname}  = 'ubos-docker';
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [ qw(
                ubos-networking-docker
                archlinux-keyring
                ubos-deviceclass-docker
        ) ];
    }

    if( $self->{noBoot} ) {
        error( 'Cannot specify --noboot with this device class' );
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
    # * a single directory

    my $errors = $self->_checkSingleInstallTargetOnly();
    if( $errors ) {
        return $errors;
    }

    if( $self->{swap} ) {
        error( 'Cannot use swap flag with this device class' );
        return 1;
    }

    my $installTarget = $self->{installTargets}->[0];

    if( UBOS::Install::AbstractVolumeLayout::isFile( $installTarget )) {
        # install to file
        my @volumes = (
            UBOS::Install::Volumes::RootVolume->new() # defaults
        );

        $self->{volumeLayout} = UBOS::Install::VolumeLayouts::DiskImage->new(
                'mbr',
                $installTarget,
                \@volumes );

    } else {
        error( 'Install target must be a disk image for this device class:', $installTarget );
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

    $$chrootScriptP .= "ubos-admin setnetconfig --skip-check-ready --init-only docker\n";

    return 0;
}

1;
