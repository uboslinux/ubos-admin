# 
# Abstract superclass for Raspberry Pi installers.
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
# * random number generator: PI has /dev/hwrng, so we run rngd, and patch its
#   configuration file during ubos-install, as long as Arch ARM hasn't updated the
#   default configuration they ship, which is identical as the x86 one:
#   http://archlinuxarm.org/forum/viewtopic.php?f=60&t=8571,
#   see also Bbb

use strict;
use warnings;

package UBOS::Install::AbstractRpiInstaller;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::Directory;
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
        $self->{hostname} = 'ubos-raspberry-pi';
    }
    $self->{kernelpackage} = 'linux-raspberrypi';
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( raspberrypi-firmware raspberrypi-firmware-bootloader
                                        raspberrypi-firmware-bootloader-x archlinuxarm-keyring rng-tools ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( rngd ubos-networking-client ) ];
    }
    unless( $self->{devicemodules} ) {
        $self->{devicemodules} = [ qw( bcm2708-rng snd-bcm2835 ) ];
    }

    $self->SUPER::new( @args );

    return $self;
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
            error( 'Invalid invocation: Device class rpi requires a --bootpartition parameter when specifying partitions' );
            $ret = undef;
        }
        if( $ret && @rootpartitions == 0 ) {
            error( 'Invalid invocation: A --rootpartition must be provided when specifying partitions' );
            $ret = undef;
        }
        if( $ret && !UBOS::Install::AbstractDiskLayout::isPartition( $bootpartition )) {
            error( 'Provided bootpartition is not a partition:', $bootpartition );
            $ret = undef;
        }
        my %haveAlready = ();
        if( defined( $bootpartition )) {
            $haveAlready{$bootpartition} = 1;
        }

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
        if( $ret && @varpartitions == 0 ) {
            # Option 3
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
                    {   '/boot' => {
                            'index'   => 1,
                            'fs'      => 'ext4',
                            'devices' => [ $bootpartition ],
                            'boot'    => 1
                        },
                        '/' => {
                            'index'  => 2,
                            'fs'      => 'btrfs',
                            'devices' => \@rootpartitions
                        }
                    } );
        } elsif( $ret ) {
            # Options 4
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
                    {   '/boot' => {
                            'index'   => 1,
                            'fs'      => 'ext4',
                            'devices' => [ $bootpartition ],
                            'boot'    => 1
                        },
                        '/' => {
                            'index'   => 2,
                            'fs'      => 'btrfs',
                            'devices' => \@rootpartitions
                        },
                        '/var' => {
                            'index'  => 3,
                            'fs'      => 'btrfs',
                            'devices' => \@varpartitions
                        }
                    } );
        }
            
    } else {
        # Option 1 or 2
        if( @$argvp == 1 ) {
            my $rootDiskOrImage = $argvp->[0];
            if( $ret && UBOS::Install::AbstractDiskLayout::isFile( $rootDiskOrImage )) {
                # Option 1
                $ret = UBOS::Install::DiskLayouts::DiskImage->new(
                        $rootDiskOrImage,
                        {   '/boot' => {
                                'index' => 1,
                                'fs'    => 'vfat',
                                'size'  => '100M'
                            },
                            '/' => {
                                'index' => 2,
                                'fs'    => 'btrfs'
                            },
                        } );
            } elsif( $ret && UBOS::Install::AbstractDiskLayout::isDisk( $rootDiskOrImage )) {
                # Option 2
                $ret = UBOS::Install::DiskLayouts::DiskBlockDevices->new(
                        [   $rootDiskOrImage    ],
                        {   '/boot' => {
                                'index' => 1,
                                'fs'    => 'vfat',
                                'size'  => '100M'
                            },
                            '/' => {
                                'index' => 2,
                                'fs'    => 'btrfs'
                            },
                        } );
            } elsif( $ret ) {
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
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    debug( "Executing addEnableServicesToScript" );

    $$chrootScriptP .= 'ubos-admin setnetconfig --init-only client';

    return 0;
}

1;
