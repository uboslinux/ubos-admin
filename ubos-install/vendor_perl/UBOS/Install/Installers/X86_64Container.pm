#
# Install UBOS for a Linux container running on x86_64.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Container;

use base qw( UBOS::Install::AbstractContainerInstaller );
use fields;

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

    return 'container';
}

##
# Help text
sub help {
    return 'Linux container on x86_64';
}

1;
