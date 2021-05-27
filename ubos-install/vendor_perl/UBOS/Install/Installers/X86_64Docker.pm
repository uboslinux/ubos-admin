#
# Install UBOS for Docker running on an x86_64 device.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Docker;

use UBOS::Install::AbstractDockerInstaller;

use base qw( UBOS::Install::AbstractDockerInstaller );
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
    return 'docker';
}

##
# Help text
sub help {
    return 'Docker on x86_64';
}

1;
