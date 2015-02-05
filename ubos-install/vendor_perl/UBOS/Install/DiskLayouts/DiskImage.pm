#
# A DiskImage disk layout. Contains at least one partition. May contain
# boot sector.
#

package UBOS::Install::DiskLayouts::DiskImage;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( image );

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

    my $errors      = 0;
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

    # Reread partition table
    UBOS::Utils::myexec( "partprobe '" . $self->{image} . "'" ); 
        
    # Create loopback devices and figure out what they are
    debug( "Creating loop devices" );

    # -s: wait until created
    if( UBOS::Utils::myexec( "kpartx -a -s -v '" . $self->{image} . "'", undef, \$out, \$err )) {
        error( "kpartx error:", $err );
        ++$errors;
    }
    $out =~ m!/dev/(loop\d+)\s+!; # matches once for each partition, but that's okay
    my $partitionLoopDeviceRoot = "/dev/mapper/$1";

    foreach my $mountPath ( @mountPathIndexSequence ) {
        my $data = $self->{devicetable}->{$mountPath};
        
        $data->{devices} = [ $partitionLoopDeviceRoot . 'p' . $data->{index} ]; # augment $self->{devicetable}
    }
    return $errors;
}

##
# Unmount the previous mounts. Override because we need to take care of the
# loopback devices.
# $target: the target directory
sub umountDisks {
    my $self   = shift;
    my $target = shift;

    my $errors = $self->SUPER::umountDisks( $target );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "kpartx -d '" . $self->{image} . "'", undef, \$out, \$err )) {
        error( "kpartx error:", $out, $err );
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
