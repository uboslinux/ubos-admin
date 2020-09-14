#
# Install UBOS for a Linux container running on an x86_64 device.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Container;

use UBOS::Install::AbstractContainerInstaller;

use base qw( UBOS::Install::AbstractContainerInstaller );
use fields;

## Constructor inherited from superclass

##
# Returns the arch for this device.
# return: the arch
sub arch {
    return 'x86_64';
}

##
# Returns the device class
sub deviceClass {
    return 'container';
}

##
# Help text
sub help {
    return 'Linux container on x86_64';
}

1;
