#
# A disk layout using full disks with Master Boot Records. May contain boot sector.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::DiskLayouts::MbrDiskBlockDevices;

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

    # zero out the beginning -- sometimes there are strange leftovers
    foreach my $disk ( @{$self->{disks}} ) {
        if( UBOS::Utils::myexec( "dd 'if=/dev/zero' 'of=$disk' bs=1M count=8 status=none" )) {
            ++$errors;
        }
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

        $fdiskScript .= <<END;
n
p
$index

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
        if( exists( $data->{mbrboot} )) {
            $fdiskScript .= <<END;
a
END
        }

        $fdiskScript .= UBOS::Install::PartitionUtils::appendFdiskChangePartitionType( $data->{mbrparttype}, $index );
    }
    $fdiskScript .= <<END;
w
END

    trace( 'fdisk script:', $fdiskScript );

    foreach my $disk ( @{$self->{disks}} ) {
        my $out;
        my $err;

        if( UBOS::Utils::myexec( "fdisk '" . $disk . "'", $fdiskScript, \$out, \$err )) {
            error( 'fdisk failed', $out, $err );
            ++$errors;
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
