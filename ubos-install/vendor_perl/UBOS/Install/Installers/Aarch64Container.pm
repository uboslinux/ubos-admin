#
# Install UBOS for a Linux container running on an aarch64 device.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Aarch64Container;

use base qw( UBOS::Install::AbstractContainerInstaller );
use fields;

##
# Constructor. Add keyring, as on arm (unlike x86), pacman does not depend on it
sub new {
    my $self = shift;
    my @args = @_;

    unless( ref $self ) {
        $self = fields::new( $self );

    }
    $self->SUPER::new( @args );

    push @{$self->{devicepackages}}, 'archlinuxarm-keyring';

    return $self;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'aarch64';
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
    return 'Linux container on aarch64';
}

1;
