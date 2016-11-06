#
# A DiskImage disk layout. Contains at least one partition. May contain
# boot sector.
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

package UBOS::Install::DiskLayouts::DiskImage;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( image loopDevice );

use UBOS::Install::AbstractDiskLayout;
use UBOS::Logging;

##
# Constructor
# $image: the disk image file to be partitioned
# $devicetable: device data
sub new {
    my $self        = shift;
    my $image       = shift;
    my $devicetable = shift;

    if( keys %$devicetable > 4 ) {
        fatal( 'Cannot currently handle devicetable for more than 4 devices; need primary partitions' );
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $devicetable );
    
    $self->{image} = $image;

    return $self;
}

##
# Format the configured disks.
sub createDisks {
    my $self = shift;

    my $errors = 0;

    # zero out the beginning -- sometimes there are strange leftovers
    if( UBOS::Utils::myexec( "dd 'if=/dev/zero' 'of=" . $self->{image} . "' bs=1M count=8 conv=notrunc status=none" )) {
        ++$errors;
    }

    my $fdiskScript = '';

    $fdiskScript .= <<END; # first clear out everything
o
END

    # in sequence of index
    my @mountPathIndexSequence = sort { $self->{devicetable}->{$a}->{index} <=> $self->{devicetable}->{$b}->{index} } keys %{$self->{devicetable}};
    foreach my $mountPath ( @mountPathIndexSequence ) {
        my $data  = $self->{devicetable}->{$mountPath};
        my $index = $data->{index};
        my $startsector = ''; # default
        if( exists( $data->{startsector} )) {
            $startsector = $data->{startsector};
        }

        $fdiskScript .= <<END;
n
p
$index
$startsector
END
        if( exists( $data->{size} )) {
            my $size  = $data->{size};
            $fdiskScript .= <<END;
+$size
END
        } else {
            $fdiskScript .= <<END;

END
        }
        if( exists( $data->{boot} )) {
            $fdiskScript .= <<END;
a
END
        }

        $fdiskScript .= $self->appendFdiskChangePartitionType( $data->{fs}, $index );
    }
    $fdiskScript .= <<END;
w
END

    my $out;
    my $err;

    debug( 'fdisk script:', $fdiskScript );

    if( UBOS::Utils::myexec( "fdisk '" . $self->{image} . "'", $fdiskScript, \$out, \$err )) {
        error( 'fdisk failed', $out, $err );
        ++$errors;
    }

    return $errors;
}

##
# Create any needed loop devices.
# return: number of errors
sub createLoopDevices {
    my $self = shift;

    debug( "Creating loop devices" );

    my $errors = 0;

    my $out;
    if( UBOS::Utils::myexec( "losetup --show --find --partscan '" . $self->{image} . "'", undef, \$out, \$out )) {
        error( "losetup -a error:", $out );
        ++$errors;
    }
    $out =~ m!/dev/(loop\d+)\s+!; # matches once for each partition, but that's okay
    $self->{loopDevice} = "/dev/loop$1";
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

    debug( "Deleting loop devices" );

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
