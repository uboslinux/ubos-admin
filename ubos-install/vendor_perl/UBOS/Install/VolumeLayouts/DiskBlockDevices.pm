#
# A disk layout using full disks.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::VolumeLayouts::DiskBlockDevices;

use base qw( UBOS::Install::AbstractVolumeLayout );
use fields qw( labelType devices );

use UBOS::Utils;
use UBOS::Logging;

##
# Constructor
# $labelType: type of partition label as parted calls them, e.g. 'msdos' or 'gpt'
# $disksp: array of disk block devices
# $devicetable: device data
sub new {
    my $self        = shift;
    my $labelType   = shift;
    my $devicesP    = shift;
    my $volumesP    = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $volumesP );

    $self->{labelType} = $labelType;
    $self->{devices}   = $devicesP;

    return $self;
}

##
# Create the configured disks.
sub createDisks {
    my $self = shift;


    error( 'FIXME createDisks' );
}

##
# Determine the boot loader device for this VolumeLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{devices}->[0];
}

##
# Assuming that the partition names are simply the disk names with an integer
# appended turned out to be too simplistic. So let's ask the system.
# Maybe there is a way of making this simpler, but if so, I can't see it
# return: number of errors
sub _augmentDeviceTableWithPartitions {
    my $self = shift;

    my $errors = 0;
    foreach my $dev ( @{$self->{devices}} ) {
        my $shortDisk = $dev;
        $shortDisk =~ s!^.+/!!; # greedy

        my $out;
        if( UBOS::Utils::myexec( "lsblk --json -o NAME $dev", undef, \$out )) {
            ++$errors;

        } else {
            my $json = UBOS::Utils::readJsonFromString( $out );

            foreach my $child ( @{$json->{blockdevices}->[0]->{children}} ) {
                my $childName = $child->{name};

                # in sequence of index
                my @mountPathIndexSequence = sort { $self->{devicetable}->{$a}->{index} <=> $self->{devicetable}->{$b}->{index} } keys %{$self->{devicetable}};
                foreach my $mountPath ( @mountPathIndexSequence ) {
                    my $data  = $self->{devicetable}->{$mountPath};
                    my $index = $data->{index};

                    my $regex = $shortDisk . 'p?' . $index;
                    if( $childName =~ m!^$regex$! ) {
                        unless( exists( $data->{devices} )) {
                            $data->{devices} = [];
                        }

                        push @{$data->{devices}}, "/dev/$childName";
                    }
                }
            }
        }
    }

    return $errors;
}

1;
