#
# Abstract superclass for disk images.
#
# This file is part of ubos-install.
# (C) 2012-2017 Indie Computing Corp.
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

package UBOS::Install::AbstractDiskImage;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( image loopDevice );

use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::MbrDiskImage;
use UBOS::Install::DiskLayouts::GptDiskImage;
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
