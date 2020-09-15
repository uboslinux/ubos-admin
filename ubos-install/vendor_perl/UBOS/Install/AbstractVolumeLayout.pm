#
# Abstract superclass for volume layouts for an installation.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::AbstractVolumeLayout;

use fields qw( volumes );

use Cwd 'abs_path';
use UBOS::Logging;
use UBOS::Utils;

my $_pathFacts = {}; # cache of facts about particular paths, hash of <string,hash>
my $_lsBlk     = undef; # cache of lsblk output

##
# Constructor
sub new {
    my $self    = shift;
    my $volumes = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{volumes} = $volumes;

    return $self;
}

##
# Create the configured volumes.
sub createVolumes {
    my $self = shift;

    # no op, may be overridden
    return 0;
}

##
# Helper method to format a single disk device or image file.
# $dev: the disk device (e.g. /dev/sdc) or disk (e.g. /tmp/diskfile)
# $partitioningScheme: the partitioning scheme to use
# $startOffset: the starting offset for the first partition
# $alignment: the gparted alignment to use
# return: number of errors
sub formatSingleDisk {
    my $self               = shift;
    my $dev                = shift;
    my $partitioningScheme = shift;
    my $startOffset        = shift;
    my $alignment          = shift;

    my $errors = 0;

    my $out;
    my $err;

    trace( 'AbstractVolumeLayout::formatSingleDisk', $dev, $partitioningScheme );

    # Clear everything out
    if( UBOS::Utils::myexec( "sgdisk --zap-all '" . $dev . "'", undef, \$out, \$out )) {
        error( 'sgdisk --zap-all:', $out );
        ++$errors;
    }

    my $script  = 'mklabel'; # note there are no \n or any other separators between commands
    if( $partitioningScheme eq 'mbr' ) {
        $script .= ' msdos';
    } else {
        $script .= ' gpt';
    }

    my $partType = '';
    if( $partitioningScheme eq 'mbr' ) {
        if( @{$self->{volumes}} <= 4 ) {
            $partType = 'primary';
        } else {
            $partType = 'logical';
        }
    }

    my $currentStart = $startOffset;
    my $currentEnd   = -1024 * 1024; # keep a bit of space, some disks don't like -512B = last sector

    # traverse forward in vol's until we find a partition with unspecified size
    # then traverse backward from the end until we find a partition with unspecified size
    # then create the unspecified partition in the middle

    my $indexFromFront = 0; # index into $self->{volumes}, so we know where we are
    foreach my $vol ( @{$self->{volumes}} ) {

        my $partSize = $vol->getSize();
        unless( $partSize ) {
            last;
        }

        my $partLabel = $vol->getLabel();
        my $partFs    = $vol->getPartedFs();
        my $nextStart = $currentStart + $partSize;

        # mkpart [part-type name fs-type] start end
        $script .= " mkpart";

        if( $partType ) {
            $script .= " $partType";
        }
        if( $partitioningScheme ne 'mbr' && $partLabel ) {
            $script .= " $partLabel";
        }
        if( $partFs ) {
            $script .= " $partFs";
        }

        $script .= ' ' . $currentStart . 'B';
        $script .= ' ' . $nextStart . 'B';

        $currentStart = $nextStart + 512; # next sector
        ++$indexFromFront;
    }

    my $indexFromBack = @{$self->{volumes}} - 1;
    my $scriptTrailer = ''; # will be appended at the end; otherwise partitions out of sequence
    foreach my $vol ( reverse @{$self->{volumes}} ) {

        if( $indexFromBack < $indexFromFront ) {
            last; # no part had unspecified size
        }

        my $partSize = $vol->getSize();
        unless( $partSize ) {
            last;
        }

        my $partLabel = $vol->getLabel();
        my $partFs    = $vol->getPartedFs();
        my $nextEnd   = $currentEnd - $partSize;

        # mkpart [part-type name fs-type] start end
        $scriptTrailer .= " mkpart";

        if( $partType ) {
            $scriptTrailer .= " $partType";
        }
        if( $partitioningScheme ne 'mbr' && $partLabel ) {
            $scriptTrailer .= " $partLabel";
        }
        if( $partFs ) {
            $scriptTrailer .= " $partFs";
        }

        $scriptTrailer .= ' ' . $nextEnd . 'B';
        $scriptTrailer .= ' ' . $currentEnd . 'B';

        $currentEnd = $nextEnd - 512; # previous sector
        --$indexFromBack;
    }
    if( $indexFromFront < $indexFromBack ) {
        fatal( 'More than one partition has unspecified size, cannot continue' );
    }
    if( $indexFromFront == $indexFromBack ) {
        # exactly one has unspecified size

        my $vol       = $self->{volumes}->[$indexFromFront];
        my $partLabel = $vol->getLabel();
        my $partFs    = $vol->getPartedFs();

        # mkpart [part-type name fs-type] start end
        $script .= " mkpart";

        if( $partType ) {
            $script .= " $partType";
        }
        if( $partitioningScheme ne 'mbr' && $partLabel ) {
            $script .= " $partLabel";
        }
        if( $partFs ) {
            $script .= " $partFs";
        }
        $script .= ' ' . $currentStart . 'B';
        $script .= ' ' . $currentEnd . 'B';
    }
    $script .= $scriptTrailer;

    # Set flags
    for( my $i=0 ; $i < @{$self->{volumes}} ; ++$i ) {
        my $vol    = $self->{volumes}->[$i];
        my $number = $i+1;

        my @flags = $vol->getPartedFlags();
        foreach my $flag ( @flags ) {
            $script .= " set $number $flag on";
        }
    }

    my $cmd  = 'parted';
    $cmd    .= " --align '" . $alignment . "'";
    $cmd    .= " --script";
    $cmd    .= " '" . $dev . "'";
    $cmd    .= " -- " . $script;

    if( UBOS::Utils::myexec( $cmd, undef, \$out, \$out )) {
       error( 'parted failed:', $out );
       ++$errors;
    }

    $errors += resetDiskCaches();

    return $errors;
}

