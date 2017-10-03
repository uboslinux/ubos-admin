#
# Install UBOS for EspressoBIN
#
# This file is part of ubos-install.
# (C) 2012-2017 Indie Computing Corp.
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

package UBOS::Install::Installers::Aarch64Espressobin;

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
    $self->{kernelpackage} = 'linux-espressobin';

    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( ubos-networking-client ubos-networking-espressobin
                ubos-networking-standalone uboot-tools archlinuxarm-keyring
                espressobin-uboot-config
                smartmontools wpa_supplicant crda ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged.service systemd-timesyncd.service ) ];
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

    # Option 3: a directory

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
        # Option 3
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

    } else {
        # Option 1 or 2
        if( @$argvp == 1 ) {
            my $rootDiskOrImage = $argvp->[0];
            if( UBOS::Install::AbstractDiskLayout::isFile( $rootDiskOrImage )) {
                # Option 1
                $ret = UBOS::Install::DiskLayouts::DiskImage->new(
                        $rootDiskOrImage,
                        {   '/boot' => {
                                'index' => 1,
                                'fs'    => 'ext4',
                                'size'  => '100M'
                            },
                            '/' => {
                                'index' => 2,
                                'fs'    => 'btrfs'
                            },
                        } );
            } elsif( UBOS::Install::AbstractDiskLayout::isDisk( $rootDiskOrImage )) {
                # Option 2
                $ret = UBOS::Install::DiskLayouts::DiskBlockDevices->new(
                        [   $rootDiskOrImage    ],
                        {   '/boot' => {
                                'index' => 1,
                                'fs'    => 'ext4',
                                'size'  => '100M'
                            },
                            '/' => {
                                'index' => 2,
                                'fs'    => 'btrfs'
                            },
                        } );
            } else {
                error( 'Must be file or disk:', $rootDiskOrImage );
                $ret = undef;
            }
        } elsif( @$argvp > 1 ) {
            # Don't do RAID here
            error( 'Do not specify more than one file or image for deviceclass=' . $self->deviceClass() );
            $ret = undef;
        } else {
            # Need at least one disk
            error( 'Must specify at least than one file or image for deviceclass=' . $self->deviceClass() );
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

    # don't do anything here. All contained in uboot-espressobin-config
    my $errors           = 0;

    return $errors;
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    trace( "Executing addConfigureNetworkingToScript" );

    $$chrootScriptP .= "ubos-admin setnetconfig --skip-check-ready --init-only espressobin\n";

    return 0;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'aarch64';
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'espressobin';
}

##
# Help text
sub help {
    return 'Boot disk for EspressoBIN';
}

1;
