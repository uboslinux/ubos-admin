# 
# Abstract superclass for disk layouts for an installation.
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

package UBOS::Install::AbstractDiskLayout;

use fields qw( devicetable );

use UBOS::Logging;
use UBOS::Utils;

##
# Constructor for subclasses only
# $devicetable: information about the layout
sub new {
    my $self        = shift;
    my $devicetable = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    $self->{devicetable} = $devicetable;

    debug( 'Using disk layout', ref( $self ));

    return $self;
}

##
# Format the configured disks.
sub createDisks {
    my $self = shift;

    # no op, may be overridden
    return 0;
}

##
# Format the configured disks.
sub formatDisks {
    my $self = shift;

    my $errors = 0;

    debug( 'Formatting file systems' );

    foreach my $mountPath ( keys %{$self->{devicetable}} ) {
        my $data = $self->{devicetable}->{$mountPath};
        my $fs   = $data->{fs};

        if( 'btrfs' eq $fs ) {
            my $cmd = 'mkfs.btrfs -f ';
            if( @{$data->{devices}} > 1 ) {
                $cmd .= '-m raid1 -d raid1 ';
            }
            if( exists( $data->{mkfsflags} )) {
                $cmd .= $data->{mkfsflags} . ' ';
            }
            $cmd .= join( ' ', @{$data->{devices}} );

            my $out;
            my $err;
            if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
                error( "$cmd error:", $err );
                ++$errors;
            }

        } elsif( 'swap' eq $fs ) {
            foreach my $dev ( @{$data->{devices}} ) {
                my $out;
                my $err;
                my $cmd = "mkswap '$dev'";
                if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
                    error( "$cmd error:", $err );
                    ++$errors;
                }
            }

        } else {
            foreach my $device ( @{$data->{devices}} ) {
                my $cmd = "mkfs.$fs";
                if( exists( $data->{mkfsflags} )) {
                    $cmd .= ' ' . $data->{mkfsflags};
                }
                $cmd .= " '$device'";

                my $out;
                my $err;
                if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
                    error( "$cmd error:", $err );
                    ++$errors;
                }
            }
        }
    }
    return $errors;
}

##
# Mount this disk layout at the specified target directory
# $target: the target directory
sub mountDisks {
    my $self   = shift;
    my $target = shift;

    debug( 'Mounting disks' );

    my $errors = 0;
    # shortest first
    foreach my $mountPoint ( sort { length( $a ) <=> length( $b ) } keys %{$self->{devicetable}} ) {
        my $entry   = $self->{devicetable}->{$mountPoint};
        my $fs      = $entry->{fs};
        my @devices = @{$entry->{devices}};

        unless( $fs ) {
            error( 'No fs given for', $mountPoint );
            ++$errors;
            next;
        }
        unless( @devices ) {
            error( 'No device known for', $mountPoint );
            ++$errors;
            next;
        }

        unless( -d "$target$mountPoint" ) {
            UBOS::Utils::mkdir( "$target$mountPoint" );
        }
        if( $fs eq 'swap' ) {
            foreach my $device ( @devices ) {
                if( UBOS::Utils::myexec( "swapon '$device'" )) {
                    ++$errors;
                }
            }
        } else {
            my $firstDevice = $devices[0];
            if( UBOS::Utils::myexec( "mount -t $fs '$firstDevice' '$target$mountPoint'" )) {
                ++$errors;
            }
        }
    }
    return $errors;
}

##
# Unmount the previous mounts
# $target: the target directory
sub umountDisks {
    my $self   = shift;
    my $target = shift;

    debug( 'Unmounting disks' );

    my $errors = 0;
    # longest first
    foreach my $mountPoint ( sort { length( $b ) <=> length( $a ) } keys %{$self->{devicetable}} ) {
        my $entry  = $self->{devicetable}->{$mountPoint};
        my $fs     = $entry->{fs};

        if( 'swap' eq $fs ) {
            foreach my $device ( @{$entry->{devices}} ) {
                if( UBOS::Utils::myexec( "swapoff '$device'" )) {
                    ++$errors;
                }
            }
        } else {
            if( UBOS::Utils::myexec( "umount '$target$mountPoint'" )) {
                ++$errors;
            }
        }
    }
    return $errors;
}

##
# Create an fdisk script fragment to change a partition type
# $fs: desired file system type
# $i: partition number
sub appendFdiskChangePartitionType {
    my $self = shift;
    my $fs   = shift;
    my $i    = shift;

    my $typesToCode = {
        'vfat' => 'c',
        'swap' => '82'
        # This may have to be extended
    };
    my $script = '';
    if( $fs && $i ) {

        # Only specify $i if $i > 1; we generate partitions in sequence, and fdisk does not
        # ask which partition if number == 1
        my $code = $typesToCode->{$fs};
        if( $code ) {
            if( $i > 1 ) {
                $script .= <<END;
t
$i
$code
END
            } else {
                $script .= <<END;
t
$code
END
            }
        }
            
    }
    return $script;
}