##
# Format the configured volumes.
# return: number of errors
sub formatVolumes {
    my $self = shift;

    my $errors = 0;

    trace( 'Checking that none of the devices are currently mounted' );

    foreach my $vol ( @{ $self->{volumes}} ) {
        if( isMountedOrChildMounted( $vol )) {
            error( 'Cannot install to mounted device:', $vol );
            ++$errors;
        }
    }

    trace( 'Formatting file systems' );

    foreach my $vol ( $self->getVolumesByMountPath()) {
        $errors += $vol->formatVolume();
    }

    $errors += resetDiskCaches();

    DONE:
    return $errors;
}

##
# Create any needed loop devices. By default, this does nothing.
# return: number of errors
sub createLoopDevices {
    my $self = shift;

    return 0;
}

##
# Delete any created loop devices. By default, this does nothing.
# return: number of errors
sub deleteLoopDevices {
    my $self = shift;

    return 0;
}

##
# Mount this volume layout at the specified target directory
# $installer: the Installer
# return: number of errors
sub mountVolumes{
    my $self      = shift;
    my $installer = shift;

    trace( 'Mounting volumes' );

    my $target = $installer->getTarget();
    my $errors = 0;

    # longest first
    foreach my $vol ( $self->getVolumesByMountPath() ) {

        my $fs = $vol->getFs();
        unless( $fs ) {
            # no need to mount
            next;
        }

        my $mountPoint = $vol->getMountPoint();

        # don't swapon swap devices during install
        if( $mountPoint ) {

            unless( -d "$target$mountPoint" ) {
                UBOS::Utils::mkdir( "$target$mountPoint" );
            }

            my $firstDevice = ( $vol->getDeviceNames() )[0];

            debugAndSuspend( 'Mount device', $firstDevice, 'at', "$target$mountPoint", 'with', $fs );
            if( UBOS::Utils::myexec( "mount -t $fs '$firstDevice' '$target$mountPoint'" )) {
                ++$errors;
            }
        }
    }
    return $errors;
}

