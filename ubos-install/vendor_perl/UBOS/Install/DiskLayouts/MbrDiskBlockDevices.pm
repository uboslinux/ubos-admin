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

    # determine disk size and how many sector are left over for the main partition
    my $remainingSectors = {};
    foreach my $disk ( @{$self->{disks}} ) {
        my $out;
        if( UBOS::Utils::myexec( "sgdisk --print '$disk'", undef, \$out, \$out )) {
            error( 'sgdisk --print:', $out );
            ++$errors;
        } elsif( $out =~ m!Disk.*:\s*(\d+)\s*sectors! )  {
            my $remaining = $1;
            $remaining -= 4096 * ( 0 + keys %{$self->{devicetable}} );
                # first 4096 sectors, for each partition
                # this is probably too much, but there seem to be alignment calculations with
                # the recommended start of a new partition

            foreach my $data ( values %{$self->{devicetable}} ) {
                if( exists( $data->{size} )) {
                    $remaining -= $data->{size};
                }
            }
            if( $remaining < 4096 * 1024 ) {
                fatal( 'Need at least 2GB for root partition:', $disk );
            }
            $remainingSectors->{$disk} = $remaining;
        } else {
            fatal( 'Cannot determine size of disk' );
        }
    }

    # zero out the beginning -- sometimes there are strange leftovers
    foreach my $disk ( @{$self->{disks}} ) {
        if( UBOS::Utils::myexec( "dd 'if=/dev/zero' 'of=$disk' bs=1M count=8 status=none" )) {
            ++$errors;
        }
    }

    foreach my $disk ( @{$self->{disks}} ) {
        my $out;
        my $err;

        my $fdiskScript = ''; # the disks may have slightly different sizes
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
            my $size;
            if( exists( $data->{size} )) {
                $size = $data->{size};
            } else {
                $size = $remainingSectors->{$disk};
            }
            $fdiskScript .= <<END;
+$size
END
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

        trace( 'fdisk script for', $disk, ':', $fdiskScript );

        if( UBOS::Utils::myexec( "fdisk '" . $disk . "'", $fdiskScript, \$out, \$err )) {
            error( 'fdisk failed', $out, $err );
            ++$errors;
        }
    }

    $errors += $self->resetDiskCaches();
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