##
# Create btrfs subvolumes if needed
# $target: the path where the bootimage has been mounted
# return: number of errors
sub createSubvols {
    my $self   = shift;
    my $target = shift;

    my $errors = 0;

    my $deviceTable = $self->{devicetable}->{'/'};
    if( 'btrfs' eq $deviceTable->{fs} ) {
        # create separate subvol for /var/log, so snapper does not roll back the logs
        unless( -d "$target/var" ) {
            UBOS::Utils::mkdirDashP( "$target/var" );
        }
        my $out;
        if( UBOS::Utils::myexec( "btrfs subvol create '$target/var/log'", undef, \$out, \$out )) {
            error( "Failed to create btrfs subvol for '$target/var/log':", $out );
            ++$errors;
        }
    }
            
    return $errors;
}
##
# Generate and save /etc/fstab
# $@mountPathSequence: the sequence of paths to mount
# %$partitions: map of paths to devices
# $target: the path where the bootimage has been mounted
# return: number of errors
sub saveFstab {
    my $self   = shift;
    my $target = shift;
    
    my $fsTab = <<FSTAB;
#
# /etc/fstab: static file system information
#
# <file system> <dir>	<type>	<options>	<dump>	<pass>

FSTAB

    if( defined( $self->{devicetable} )) {
        my $i=0;

        # shortest first
        foreach my $mountPoint ( sort { length( $a ) <=> length( $b ) } keys %{$self->{devicetable}} ) {
            my $deviceTable = $self->{devicetable}->{$mountPoint};
            my $fs          = $deviceTable->{fs};

            if( 'btrfs' eq $fs ) {
                my @devices = @{$deviceTable->{devices}};

                # Take blkid from first device
                my $uuid;
                UBOS::Utils::myexec( "blkid -s UUID -o value '" . $devices[0] . "'", undef, \$uuid );
                $uuid =~ s!^\s+!!g;
                $uuid =~ s!\s+$!!g;

                info( 'uuid of device', $devices[0], 'to be mounted at', $mountPoint, 'is', $uuid );

                my $passno = ( $mountPoint eq '/' ) ? 1 : 2;

                $fsTab .= "UUID=$uuid $mountPoint btrfs rw,relatime";
                # This may not be needed, if 'btrfs device scan' is done during boot
                # and if it is needed, this won't work, because @devices contains /dev/mapper/loopXpY or such
                # $fsTab .= join( '', map { ",device=$_" } @devices );
                $fsTab .= " $i $passno\n";

            } elsif( 'swap' eq $fs ) {
                my @devices = @{$deviceTable->{devices}};

                foreach my $device ( @devices ) {
                    my $uuid;
                    UBOS::Utils::myexec( "blkid -s UUID -o value '" . $device . "'", undef, \$uuid );
                    $uuid =~ s!^\s+!!g;
                    $uuid =~ s!\s+$!!g;

                    info( 'uuid of swap device', $device, 'is', $uuid );

                    $fsTab .= "UUID=$uuid none swap defaults 0 0\n";
                }

            } else {
                my $device = $deviceTable->{devices}->[0];

                my $uuid;
                UBOS::Utils::myexec( "blkid -s UUID -o value '$device'", undef, \$uuid );
                $uuid =~ s!^\s+!!g;
                $uuid =~ s!\s+$!!g;

                my $passno = ( $mountPoint eq '/' ) ? 1 : 2;

                $fsTab .= "UUID=$uuid $mountPoint $fs rw,relatime $i $passno\n";
            }
            ++$i;
        }
    }

    UBOS::Utils::saveFile( "$target/etc/fstab", $fsTab, 0644, 'root', 'root' );

    return 0;
}

##
# Obtain the btrfs device mount points that snapper should manage.
# return: list of mount points
sub snapperBtrfsMountPoints {
    my $self = shift;

    my @ret;
    if( defined( $self->{devicetable} )) {
        foreach my $mountPoint ( keys %{$self->{devicetable}} ) {
            my $deviceTable = $self->{devicetable}->{$mountPoint};
            my $fs          = $deviceTable->{fs};

            if( 'btrfs' eq $fs ) {
                push @ret, $mountPoint;
            }
        }
    }
    return @ret;
}

# cache found device types
my %deviceTypes = ();

##
# Helper method to determine whether a given device is a file, a disk, or a partition
# $path: the file's name
sub _determineDeviceType {
    my $path = shift;

    my $ret = $deviceTypes{$path};
    unless( $ret ) {
        $ret = 'unknown'; # default
        if( ! -e $path ) {
            $ret = 'missing';
        } elsif( -f $path ) {
            $ret = 'file';
        } elsif( -d $path ) {
            $ret = 'directory';
        } elsif( -b $path ) {
            my $out;
            UBOS::Utils::myexec( "lsblk -o TYPE -n '$path'", undef, \$out );
            if( $out =~ m!disk! ) {
                $ret = 'disk';
            } elsif( $out =~ m!loop! ) {
                $ret = 'loop';
            } elsif( $out =~ m!part! ) {
                $ret = 'part';
            }
        }
        if( 'unknown' eq $ret ) {
            warning( 'Cannot determine type of device:', $path );
        }
        $deviceTypes{$path} = $ret;
    }
    return $ret;
}

##
# Helper method to determine whether a given device is a file
# $path: the file's name
sub isFile {
    my $path = shift;

    my $type = _determineDeviceType( $path );
    return $type eq 'file';
}

##
# Helper method to determine whether a given device is a disk
# $path: the file's name
sub isDisk {
    my $path = shift;

    my $type = _determineDeviceType( $path );
    return $type eq 'disk';
}

##
# Helper method to determine whether a given device is a partition
# $path: the file's name
sub isPartition {
    my $path = shift;

    my $type = _determineDeviceType( $path );
    return $type eq 'part';
}

##
# Helper method to determine whether a given device is a disk
# $path: the file's name
sub isBlockDevice {
    my $path = shift;

    my $type = _determineDeviceType( $path );
    return $type eq 'disk' || $type eq 'part';
}

##
# Helper method to determine whether a given device is a loop device
# $path: the file's name
sub isLoopDevice {
    my $path = shift;

    my $type = _determineDeviceType( $path );
    return $type eq 'loop';
}

1;
