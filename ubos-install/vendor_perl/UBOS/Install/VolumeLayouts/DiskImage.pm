#
# A disk image volume layout. Contains at least one partition.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::VolumeLayouts::DiskImage;

use base qw( UBOS::Install::AbstractVolumeLayout );
use fields qw( partitioningScheme image startOffset alignment loopDevice );

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Utils;
use UBOS::Logging;

##
# Constructor
sub new {
    my $self               = shift;
    my $partitioningScheme = shift;
    my $image              = shift;
    my $volumesP           = shift;
    my $startOffset        = shift || 2048 * 512;
    my $alignment          = shift || 'minimal';

    if( $partitioningScheme ne 'gpt' && $partitioningScheme ne 'mbr' && $partitioningScheme ne 'gpt+mbr' ) {
        fatal( 'Invalid partitioning scheme:', $partitioningScheme );
    }

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $volumesP );

    $self->{partitioningScheme} = $partitioningScheme;
    $self->{image}              = $image;
    $self->{startOffset}        = $startOffset;
    $self->{alignment}          = $alignment;

    return $self;
}

##
# Create the configured volumes.
sub createVolumes {
    my $self = shift;

    trace( 'DiskImage::createVolumes' );

    my $errors = $self->formatSingleDisk( $self->{image}, $self->{partitioningScheme}, $self->{startOffset}, $self->{alignment} );
    return $errors;
}

##
# Create any needed loop devices.
# return: number of errors
sub createLoopDevices {
    my $self = shift;

    trace( "Creating loop devices" );

    my $errors = 0;

    my $out;
    if( UBOS::Utils::myexec( "losetup --show --find --partscan '" . $self->{image} . "'", undef, \$out, \$out )) {
        error( "losetup -a error:", $out );
        ++$errors;
    }
    $out =~ s!^\s+!!;
    $out =~ s!\s+$!!;
    $self->{loopDevice} = $out;
    my $partitionLoopDeviceRoot = $self->{loopDevice};

    # insert them into the $self->{volumes}
    my $index = 1; # starts counting at 1
    foreach my $vol ( @{$self->{volumes}} ) {
        $vol->setDevice( $partitionLoopDeviceRoot . 'p' . $index );
        ++$index;
    }

    return $errors;
}

##
# Delete any created loop devices.
# return: number of errors
sub deleteLoopDevices {
    my $self = shift;

    trace( "Deleting loop devices" );

    my $errors = 0;

    my $out;
    if( UBOS::Utils::myexec( "losetup -d  '" . $self->{loopDevice} . "'", undef, \$out, \$out )) {
        error( "losetup -d error:", $out );
        ++$errors;
    }

    return $errors;
}

##
# Determine the boot loader device for this VolumeLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{image};
}

1;



