#
# A disk layout using full disks.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::AbstractDiskBlockDevices;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( disks );

use UBOS::Utils;

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
    $self->SUPER::new( $devicetable );

    $self->{disks} = $disksp;

    return $self;
}

##
# Assuming that the partition names are simply the disk names with an integer
# appended turned out to be too simplistic. So let's ask the system.
# Maybe there is a way of making this simpler, but if so, I can't see it
# return: number of errors
sub _augmentDeviceTableWithPartitions {
    my $self = shift;

    my $errors = 0;
    foreach my $disk ( @{$self->{disks}} ) {
        my $shortDisk = $disk;
        $shortDisk =~ s!^.+/!!; # greedy

        my $out;
        if( UBOS::Utils::myexec( "lsblk --json -o NAME $disk", undef, \$out )) {
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

                        push @{$data->{devices}}, "/dev/$childName"; # augment $self->{devicetable}
                    }
                }
            }
        }
    }

    return $errors;
}

1;
