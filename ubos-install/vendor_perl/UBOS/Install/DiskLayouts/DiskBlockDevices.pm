#
# A disk layout using full disks. May contain boot sector.
#

package UBOS::Install::DiskLayouts::DiskBlockDevices;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( disks );

use UBOS::Install::AbstractDiskLayout;
use UBOS::Logging;

##
# Constructor
# $disksp: array of disk block devices
# $image: the disk image file to be partitioned
# $devicetable: device data
sub new {
    my $self        = shift;
    my $disksp      = shift;
    my $deviceTable = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $devicetable );
    
    $self->{disks} = $disksp;

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

        unless( exists( $data->{devices} )) {
            $data->{devices} = [];
        }
        foreach my $disk ( @{$self->{disks}} ) {
            push @{$data->{devices}}, "$disk$index"; # augment $self->{devicetable}
        }
    }
    $fdiskScript .= <<END;
w
END

    debug( 'fdisk script:', $fdiskScript );

    foreach my $disk ( @{$self->{disks}} ) {
        my $out;
        my $err;

        if( UBOS::Utils::myexec( "fdisk '" . $disk . "'", $fdiskScript, \$out, \$err )) {
            error( 'fdisk failed', $out, $err );
            ++$errors;
        }
        # Reread partition table
        UBOS::Utils::myexec( "partprobe '$disk'" ); 

    }
    return $errors;
}

##
# Determine the boot loader device for this DiskLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{disks}->[0];
}

1;
