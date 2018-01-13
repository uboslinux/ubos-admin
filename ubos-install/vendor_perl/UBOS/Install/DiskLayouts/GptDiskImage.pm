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
 
    # zero out the beginning does not seem to be advisable for GPT

    # first clear out everything
    if( UBOS::Utils::myexec( "sgdisk --zap-all '" . $self->{image} . "'", undef, \$out, \$out )) {
        error( 'sgdisk --zap-all:', $out );
        ++$errors;
    }

    # in sequence of index
    my @mountPathIndexSequence = sort { $self->{devicetable}->{$a}->{index} <=> $self->{devicetable}->{$b}->{index} } keys %{$self->{devicetable}};
    foreach my $mountPath ( @mountPathIndexSequence ) {
        my $data  = $self->{devicetable}->{$mountPath};
        my $index = $data->{index};

        my $startsector = '0'; # default
        if( exists( $data->{startsector} )) {
            $startsector = $data->{startsector};
        }

        my $size = '0'; #default
        if( exists( $data->{size} )) {
            $size  = '+' . $data->{size};
        }

        if( UBOS::Utils::myexec( "sgdisk '--new=$index:$startsector:$size' '" . $self->{image} . "'", undef, \$out, \$out )) {
            error( "sgdisk --new=$index:$startsector:$size " . $self->{image} . ':', $out );
            ++$errors;
        }
        
        $errors += UBOS::Install::PartitionUtils::changeGptPartitionType( $data->{gptparttype}, $index, $self->{image} );
    }

    if( UBOS::Utils::myexec( "partprobe " . $self->{image} )) {
        ++$errors;
    }

    return $errors;
}

1;
