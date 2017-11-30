#
# A disk layout using full disks with GUID Partition Table.
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

package UBOS::Install::DiskLayouts::GptDiskBlockDevices;

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

    # zero out the beginning does not seem to be advisable for GPT

    # for all disks
    my $out;
    foreach my $disk ( @{$self->{disks}} ) {
        # first clear out everything
        if( UBOS::Utils::myexec( "sgdisk --zap-all '$disk'", undef, \$out, \$out )) {
            error( 'sgdisk --zap-all:', $out );
            ++$errors;
        }
    }

    foreach my $disk ( @{$self->{disks}} ) {
        my $out;
        my $err;

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

            if( UBOS::Utils::myexec( "sgdisk '--new=$index:$startsector:$size' '" . $disk . "'", undef, \$out, \$out )) {
                error( "sgdisk --new=$index:$startsector:$size " . $disk . ':', $out );
                ++$errors;
            }
            
            $errors += UBOS::Install::PartitionUtils::changeGptPartitionType( $data->{gptparttype}, $index, $disk );

            unless( exists( $data->{devices} )) {
                $data->{devices} = [];
            }

            push @{$data->{devices}}, "$disk$index"; # augment $self->{devicetable}
        }
    }

    if( UBOS::Utils::myexec( "partprobe" )) {
        ++$errors;
    }

    return $errors;
}

##
# Ensure any special directories that this DiskLayout may need
# $target: the target directory
# return: number of errors
sub ensureSpecialDirectories {
    my $self   = shift;
    my $target = shift;

    trace( 'GptDiskBlockDevices::ensureSpecialDirectories', $target );

    unless( -d "$target/boot/EFI" ) {
        UBOS::Utils::mkdir( "$target/boot/EFI" );
    }
    return 0;
}

##
# Determine the boot loader device for this DiskLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return $self->{disks}->[0];
}

1;
