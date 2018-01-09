#
# A disk layout using full disks.
#
# This file is part of ubos-install.
# (C) 2012-2015 Indie Computing Corp.
#
# ubos-install is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-install is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-install.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Install::AbstractDiskBlockDevices;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( disks );

use UBOS::Install::DiskLayouts::MbrDiskBlockDevices;
use UBOS::Install::DiskLayouts::GptDiskBlockDevices;
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
