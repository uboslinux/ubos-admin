# 
# Install UBOS for a PC.
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
# * random number generator: we do nothing

use strict;
use warnings;

package UBOS::Install::Installers::Pc;

use base qw( UBOS::Install::AbstractPcInstaller );
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
        $self->{hostname} = 'ubos-' . $self->deviceClass();
    }
    $self->{kernelpackage} = 'linux';
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( rng-tools mkinitcpio
                ubos-networking-client ubos-networking-gateway
                ubos-networking-standalone smartmontools wpa_supplicant ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged systemd-timesyncd ) ];
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

    # Option 2: one or more disk devices (raid mode)
    # Will create /boot (ext4) and / (btrfs) partitions
    # Will install boot loader on first disk
    # ubos-install ... /dev/sda
    # ubos-install ... /dev/sda /dev/sdb /dev/sdc

    # Option 3: one or more boot partition devices, one more more root partition devices (raid mode)
    # ubos-install ... --bootloaderdevice /dev/sda --bootpartition /dev/sda1 --bootpartition /dev/sdb1 --rootpartition /dev/sda2 --rootpartition /dev/sdb2

    # Option 4: a boot partition device, a root partition device, one or more var partition devices
    # as #3, plus add --varpartition /dev/sda3 --varpartition /dev/sdd1

    # Option 5: a directory

    my $bootloaderdevice;
    my $bootpartition;
    my @rootpartitions;
    my @varpartitions;
    my $directory;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'bootloaderdevice=s' => \$bootloaderdevice,
            'bootpartition=s'    => \$bootpartition,
            'rootpartition=s'    => \@rootpartitions,
            'varpartition=s'     => \@varpartitions,
            'directory=s'        => \$directory );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    my $ret = 1; # set to something, so undef can mean error
    if( $directory ) {
        # Option 5
        if( $bootloaderdevice || $bootpartition || @rootpartitions || @varpartitions || @$argvp ) {
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

    } elsif( $bootloaderdevice || $bootpartition || @rootpartitions || @varpartitions ) {
        # Option 3 or 4
        if( @$argvp ) {
            error( 'Invalid invocation: either specify entire disks, or partitions; do not mix' );
            $ret = undef;
        }
        if( $ret && !$bootloaderdevice ) {
            error( 'Invalid invocation: Device class pc requires a --bootloaderdevice parameter when specifying partitions' );
            $ret = undef;
        }
        if( $ret && @rootpartitions == 0 ) {
            error( 'Invalid invocation: A --rootpartition must be provided when specifying partitions' );
            $ret = undef;
        }
        if( $ret && !UBOS::Install::AbstractDiskLayout::isDisk( $bootloaderdevice ) && !UBOS::Install::AbstractDiskLayout::isLoopDevice( $bootloaderdevice )) {
            error( 'Provided bootloaderdevice is not a disk:', $bootloaderdevice );
            $ret = undef;
        }
        if( $ret && $bootpartition && !UBOS::Install::AbstractDiskLayout::isPartition( $bootpartition )) {
            error( 'Provided bootpartition is not a partition:', $bootpartition );
            $ret = undef;
        }
        my %haveAlready = ();
        if( defined( $bootpartition )) {
            $haveAlready{$bootpartition} = 1;
        }

        if( $ret ) {
            foreach my $part ( @rootpartitions, @varpartitions ) {
                if( $haveAlready{$part}) {
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
            if( $bootpartition ) {
                $ret = UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector->new(
                        $bootloaderdevice,
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
                            }
                        } );
            } else {
                $ret = UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector->new(
                        $bootloaderdevice,
                        {   '/' => {
                                'index'   => 1,
                                'fs'      => 'btrfs',
                                'devices' => \@rootpartitions
                            }
                        } );
            }
        } elsif( $ret ) {
            # Options 4
            if( $bootpartition ) {
                $ret = UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector->new(
                        $bootloaderdevice,
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
                                'index'   => 3,
                                'fs'      => 'btrfs',
                                'devices' => \@varpartitions
                            }
                        } );
            } else {
                $ret = UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector->new(
                        $bootloaderdevice,
                        {   '/' => {
                                'index'   => 1,
                                'fs'      => 'btrfs',
                                'devices' => \@rootpartitions
                            },
                            '/var' => {
                                'index'   => 2,
                                'fs'      => 'btrfs',
                                'devices' => \@varpartitions
                            }
                        } );
            }
        }
            
    } else {
        # Option 1 or 2
        if( @$argvp ) {
            my $first = $argvp->[0];
            if( $ret && UBOS::Install::AbstractDiskLayout::isFile( $first )) {
                # Option 1
                if( @$argvp>1 ) {
                    error( 'Do not specify more than one disk image; cannot RAID disk images' );
                    $ret = undef;
                } else {
                    $ret = UBOS::Install::DiskLayouts::DiskImage->new(
                            $first,
                            {   '/boot' => {
                                    'index' => 1,
                                    'fs'    => 'ext4',
                                    'size'  => '100M',
                                    'boot'  => 1
                                },
                                '/' => {
                                    'index' => 2,
                                    'fs'    => 'btrfs'
                                },
                            } );
                }
            } elsif( $ret && UBOS::Install::AbstractDiskLayout::isBlockDevice( $first )) {
                # Option 2
                my %haveAlready = ( $first => 1 );
                foreach my $disk ( @$argvp ) {
                    if( $first eq $disk ) {
                        next;
                    }
                    if( $haveAlready{$disk} ) {
                        error( 'Specified more than once:', $disk );
                        $ret = undef;
                        last;
                    }
                    unless( UBOS::Install::AbstractDiskLayout::isBlockDevice( $disk )) {
                        error( 'Not a block device:', $disk );
                        $ret = undef;
                        last;
                    }
                    $haveAlready{$disk} = 1;
                }
                if( $ret ) {
                    $ret = UBOS::Install::DiskLayouts::DiskBlockDevices->new(
                            $argvp,
                            {   '/boot' => {
                                    'index' => 1,
                                    'fs'    => 'ext4',
                                    'size'  => '100M',
                                    'boot'  => 1
                                },
                                '/' => {
                                    'index' => 2,
                                    'fs'    => 'btrfs'
                                },
                            } );
                }
            } elsif( $ret ) {
                error( 'Must be file or disk:', $first );
                $ret = undef;
            }
        } else {
            # Need at least one disk
            error( 'Must specify at least than one file or image for deviceclass=pc' );
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

    return $self->installGrub( $pacmanConfigFile, $diskLayout, '' );
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    debug( "Executing addConfigureNetworkingToScript" );

    $$chrootScriptP .= 'ubos-admin setnetconfig --init-only client';

    return 0;
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'pc';
}

##
# Help text
sub help {
    return 'PC (x86_64)';
}
1;
