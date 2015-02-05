#
# A disk layout consiting of block devices referring to partitions.
#

package UBOS::Install::DiskLayouts::PartitionBlockDevices;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields;

use UBOS::Install::AbstractDiskLayout;
use UBOS::Logging;

##
# Constructor
# $devicetable: device data
sub new {
    my $self        = shift;
    my $devicetable = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $devicetable );
    
    return $self;
}

1;
