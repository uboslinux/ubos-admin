#
# A disk layout using full disks.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::VolumeLayouts::DiskBlockDevices;

use base qw( UBOS::Install::AbstractVolumeLayout );
use fields qw( partitioningScheme devices startOffset alignment );

use UBOS::Utils;
use UBOS::Logging;

##
# Constructor
sub new {
    my $self               = shift;
    my $partitioningScheme = shift;
    my $devicesP           = shift;
    my $volumesP           = shift;
    my $startOffset        = shift || 2048 * 512;
    my $alignment          = shift || 'minimal';

    if( $partitioningScheme ne 'gpt' && $partitioningScheme ne 'mbr' && $partitioningScheme ne 'gpt+mbr' ) {
        fatal( 'Invalid partitioning scheme:', $partitioningScheme );
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $volumesP );

    $self->{partitioningScheme} = $partitioningScheme;
    $self->{devices}            = $devicesP;
    $self->{startOffset}        = $startOffset;
    $self->{alignment}          = $alignment;

    return $self;
}

##
# Create the configured volumes.
sub createVolumes {
    my $self = shift;

    my $errors = 0;

    trace( 'DiskBlockDevices::createVolumes', $self->{devices} );

    foreach my $dev ( @{$self->{devices}} ) {
        $errors += $self->formatSingleDisk( $dev, $self->{partitioningScheme}, $self->{startOffset}, $self->{alignment} );
    }
    $errors += $self->_augmentDeviceTableWithPartitions();

    return $errors;
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

    my $isFirstDevice = 1;
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

                my $index = 1; # starts with 1
                foreach my $vol( @{$self->{volumes}} ) {

                    my $regex = $shortDisk . 'p?' . $index;
                    if( $childName =~ m!^$regex$! ) {
                        if( $isFirstDevice ) {
                            $vol->setDevice( "/dev/$childName" );
                        } else {
                            $vol->addDevice( "/dev/$childName" );
                        }
                    }
                    ++$index;
                }
            }
        }
        $isFirstDevice = 0;
    }

    return $errors;
}

1;
