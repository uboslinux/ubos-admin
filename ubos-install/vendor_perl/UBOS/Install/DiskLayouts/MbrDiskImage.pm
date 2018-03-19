#
# A Master Boot Record-based image disk layout. Contains at least
# one partition. May contain a boot sector.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::DiskLayouts::MbrDiskImage;

use base qw( UBOS::Install::AbstractDiskImage );
use fields qw();

use UBOS::Install::AbstractDiskImage;
use UBOS::Install::PartitionUtils;
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
    $self->SUPER::new( $image, $devicetable );

    return $self;
}

##
# Format the configured disks.
sub createDisks {
    my $self = shift;

    my $errors = 0;
    my $out;
    my $err;

    # determine disk size and how many sector are left over for the main partition
    my $remainingSectors;
    if( UBOS::Utils::myexec( "sgdisk --print '" . $self->{image} . "'", undef, \$out, \$out )) {
        error( 'sgdisk --print:', $out );
        ++$errors;

    } elsif( $out =~ m!First\s+usable\s+sector\s+is\s+(\d+),\s+last\s+usable\s+sector\s+is\s+(\d+)\s+!s )  {
        my $firstSector = $1;
        my $lastSector  = $2;
        my $remaining   = $lastSector-$firstSector;
        $remaining -= 2049; # first 2048 sectors, plus one sector more

        foreach my $data ( values %{$self->{devicetable}} ) {
            if( exists( $data->{size} )) {
                $remaining -= $data->{size};
            }
        }
        if( $remaining < 4096 * 1024 ) {
            fatal( 'Need at least 2GB for root partition:', $self->{image} );
        }
        $remainingSectors = $remaining;

    } else {
        fatal( 'Cannot determine size of disk' );
    }

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
        my $size;
        if( exists( $data->{size} )) {
            $size = $data->{size};
        } else {
            $size = $remainingSectors;
        }
        $fdiskScript .= <<END;
+$size
END
        if( exists( $data->{boot} )) {
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

    if( UBOS::Utils::myexec( "fdisk '" . $self->{image} . "'", $fdiskScript, \$out, \$err )) {
        error( 'fdisk failed', $out, $err );
        ++$errors;
    }

    return $errors;
}

1;
