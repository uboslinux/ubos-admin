#
# A disk layout using full disks. May contain boot sector.
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

package UBOS::Install::DiskLayouts::DiskBlockDevices;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( disks );

use UBOS::Install::AbstractDiskLayout;
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
    $self->SUPER::new( $devicetable );

    $self->{disks} = $disksp;

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

    trace( 'fdisk script:', $fdiskScript );

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
