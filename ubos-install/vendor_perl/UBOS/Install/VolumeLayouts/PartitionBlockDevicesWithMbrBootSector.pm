#
# A volume layout consiting of block devices referring to partitions,
# identifying a disk as the MBR boot loader device
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::VolumeLayouts::PartitionBlockDevicesWithMbrBootSector;

use base qw( UBOS::Install::AbstractVolumeLayout );
use fields qw( bootloaderDevice );

use UBOS::Logging;

##
# Constructor
# $bootloaderDevice: the device for the MBR boot loader
# @$volumesP: volumes for this layout
sub new {
    my $self             = shift;
    my $bootloaderDevice = shift;
    my $volumesP         = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $volumesP );

    $self->{bootloaderDevice} = $bootloaderDevice;

    return $self;
}

##
# Determine the boot loader device for this VolumeLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{bootloaderDevice};
}

1;
