#
# A GUID Partition Table-based image disk layout. Contains at least
# one partition.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::DiskLayouts::GptDiskImage;

use base qw( UBOS::Install::AbstractDiskImage );
use fields qw();

use UBOS::Install::AbstractDiskImage;
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::PartitionUtils;
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
    $self->SUPER::new( $image, $devicetable );

    return $self;
}

##
# Format the configured disks.
sub createDisks {
    my $self = shift;

    my $errors = 0;
    my $out;
    my $err;

    trace( 'GptDiskImage::createDisks' );

    # Clear everything out
    if( UBOS::Utils::myexec( "sgdisk --zap-all '" . $self->{image} . "'", undef, \$out, \$out )) {
        error( 'sgdisk --zap-all:', $out );
        ++$errors;
    }

    # determine disk size and how many sector are left over for the main partition
    my $remainingSectors;
    if( UBOS::Utils::myexec( "sgdisk --print '" . $self->{image} . "'", undef, \$out, \$out )) {
        fatal( 'Cannot determine size of disk: sgdisk --print:', $out );

    } elsif( $out =~ m!First\s+usable\s+sector\s+is\s+(\d+),\s+last\s+usable\s+sector\s+is\s+(\d+)\s+!s )  {
        my $firstSector = $1;
        my $lastSector  = $2;
        my $remaining   = $lastSector-$firstSector;
        $remaining -= 4096 * ( 0 + keys %{$self->{devicetable}} );
            # first 4096 sectors, for each partition
            # this is probably too much, but there seem to be alignment calculations with
            # the recommended start of a new partition

        foreach my $data ( values %{$self->{devicetable}} ) {
            if( exists( $data->{size} )) {
                $remaining -= $data->{size};
            }
        }
        if( $remaining < 4096 * 1024 ) {
            fatal( 'Need at least 2GB for root partition:', $self->{image} );
        }
        $remainingSectors = $remaining;

    } else {
        fatal( 'Cannot determine size of disk' );
    }

    # in sequence of index
    my @mountPathIndexSequence = sort { $self->{devicetable}->{$a}->{index} <=> $self->{devicetable}->{$b}->{index} } keys %{$self->{devicetable}};
    foreach my $mountPath ( @mountPathIndexSequence ) {
        my $data  = $self->{devicetable}->{$mountPath};
        my $index = $data->{index};

        my $startsector = ''; # default
        if( exists( $data->{startsector} )) {
            $startsector = $data->{startsector};
        }

        my $size;
        if( exists( $data->{size} )) {
            $size = '+' . $data->{size};
        } else {
            $size = '+' . $remainingSectors;
        }

        if( UBOS::Utils::myexec( "sgdisk '--new=$index:$startsector:$size' '" . $self->{image} . "'", undef, \$out, \$out )) {
            error( "sgdisk --new=$index:$startsector:$size " . $self->{image} . ':', $out );
            ++$errors;
        }

        $errors += UBOS::Install::PartitionUtils::changeGptPartitionType( $data->{gptparttype}, $index, $self->{image} );
    }

    $errors += UBOS::Install::AbstractDiskLayout::resetDiskCaches();

    return $errors;
}

1;
