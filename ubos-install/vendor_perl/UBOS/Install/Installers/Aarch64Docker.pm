#
# Install UBOS for Docker running on an aarch64 device.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Aarch64Docker;

use UBOS::Install::AbstractDockerInstaller;

use base qw( UBOS::Install::AbstractDockerInstaller );
use fields;

## Constructor inherited from superclass

##
# Returns the arch for this device.
# return: the arch
sub arch {
    return 'aarch64';
}

##
# Returns the device class
sub deviceClass {
    return 'docker';
}

##
# Help text
sub help {
    return 'Docker on aarch64';
}

1;
