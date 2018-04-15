#
# Abstract superclass for disk images.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::AbstractDiskImage;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( image loopDevice );

use UBOS::Install::AbstractDiskLayout;
use UBOS::Logging;

##
# Constructor
# $image: the disk image file to be partitioned
# $devicetable: device data
sub new {
    my $self        = shift;
    my $image       = shift;
    my $devicetable = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $devicetable );

    $self->{image} = $image;

    return $self;
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

    # in sequence of index
    my @mountPathIndexSequence = sort { $self->{devicetable}->{$a}->{index} <=> $self->{devicetable}->{$b}->{index} } keys %{$self->{devicetable}};
    foreach my $mountPath ( @mountPathIndexSequence ) {
        my $data = $self->{devicetable}->{$mountPath};

        $data->{devices} = [ $partitionLoopDeviceRoot . 'p' . $data->{index} ]; # augment $self->{devicetable}
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
# Determine the boot loader device for this DiskLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{image};
}

1;
