#
# A disk layout consiting of block devices referring to partitions,
# identifying a disk as the boot loader device
#

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
