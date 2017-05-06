# 
# Install UBOS on an SD Card for a Pcduino3.
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

package UBOS::Install::Installers::Pcduino3;

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
        $self->{hostname} = 'ubos-' . $self->deviceClass();
    }
    $self->{kernelpackage} = 'linux-armv7';
        # The armv7 kernel has problems talking to the network on the pcduino3 nano (works on regular pcduino)
        # The sun7i kernel has problems booting at all

    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( ubos-networking-client
                ubos-networking-standalone uboot-tools archlinuxarm-keyring
                smartmontools wpa_supplicant crda ) ];
        # Do not add uboot-pcduino3 here: it wants interactive input, and we can't handle this here.
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( rngd.service systemd-timesyncd.service ) ];
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

    # Option 3: a bootloader device, one or more root partition devices
    # ubos-install ... --bootloaderdevice /dev/sda --rootpartition /dev/sda2 --rootpartition /dev/sdb1

    # Option 4: a bootloaderdevice device, one or more root partition devices, one or more var partition devices
    # as #3, plus add --varpartition /dev/sda3 --varpartition /dev/sdd1

    # Option 5: a directory

    my $bootloaderdevice;
    my @rootpartitions;
    my @varpartitions;
    my $directory;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'bootloaderdevice=s' => \$bootloaderdevice,
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
        if( $bootloaderdevice || @rootpartitions || @varpartitions || @$argvp ) {
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

    } elsif( @rootpartitions || @varpartitions ) {
        # Option 3 or 4
        if( @$argvp ) {
            error( 'Invalid invocation: either specify entire disks, or partitions; do not mix' );
            $ret = undef;
        }
        if( $ret && !$bootloaderdevice ) {
            error( 'Invalid invocation: Device class pcduino requires a --bootloaderdevice parameter when specifying partitions' );
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

        my %haveAlready = ();

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
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector->new(
                    $bootloaderdevice,
                    {   '/' => {
                            'index'       => 1,
                            'fs'          => 'ext4',
                            'devices'     => \@rootpartitions,
                            'startsector' => '2048'
                        }
                    } );
        } else {
            # Options 4
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector->new(
                    $bootloaderdevice,
                    {   '/' => {
                            'index'       => 1,
                            'fs'          => 'ext4',
                            'devices'     => \@rootpartitions,
                            'startsector' => '2048'
                        },
                        '/var' => {
                            'index'       => 2,
                            'fs'          => 'btrfs',
                            'devices'     => \@varpartitions
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
                        {   '/' => {
                                'index'       => 1,
                                'fs'          => 'ext4',
                                'startsector' => '2048'
                            },
                        } );
            } elsif( UBOS::Install::AbstractDiskLayout::isDisk( $rootDiskOrImage )) {
                # Option 2
                $ret = UBOS::Install::DiskLayouts::DiskBlockDevices->new(
                        [   $rootDiskOrImage    ],
                        {   '/' => {
                                'index'       => 1,
                                'fs'          => 'ext4',
                                'startsector' => '2048'
                            },
                        } );
            } else {
                error( 'Must be file or disk:', $rootDiskOrImage );
                $ret = undef;
            }
        } elsif( @$argvp > 1 ) {
            # Don't do RAID here
            error( 'Do not specify more than one file or image for deviceclass=pcduino3' );
            $ret = undef;
        } else {
            # Need at least one disk
            error( 'Must specify at least than one file or image for deviceclass=pcduino3' );
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

    my $errors           = 0;
    my $bootLoaderDevice = $diskLayout->determineBootLoaderDevice();
    my $target           = $self->{target};

    # Boot loader
    debug( "Installing uboot-pcduino3" );
    my $pacmanCmd = "pacman"
            . " -r '$target'"
            . " -S"
            . " '--config=" . $pacmanConfigFile . "'"
            . " --cachedir '$target/var/cache/pacman/pkg'"
            . " --noconfirm"
            . " uboot-pcduino3  --noscriptlet"; # DO NOT RUN the install script

    my $out;
    my $err;
    if( UBOS::Utils::myexec( $pacmanCmd, undef, \$out, \$err )) {
        error( "pacman failed", $err );
        ++$errors;
    }

    # Instead, we do it ourselves  
    if( UBOS::Utils::myexec( "dd 'if=$target/boot/u-boot-sunxi-with-spl.bin' 'of=$bootLoaderDevice' bs=1024 seek=8 conv=notrunc status=none" )) {
        ++$errors;
    }

    return $errors;
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    debug( "Executing addConfigureNetworkingToScript" );

    $$chrootScriptP .= "ubos-admin setnetconfig --skip-check-ready --init-only client\n";

    return 0;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'armv7h';
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'pcduino3';
}

##
# Help text
sub help {
    return 'pcduino3';
}

1;