##
# Unmount the previous mounts
# $installer: the Installer
# return: number of errors
sub umountVolumes {
    my $self      = shift;
    my $installer = shift;

    trace( 'Unmounting volumes' );

    my $target = $installer->getTarget();
    my $errors = 0;

    # longest first
    foreach my $vol ( reverse $self->getVolumesByMountPath() ) {

        my $fs = $vol->getFs();
        unless( $fs ) {
            # no need to mount
            next;
        }

        my $mountPoint = $vol->getMountPoint();

        if( $mountPoint ) {
            debugAndSuspend( 'Umount ', $mountPoint );
            if( UBOS::Utils::myexec( "umount '$target$mountPoint'" )) {
                ++$errors;
            }
        }
    }
    return $errors;
}

##
# Create btrfs subvolumes if needed
# $installer: the Installer
# return: number of errors
sub createSubvols {
    my $self      = shift;
    my $installer = shift;

    my $target = $installer->getTarget();
    my $errors = 0;

    my $rootVolume = $self->getRootVolume();

    if( $rootVolume && 'btrfs' eq $rootVolume->getFs() ) {
        # create separate subvol for /var/log, so snapper does not roll back the logs
        unless( -d "$target/var" ) {
            UBOS::Utils::mkdirDashP( "$target/var" );
        }

        debugAndSuspend( 'Create subvol ', "$target/var/log" );
        my $out;
        if( UBOS::Utils::myexec( "btrfs subvol create '$target/var/log'", undef, \$out, \$out )) {
            error( "Failed to create btrfs subvol for '$target/var/log':", $out );
            ++$errors;
        }
    } else {
        UBOS::Utils::mkdirDashP( "$target/var/log" );
    }

    return $errors;
}

##
# Generate and save /etc/fstab
# $installer: the Installer
# return: number of errors
sub saveFstab {
    my $self      = shift;
    my $installer = shift;

    my $target = $installer->getTarget();

    my $fsTab = <<FSTAB;
#
# /etc/fstab: static file system information
#
# <file system> <dir>   <type>  <options>   <dump>  <pass>

FSTAB

    my $i=0;

    # shortest first
    foreach my $vol ( $self->getVolumesByMountPath() ) {

        my $fs = $vol->getFs();
        unless( $fs ) {
            # no need to mount
            next;
        }

        my $mountPoint = $vol->getMountPoint();

        if( 'btrfs' eq $fs ) {
            my @devices = $vol->getDeviceNames();

            # Take blkid from first device
            my $uuid;
            UBOS::Utils::myexec( "blkid -s UUID -o value '" . $devices[0] . "'", undef, \$uuid );
            $uuid =~ s!^\s+!!g;
            $uuid =~ s!\s+$!!g;

            trace( 'uuid of btrfs device', $devices[0], 'to be mounted at', $mountPoint, 'is', $uuid );

            my $passno = ( $mountPoint eq '/' ) ? 1 : 2;

            $fsTab .= "UUID=$uuid $mountPoint btrfs rw,relatime";
            # This may not be needed, if 'btrfs device scan' is done during boot
            # and if it is needed, this won't work, because @devices contains /dev/mapper/loopXpY or such
            # $fsTab .= join( '', map { ",device=$_" } @devices );
            $fsTab .= " $i $passno\n";

        } elsif( 'swap' eq $fs ) {
            my @devices = $vol->getDeviceNames();

            foreach my $device ( @devices ) {
                my $uuid;
                UBOS::Utils::myexec( "blkid -s UUID -o value '" . $device . "'", undef, \$uuid );
                $uuid =~ s!^\s+!!g;
                $uuid =~ s!\s+$!!g;

                trace( 'uuid of swap device', $device, 'is', $uuid );

                $fsTab .= "UUID=$uuid none swap defaults 0 0\n";
            }

        } else {
            my $device = ( $vol->getDeviceNames() )[0];

            my $uuid;
            UBOS::Utils::myexec( "blkid -s UUID -o value '$device'", undef, \$uuid );
            $uuid =~ s!^\s+!!g;
            $uuid =~ s!\s+$!!g;

            trace( 'uuid of other device', $device, 'to be mounted at', $mountPoint, 'is', $uuid );

            my $passno = ( $mountPoint eq '/' ) ? 1 : 2;

            $fsTab .= "UUID=$uuid $mountPoint $fs rw,relatime $i $passno\n";
        }
        ++$i;
    }
    debugAndSuspend( 'Saving ', "$target/etc/fstab", ":\n$fsTab" );

    UBOS::Utils::saveFile( "$target/etc/fstab", $fsTab, 0644, 'root', 'root' );

    return 0;
}


