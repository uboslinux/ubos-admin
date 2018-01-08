#
# A GUID Partition Table-based image disk layout. Contains at least
# one partition.
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

package UBOS::Install::DiskLayouts::GptDiskImage;

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
 
    # zero out the beginning does not seem to be advisable for GPT

    # first clear out everything
    if( UBOS::Utils::myexec( "sgdisk --zap-all '" . $self->{image} . "'", undef, \$out, \$out )) {
        error( 'sgdisk --zap-all:', $out );
        ++$errors;
    }

    # in sequence of index
    my @mountPathIndexSequence = sort { $self->{devicetable}->{$a}->{index} <=> $self->{devicetable}->{$b}->{index} } keys %{$self->{devicetable}};
    foreach my $mountPath ( @mountPathIndexSequence ) {
        my $data  = $self->{devicetable}->{$mountPath};
        my $index = $data->{index};

        my $startsector = '0'; # default
        if( exists( $data->{startsector} )) {
            $startsector = $data->{startsector};
        }

        my $size = '0'; #default
        if( exists( $data->{size} )) {
            $size  = '+' . $data->{size};
        }

        if( UBOS::Utils::myexec( "sgdisk '--new=$index:$startsector:$size' '" . $self->{image} . "'", undef, \$out, \$out )) {
            error( "sgdisk --new=$index:$startsector:$size " . $self->{image} . ':', $out );
            ++$errors;
        }
        
        $errors += UBOS::Install::PartitionUtils::changeGptPartitionType( $data->{gptparttype}, $index, $self->{image} );
    }

    if( UBOS::Utils::myexec( "partprobe " . $self->{image} )) {
        ++$errors;
    }

    return $errors;
}

1;
