# 
# Install UBOS on an SD Card for a Beagle Bone Black.
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

# Device-specific notes:

# * This device is a bit strange: it needs a boot partition separate from /boot.
#   * During installation, the boot partition gets mounted at /boot, and it
#     drops dtbs, MLO, u-boot.img, uEnv.txt and zImage there
#   * When booting, the bootloader looks for MLO, u-boot.img and uEnv.txt in
#     the umounted first partition, but then it looks for dtbs and zImage in
#     /boot of the second partition
#   * We fix this by copying files from /boot to /bootpart at the end of the
#     process.
# * random number generator: BBB has /dev/hwrng, so we run rngd, and patch its
#   configuration file during ubos-install, as long as Arch ARM hasn't updated the
#   default configuration they ship, which is identical as the x86 one:
#   http://archlinuxarm.org/forum/viewtopic.php?f=60&t=8571,
#   see also AbstractRpiInstaller

use strict;
use warnings;

package UBOS::Install::Installers::Bbb;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::DiskBlockDevices;
use UBOS::Install::DiskLayouts::DiskImage;
use UBOS::Install::DiskLayouts::PartitionBlockDevices;
use UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector;
use UBOS::Logging;
use UBOS::Utils;

##
# Constructor
sub new {
    my $self = shift;
    my @args = @_;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    unless( $self->{hostname} ) {
        $self->{hostname} = 'ubos-bbb';
    }
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( linux-am33x uboot-beaglebone uboot-tools archlinuxarm-keyring rng-tools ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( rngd ) ];
    }

    $self->SUPER::new( @args );

    return $self;
}

##
# Add kernel parameters for the kernel boot
# @modules: array of parameter strings
sub addKernelParameters {
    my $self = shift;
    my @pars = @_;

    fatal( 'Cannot add kernel parameters on device class bbb at this time' );
}