##
# Obtain the btrfs device mount points that snapper should manage.
# return: list of mount points
sub snapperBtrfsMountPoints {
    my $self = shift;

    my @ret;
    foreach my $vol ( @{$self->{volumes}} ) {
        if( 'btrfs' eq $vol->getFs()) {
            push @ret, $vol->getMountPoint();
        }
    }
    return @ret;
}

##
# Helper method to determine the root volume
# return: the root volume
sub getRootVolume {
    my $self = shift;

    my @ret;
    foreach my $vol ( @{$self->{volumes}} ) {
        if( $vol->isRoot() ) {
            return $vol;
        }
    }
    return undef;
}

##
# Determine the boot loader device for this VolumeLayout
sub determineBootLoaderDevice {
    my $self = shift;

    # no op, may be overridden
    return undef;
}

##
# Helper method to return the instances of Volume ordered by the length of
# the mount path, from shortest to longest. This will return not-to-be-mounted
# devices (like swap) first as their mount path is ''.
# return: array
sub getVolumesByMountPath {
    my $self = shift;

    my @ret = sort {
        length( $a->getMountPoint() ) <=> length( $b->getMountPoint() )
    } @{$self->{volumes}};

    return @ret;
}

# -- statics from here

##
# Reset caches related to information about disks.
# return: number of errors
sub resetDiskCaches {

    my $errors = 0;
    my $out;
    if( UBOS::Utils::myexec( 'partprobe', undef, \$out, \$out )) {
        # swallow output. It sometimes says things such as:
        # Warning: Not all of the space available to /dev/xxx appears to be used, you can fix ...
        ++$errors;
    }
    trace( 'partprobe:', $out );

    $_pathFacts = {};
    $_lsBlk     = undef;
    return $errors;
}

