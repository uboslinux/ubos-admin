#
# Install UBOS on an SD Card or disk for a Raspberry Pi 5.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::AarchRpi5;

use UBOS::Install::AbstractRpiInstaller;
use UBOS::Install::AbstractVolumeLayout;
use UBOS::Logging;
use UBOS::Utils;

use base qw( UBOS::Install::AbstractRpiInstaller );
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
        $self->{hostname}      = 'ubos-raspberry-pi5';
    }

    unless( $self->{kernelPackage} ) {
        $self->{kernelPackage} = 'linux-rpi';
    }

    my $errors = $self->SUPER::checkCompleteParameters();

    push @{$self->{devicePackages}}, 'ubos-deviceclass-rpi5';

    return $errors;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    return 'aarch64';
}

##
# Returns the device class
sub deviceClass {
    return 'rpi5';
}

##
# Help text
sub help {
    return 'SD card or USB disk for Raspberry Pi 5';
}

1;
