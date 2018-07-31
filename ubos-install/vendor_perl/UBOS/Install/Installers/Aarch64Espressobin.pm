#
# Install UBOS for EspressoBIN
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: we do nothing

use strict;
use warnings;

package UBOS::Install::Installers::Aarch64Espressobin;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskBlockDevices;
use UBOS::Install::AbstractDiskImage;
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::Directory;
use UBOS::Install::DiskLayouts::MbrDiskBlockDevices;
use UBOS::Install::DiskLayouts::MbrDiskImage;
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
    $self->{kernelpackage} = 'linux-espressobin';

    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( ubos-networking-client ubos-networking-espressobin
                ubos-networking-standalone uboot-tools archlinuxarm-keyring
                espressobin-uboot-config espressobin-ubos-state
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
# $noswap: if true, do not create a swap partition
# $argvp: remaining command-line arguments
# $config: the config JSON if a JSON file was given on the command-line
# return: the DiskLayout object
sub createDiskLayout {
    my $self   = shift;
    my $noswap = shift;
    my $argvp  = shift;
    my $config = shift;

    # Option 1: a single image file
    # ubos-install ... image.img

    # Option 2: a single disk device
    # ubos-install ... /dev/sda

    # Option 3: a directory (invalid)

    my $bootloaderdevice;
    my @rootpartitions;
    my @ubospartitions;
    my $directory;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'bootloaderdevice=s' => \$bootloaderdevice,
            'rootpartition=s'    => \@rootpartitions,
            'ubospartition=s'    => \@ubospartitions,
            'directory=s'        => \$directory );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    if( !$bootloaderdevice && exists( $config->{bootloaderdevice} )) {
        $bootloaderdevice = $config->{bootloaderdevice};
    }
    if( !@rootpartitions ) {
        if( exists( $config->{rootpartitions} )) {
            @rootpartitions = @{$config->{rootpartitions}};
        } elsif( exists( $config->{rootpartition} )) {
            @rootpartitions = ( $config->{rootpartition} );
        }
    }
    if( !@ubospartitions ) {
        if( exists( $config->{ubospartitions} )) {
            @ubospartitions = @{$config->{ubospartitions}};
        } elsif( exists( $config->{ubospartition} )) {
            @ubospartitions = ( $config->{ubospartition} );
        }
    }
    if( !$directory && exists( $config->{directory} )) {
        $directory = $config->{directory};
    }
    if( !@$argvp ) {
        if( exists( $config->{devices} )) {
            @$argvp = @{$config->{devices}};
        } elsif( exists( $config->{device} )) {
            @$argvp = ( $config->{device} );
        }
    }

    my $ret = 1; # set to something, so undef can mean error
    if( $directory ) {
        # Option 3
        error( 'Invalid invocation: --directory cannot be used with this device class. Did you mean to install for a container?' );
        $ret = undef;

    } else {
        # Option 1 or 2
        if( @$argvp == 1 ) {
            my $rootDiskOrImage = $argvp->[0];
            if( UBOS::Install::AbstractDiskLayout::isFile( $rootDiskOrImage )) {
                # Option 1
                if( $noswap ) {
                    error( 'Invalid invocation: --noswap cannot be used if installing to a file' );
                    $ret = undef;
                } else {
                    $ret = UBOS::Install::DiskLayouts::MbrDiskImage->new(
                            $rootDiskOrImage,
                            {   '/boot' => {
                                    'index'     => 1,
                                    'fs'        => 'ext4',
                                    'size'      => 200 * 1024, # 100M at 512/sector
                                    'mkfsflags' => '-O ^metadata_csum,^64bit',
                                    'mbrboot'   => 1
                                    # default partition type                                
                                },
                                '/' => {
                                    'index' => 2,
                                    'fs'    => 'btrfs'
                                    # default partition type
                                },
                            } );
                }
            } elsif( UBOS::Install::AbstractDiskLayout::isDisk( $rootDiskOrImage )) {
                # Option 2
                if( UBOS::Install::AbstractDiskLayout::determineMountPoint( $rootDiskOrImage )) {
                    error( 'Cannot install to mounted disk:', $rootDiskOrImage );
                    $ret = undef;
                } else {
                    my $deviceTable = {
                        '/boot' => {
                            'index'     => 1,
                            'fs'        => 'ext4',
                            'size'      => 200 * 1024, # 100M at 512/sector
                            'mkfsflags' => '-O ^metadata_csum,^64bit',
                            'mbrboot'   => 1,
                            'label'       => 'UBOS_boot'
                            # default partition type
                        },
                        '/' => {
                            'index' => 2,
                            'fs'    => 'btrfs',
                            'label' => 'UBOS_root'
                            # default partition type
                        }
                    };
                    unless( $noswap ) {
                        $deviceTable->{swap} = {
                            'index'       => 3,
                            'fs'          => 'swap',
                            'size'        => 8192 * 1024, # 4G at 512/sector
                            'mbrparttype' => '82',
                            'gptparttype' => '8200',
                            'label'       => 'swap'
                        };
                    }
                    $ret = UBOS::Install::DiskLayouts::MbrDiskBlockDevices->new(
                            [ $rootDiskOrImage ],
                            $deviceTable );
                }
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
            error( 'Must specify at least one file or image for deviceclass=' . $self->deviceClass() );
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
