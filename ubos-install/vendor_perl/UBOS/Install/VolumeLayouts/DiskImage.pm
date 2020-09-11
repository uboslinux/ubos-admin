#
# A disk image volume layout. Contains at least one partition.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::VolumeLayouts::DiskImage;

use base qw( UBOS::Install::AbstractVolumeLayout );
use fields qw( loopDevice );

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Utils;
use UBOS::Logging;

## Inherited constructor

##
# Format the configured disks.
sub createDisks {
    my $self = shift;

    error( 'FIXME createDisks' );
}

##
# Create any needed loop devices.
# return: number of errors
sub createLoopDevices {
    my $self = shift;

    trace( "Creating loop devices" );

    my $errors = 0;

    my $out;
    if( UBOS::Utils::myexec( "losetup --show --find --partscan '" . $self->{volumes}->[0] . "'", undef, \$out, \$out )) {
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
# Determine the boot loader device for this VolumeLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{volumes}->[0];
}

1;



