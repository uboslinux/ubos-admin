#
# Install UBOS for a Linux container running on an ARMv6 device.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Armv6hContainer;

use base qw( UBOS::Install::AbstractContainerInstaller );
use fields;

## Constructor inherited from superclass

##
# Check that the provided parameters are correct, and complete incomplete items from
# default except for the disk layout.
# return: number of errors.
sub checkCompleteParameters {
    my $self = shift;

    my $errors = $self->SUPER::checkCompleteParameters();

    # Add keyring, as on arm (unlike x86), pacman does not depend on it
    push @{$self->{devicePackages}}, 'archlinuxarm-keyring';

    return $errors;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    return 'armv6h';
}

##
# Returns the device class
sub deviceClass {
    return 'container';
}

##
# Help text
sub help {
    return 'Linux container on armv6h';
}

1;
