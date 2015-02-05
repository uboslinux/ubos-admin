# 
# Abstract superclass for disk layouts for an installation.
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
            $cmd .= join( ' ', @{$data->{devices}} );

            my $out;
            my $err;
            if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
                error( "$cmd error:", $err );
                ++$errors;
            }
        } else {
            foreach my $device ( @{$data->{devices}} ) {
                my $cmd = "mkfs.$fs '$device'";

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
        my $deviceTable = $self->{devicetable}->{$mountPoint};
        my $fs          = $deviceTable->{fs};
        my $device      = $deviceTable->{devices}->[0];

        unless( $fs ) {
            error( 'No fs given for', $mountPoint );
            next;
        }
        unless( $fs ) {
            error( 'No device known for', $mountPoint );
            next;
        }

        unless( -d "$target$mountPoint" ) {
            UBOS::Utils::mkdir( "$target$mountPoint" );
        }
        if( UBOS::Utils::myexec( "mount -t $fs '$device' '$target$mountPoint'" )) {
            ++$errors;
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
    foreach my $dir ( sort { length( $b ) <=> length( $a ) } keys %{$self->{devicetable}} ) {
        if( UBOS::Utils::myexec( "umount '$target$dir'" )) {
            ++$errors;
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

    my $script = '';
    if( $fs && $i ) {
        # This may have to be extended

        # Only specify $i if $i > 1; we generate partitions in sequence, and fdisk does not
        # ask which partition if number == 1
        if( 'vfat' eq $fs ) {
            if( $i > 1 ) {
                $script .= <<END;
t
$i
c
END
            } else {
                $script .= <<END;
t
c
END
            }
        }
    }
    return $script;
}

##
# Generate and save /etc/fstab
# $@mountPathSequence: the sequence of paths to mount
# %$partitions: map of paths to devices
# $targetDir: the path where the bootimage has been mounted
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
                UBOS::Utils::myexec( "sudo blkid -s UUID -o value '" . $devices[0] . "'", undef, \$uuid );
                $uuid =~ s!^\s+!!g;
                $uuid =~ s!\s+$!!g;

                my $passno = ( $mountPoint eq '/' ) ? 1 : 2;

                $fsTab .= "UUID=$uuid $mountPoint btrfs rw,relatime";
                # This may not be needed, if 'btrfs device scan' is done during boot
                # and if it is needed, this won't work, because @devices contains /dev/mapper/loopXpY or such
                # $fsTab .= join( '', map { ",device=$_" } @devices );
                $fsTab .= " $i $passno\n";

            } else {
                my $device = $deviceTable->{devices}->[0];

                my $uuid;
                UBOS::Utils::myexec( "sudo blkid -s UUID -o value '$device'", undef, \$uuid );
                $uuid =~ s!^\s+!!g;
                $uuid =~ s!\s+$!!g;

                my $passno = ( $mountPoint eq '/' ) ? 1 : 2;

                $fsTab .= <<FSTAB;
UUID=$uuid $mountPoint $fs rw,relatime $i $passno
FSTAB
            }
            ++$i;
        }
    }

    UBOS::Utils::saveFile( "$target/etc/fstab", $fsTab, 0644, 'root', 'root' );

    return 0;
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
        } elsif( -b $path ) {
            my $out;
            UBOS::Utils::myexec( "lsblk -o TYPE -n '$path'", undef, \$out );
            if( $out =~ m!disk! ) {
                $ret = 'disk';
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

1;
