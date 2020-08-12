#
# Install UBOS on an SD Card for an Odroid XU3, XU4 or HC2.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Armv7hOdroidXu3;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
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
    unless( $self->{hostname} ) {
        $self->{hostname} = 'ubos-odroid-xu3';
    }
    $self->{kernelpackage} = 'linux-odroid-xu3';

    $self->SUPER::new( @args );

    push @{$self->{devicepackages}}, 'ubos-deviceclass-odroidxu3';

    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw(
                ubos-networking-client
                archlinuxarm-keyring
                rng-tools uboot-odroid-xu3
                smartmontools
                ubos-deviceclass-odroidxu3
        ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( rngd.service systemd-timesyncd.service ) ];
    }

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

    my $parseOk = GetOptionsFromArray(
            $argvp );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    if( !@$argvp ) {
        if( exists( $config->{devices} )) {
            @$argvp = @{$config->{devices}};
        } elsif( exists( $config->{device} )) {
            @$argvp = ( $config->{device} );
        }
    }
    unless( $self->replaceDevSymlinks( $argvp )) {
        error( $@ );
        return undef;
    }

    my $ret = 1; # set to something, so undef can mean error

    # Option 1 or 2
    if( @$argvp == 1 ) {
        my $rootDiskOrImage = $argvp->[0];
        if( $ret && UBOS::Install::AbstractDiskLayout::isFile( $rootDiskOrImage )) {
            # Option 1
            if( $noswap ) {
                error( 'Invalid invocation: --noswap cannot be used if installing to a file' );
                $ret = undef;
            } else {
                $ret = UBOS::Install::DiskLayouts::MbrDiskImage->new(
                        $rootDiskOrImage,
                        {   '/' => {
                                'index' => 1,
                                'fs'    => 'ext4'
                                # default partition type
                            },
                        } );
            }
        } elsif( $ret && UBOS::Install::AbstractDiskLayout::isDisk( $rootDiskOrImage )) {
            # Option 2
            if( UBOS::Install::AbstractDiskLayout::isMountedOrChildMounted( $rootDiskOrImage )) {
                error( 'Cannot install to mounted disk:', $rootDiskOrImage );
                $ret = undef;
            } else {
                my $deviceTable = {
                     '/' => {
                        'index' => 1,
                        'fs'    => 'ext4',
                        'label' => 'UBOS_root'
                        # default partition type
                    },
                };
                unless( $noswap ) {
                    $deviceTable->{swap} = {
                        'index'       => 2,
                        'fs'          => 'swap',
                        'size'        => 2048 * 1024, # 1G at 512/sector
                        'mbrparttype' => '82',
                        'gptparttype' => '8200',
                        'label'       => 'swap'
                    };
                }

                $ret = UBOS::Install::DiskLayouts::MbrDiskImage->new(
                        $rootDiskOrImage,
                        $deviceTable );
            }
        } elsif( $ret ) {
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

    return 'odroid-xu3';
}

##
# Help text
sub help {
    return 'SD card for Odroid-XU3/XU4/HC2';
}

1;