##
# Create a DiskLayout object that goes with this Installer.
# $argvp: remaining command-line arguments
sub createDiskLayout {
    my $self  = shift;
    my $argvp = shift;

    # Option 1: a single image file
    # ubos-install ... image.img
    
    # Option 2: a single disk device
    # ubos-install ... /dev/sda

    # Option 3: a boot partition device, one or more root partition devices
    # ubos-install ... --bootpartition /dev/sda1 --rootpartition /dev/sda2 --rootpartition /dev/sdb1

    # Option 4: a boot partition device, one or more root partition devices, one or more var partition devices
    # as #3, plus add --varpartition /dev/sda3 --varpartition /dev/sdd1

    # Option 5: a directory

    my $bootpartition;
    my @rootpartitions;
    my @varpartitions;
    my $directory;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'bootpartition=s' => \$bootpartition,
            'rootpartition=s' => \@rootpartitions,
            'varpartition=s'  => \@varpartitions,
            'directory=s'     => \$directory );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    my $ret = 1; # set to something, so undef can mean error
    if( $directory ) {
        # Option 5
        if( $bootpartition || @rootpartitions || @varpartitions || @$argvp ) {
            error( 'Invalid invocation: if --directory is given, do not provide other partitions or devices' );
            $ret = undef;
        } elsif( !-d $directory || ! UBOS::Utils::isDirEmpty( $directory )) {
            error( 'Invalid invocation: directory must exist and be empty:', $directory );
            $ret = undef;
        } elsif( $self->{target} ) {
            error( 'Invalid invocation: do not specify --target when providing --directory:', $directory );
            $ret = undef;
        } else {
            $ret = UBOS::Install::DiskLayouts::Directory->new( $directory );
            $self->setTarget( $directory );
        }

    } elsif( $bootpartition || @rootpartitions || @varpartitions ) {
        # Option 3 or 4
        if( @$argvp ) {
            error( 'Invalid invocation: either specify entire disks, or partitions; do not mix' );
            $ret = undef;
        }
        if( $ret && !$bootpartition ) {
            error( 'Invalid invocation: Device class bbb requires a --bootpartition parameter when specifying partitions' );
            $ret = undef;
        }
        if( $ret && @rootpartitions == 0 ) {
            error( 'Invalid invocation: A --rootpartition must be provided when specifying partitions' );
            $ret = undef;
        }
        if( $ret && !UBOS::Install::AbstractDiskLayout::isPartition( $bootpartition )) {
            error( 'Not a partition:', $bootpartition );
        }
        my %haveAlready = ( $bootpartition => 1 );

        if( $ret ) {
            foreach my $part ( @rootpartitions, @varpartitions ) {
                if( $haveAlready{$part} ) {
                    error( 'Specified more than once:', $part );
                    $ret = undef;
                    last;
                }
                unless( UBOS::Install::AbstractDiskLayout::isPartition( $part )) {
                    error( 'Not a partition:', $part );
                    $ret = undef;
                    last;
                }
                $haveAlready{$part} = 1;
            }
        }
        if( @varpartitions == 0 ) {
            # Option 3
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
                    {   '/bootpart' => {
                            'index'     => 1,
                            'fs'        => 'vfat',
                            'mkfsflags' => '-F 16',
                            'devices'   => [ $bootpartition ],
                            'boot'      => 1
                        },
                        '/' => {
                            'index'  => 2,
                            'fs'      => 'ext4',
                            'devices' => \@rootpartitions
                        }
                    } );
        } else {
            # Options 4
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
                    {   '/bootpart' => {
                            'index'     => 1,
                            'fs'        => 'vfat',
                            'mkfsflags' => '-F 16',
                            'devices'   => [ $bootpartition ],
                            'boot'      => 1
                        },
                        '/' => {
                            'index'   => 2,
                            'fs'      => 'ext4',
                            'devices' => \@rootpartitions
                        },
                        '/var' => {
                            'index'  => 3,
                            'fs'      => 'ext4',
                            'devices' => \@varpartitions
                        }
                    } );
        }
            
    } else {
        # Option 1 or 2
        if( @$argvp == 1 ) {
            my $rootDiskOrImage = $argvp->[0];
            if( UBOS::Install::AbstractDiskLayout::isFile( $rootDiskOrImage )) {
                # Option 1
                $ret = UBOS::Install::DiskLayouts::DiskImage->new(
                        $rootDiskOrImage,
                        {   '/bootpart' => {
                                'index'     => 1,
                                'fs'        => 'vfat',
                                'mkfsflags' => '-F 16',
                                'size'      => '64M'
                            },
                            '/' => {
                                'index' => 2,
                                'fs'    => 'ext4'
                            },
                        } );
            } elsif( UBOS::Install::AbstractDiskLayout::isDisk( $rootDiskOrImage )) {
                # Option 2
                $ret = UBOS::Install::DiskLayouts::DiskBlockDevices->new(
                        [   $rootDiskOrImage    ],
                        {   '/bootpart' => {
                                'index'     => 1,
                                'fs'        => 'vfat',
                                'mkfsflags' => '-F 16',
                                'size'      => '64M'
                            },
                            '/' => {
                                'index' => 2,
                                'fs'    => 'ext4'
                            },
                        } );
            } else {
                error( 'Must be file or disk:', $rootDiskOrImage );
                $ret = undef;
            }
        } elsif( @$argvp > 1 ) {
            # Don't do RAID here
            error( 'Do not specify more than one file or image for deviceclass=rpi' );
            $ret = undef;
        } else {
            # Need at least one disk
            error( 'Must specify at least than one file or image for deviceclass=rpi' );
            $ret = undef;
        }
    }
    
    return $ret;
}

##
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# $diskLayout: the disk layout
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;
    my $diskLayout       = shift;

    # Need to "fix this up": some files need to be moved from /boot to /bootpart
    # Actually we move them. FIXME: This needs to happen again when the
    # respective package gets updated, but currently doesn't.

    my $errors = 0;
    my $target = $self->{target};

    foreach my $file ( qw( MLO u-boot.img uEnv.txt )) {
        if( UBOS::Utils::myexec( "cp '$target/boot/$file' '$target/bootpart/'" )) {
            ++$errors;
        }
    }
    
    return $errors;
}

##
# Generate and save different other files if needed
# return: number of errors
sub saveOther {
    my $self = shift;

    my $target = $self->{target};

    # Use hardware random generator by default

    UBOS::Utils::saveFile( "$target/etc/conf.d/rngd", <<CONTENT );
# Changed for UBOS 
RNGD_OPTS="-o /dev/random -r /dev/hwrng"
CONTENT

    return 0;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'armv7h';
}

1;
