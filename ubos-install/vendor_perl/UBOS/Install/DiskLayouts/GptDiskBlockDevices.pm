#
# A disk layout using full disks with GUID Partition Table.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::DiskLayouts::GptDiskBlockDevices;

use base qw( UBOS::Install::AbstractDiskBlockDevices );
use fields qw();

use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::PartitionUtils;
use UBOS::Logging;

##
# Constructor
# $disksp: array of disk block devices
# $devicetable: device data
sub new {
    my $self        = shift;
    my $disksp      = shift;
    my $devicetable = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $disksp, $devicetable );

    return $self;
}

##
# Format the configured disks.
sub createDisks {
    my $self = shift;

    my $errors = 0;

    # zero out the beginning does not seem to be advisable for GPT

    # for all disks
    my $out;
    foreach my $disk ( @{$self->{disks}} ) {
        # first clear out everything
        if( UBOS::Utils::myexec( "sgdisk --zap-all '$disk'", undef, \$out, \$out )) {
            error( 'sgdisk --zap-all:', $out );
            ++$errors;
        }
    }

    foreach my $disk ( @{$self->{disks}} ) {
        my $out;
        my $err;

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

            if( UBOS::Utils::myexec( "sgdisk '--new=$index:$startsector:$size' '" . $disk . "'", undef, \$out, \$out )) {
                error( "sgdisk --new=$index:$startsector:$size " . $disk . ':', $out );
                ++$errors;
            }
            
            $errors += UBOS::Install::PartitionUtils::changeGptPartitionType( $data->{gptparttype}, $index, $disk );
        }
    }

    if( UBOS::Utils::myexec( "partprobe " . join( ' ', @{$self->{disks}} ))) {
        ++$errors;
    }

    $errors += $self->_augmentDeviceTableWithPartitions();

    return $errors;
}

##
# Determine the boot loader device for this DiskLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{disks}->[0];
}

1;