##
# Helper method to determine some facts about a given path, such as whether it is a file,
# a disk, or a partition
# $path: the path
# $fact: the fact to determine
sub _determineDeviceFact {
    my $path = shift;
    my $fact = shift;

    my $facts;
    if( exists( $_pathFacts->{$path} )) {
        $facts = $_pathFacts->{$path};

    } else {
        if( -e $path ) {
            my $absPath = abs_path( $path );

            if( -f $absPath ) {
                $facts = {
                    'devicetype' => 'file'
                };

            } elsif( -d $absPath ) {
                $facts = {
                    'devicetype' => 'directory'
                };

            } elsif( -b $absPath ) {

                unless( $_lsBlk ) {
                    my $out;
                    if( UBOS::Utils::myexec( "lsblk -o NAME,TYPE,PARTUUID,MOUNTPOINT --json -n", undef, \$out )) {
                        fatal( 'lsblk of device failed:', $absPath );
                    }

                    $_lsBlk = UBOS::Utils::readJsonFromString( $out );
                }

                foreach my $deviceEntry ( @{$_lsBlk->{blockdevices}} ) {
                    my $deviceName = $deviceEntry->{name};
                    my $deviceFacts = {
                        'devicetype' => $deviceEntry->{type},
                        'partuuid'   => $deviceEntry->{partuuid},
                        'mountpoint' => $deviceEntry->{mountpoint}
                    };
                    $_pathFacts->{ "/dev/$deviceName" } = $deviceFacts;


                    if( exists( $deviceEntry->{children} )) {
                        # flatten this
                        foreach my $child ( @{$deviceEntry->{children}} ) {
                            my $childName = $child->{name};
                            my $childFacts = {
                                'devicetype' => $child->{type},
                                'partuuid'   => $child->{partuuid},
                                'mountpoint' => $child->{mountpoint}
                            };
                            $_pathFacts->{ "/dev/$childName" } = $childFacts;
                        }
                    }
                }
                if( exists( $_pathFacts->{$absPath} )) {
                    $facts = $_pathFacts->{$absPath};
                }
            } else {
                warning( 'Cannot determine type of path:', $path );
                $facts = {
                    'devicetype' => 'unknown'
                };
            }
        } else {
            $facts = {
                'devicetype' => 'missing'
            };
        }
        $_pathFacts->{$path} = $facts;
    }
    if( $facts && exists( $facts->{$fact} )) {
        return $facts->{$fact};
    } else {
        return undef;
    }
}

##
# Helper method to determine whether a given path points to a file
# $path: the path
sub isFile {
    my $path = shift;

    my $type = _determineDeviceFact( $path, 'devicetype' );
    return $type eq 'file';
}

##
# Helper method to determine whether a given path points to a directory
# $path: the path
sub isDirectory {
    my $path = shift;

    my $type = _determineDeviceFact( $path, 'devicetype' );
    return $type eq 'directory';
}

##
# Helper method to determine whether a given path points to a disk
# $path: the path
sub isDisk {
    my $path = shift;

    my $type = _determineDeviceFact( $path, 'devicetype' );
    return $type eq 'disk';
}

##
# Helper method to determine whether a given path points to a partition
# $path: the path
sub isPartition {
    my $path = shift;

    my $type = _determineDeviceFact( $path, 'devicetype' );
    return $type eq 'part';
}

##
# Helper method to determine whether a given path points to a block device
# $path: the path
sub isBlockDevice {
    my $path = shift;

    my $type = _determineDeviceFact( $path, 'devicetype' );
    return $type eq 'disk' || $type eq 'part';
}

##
# Helper method to determine whether a given path points to a loop device
# $path: the path
sub isLoopDevice {
    my $path = shift;

    my $type = _determineDeviceFact( $path, 'devicetype' );
    return $type eq 'loop';
}

##
# Helper method to determine the PARTUUID of a given device, assuming it has one
# $path: the file's name
sub determinePartUuid {
    my $path = shift;

    my $uuid = _determineDeviceFact( $path, 'partuuid' );
    return $uuid;
}

##
# Helper method to determine the MOUNTPOINT of a given device, or return undef if
# not mounted.
# $path: the file's name
sub determineMountPoint {
    my $path = shift;

    my $mountPoint = _determineDeviceFact( $path, 'mountpoint' );
    if( $mountPoint ) {
        return $mountPoint;
    } else {
        return undef;
    }
}

##
# Helper method to determine whether or not a given device, or a child device
# is mounted. E.g. for /dev/sda, it will return 0 only if neither /dev/sda nor
# any of the /dev/sda1 ... /dev/sdaX are mounted; 1 otherwise
# $path: the block device's
# return: true or false
sub isMountedOrChildMounted {
    my $path = shift;

    if( determineMountPoint( $path )) {
        return 1;
    }

    foreach my $childPath ( keys %$_pathFacts ) {
        if( $childPath =~ m!^$path! ) {
            if( determineMountPoint( $childPath )) {
                return 1;
            }
        }
    }
    return 0;
}

1;
