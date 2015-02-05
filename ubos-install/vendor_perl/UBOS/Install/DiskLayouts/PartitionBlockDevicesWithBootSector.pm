#
# A disk layout consiting of block devices referring to partitions,
# identifying a disk as the boot loader device
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

package UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector;

use base   qw( UBOS::Install::DiskLayouts::PartitionBlockDevices );
use fields qw( bootloaderdevice );

use UBOS::Logging;

##
# Constructor
# $bootloaderdevice: the device to write the bootloader to
# $devicetable: device data
sub new {
    my $self             = shift;
    my $bootloaderdevice = shift;
    my $devicetable      = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $devicetable );

    $self->{bootloaderdevice} = $bootloaderdevice;

    return $self;
}

##
# Determine the boot loader device for this DiskLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{bootloaderdevice};
}

1;
