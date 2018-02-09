#
# Install UBOS for a 64-bit PC emulated in VirtualBox.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: haveged for artificial entropy. VirtualBox does not
#   currently have any support for (virtual) hardware random devices:
#   https://www.virtualbox.org/pipermail/vbox-dev/2015-March/012909.html

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Vbox;

use base qw( UBOS::Install::AbstractPcInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskBlockDevices;
use UBOS::Install::AbstractDiskImage;
use UBOS::Install::AbstractDiskLayout;
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
        $self->{hostname} = 'ubos-vbox-pc';
    }
    $self->{kernelpackage} = 'linux';
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( ubos-networking-client mkinitcpio virtualbox-guest ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged.service vboxservice.service systemd-timesyncd.service ) ];
    }
    $self->SUPER::new( @args );

    $self->{packagedbs}->{'virt'} = '$depotRoot/$channel/$arch/virt';
    $self->{packagedbs}->{'ui'}   = '$depotRoot/$channel/$arch/ui'; # contains virt dependencies

    return $self;
}

##
# Create a DiskLayout object that goes with this Installer.
# $noswap: if true, do not create a swap partition
# $argvp: remaining command-line arguments
# return: the DiskLayout object
sub createDiskLayout {
    my $self   = shift;
    my $noswap = shift;
    my $argvp  = shift;

    # Option 1: a single image file
    # ubos-install ... image.img

    # Option 2: a disk device
    # ubos-install ... /dev/somedevice

    my $ret = 1; # set to something, so undef can mean error
    if( @$argvp ) {
        if( @$argvp > 1 ) {
            error( 'Do not specify more than one image file or device.' );
            $ret = undef;
        }
        my $first = $argvp->[0];
        if( $ret && UBOS::Install::AbstractDiskLayout::isFile( $first )) {
            # Option 1
            if( $noswap ) {
                error( 'Invalid invocation: --noswap cannot be used when installing to a file' );
                $ret = undef;
            } else {
                $ret = UBOS::Install::DiskLayouts::MbrDiskImage->new(
                        $first,
                        {   '/' => {
                                'index' => 1,
                                'fs'    => 'btrfs'
                                # default partition type
                            },
                        } );
            }
        } elsif( $ret && UBOS::Install::AbstractDiskLayout::isBlockDevice( $first )) {
            # Option 2
            my $deviceTable = {
                '/' => {
                    'index' => $noswap ? 1 : 2,
                    'fs'    => 'btrfs'
                    # default partition type
                }
            };
            unless( $noswap ) {
                $deviceTable->{swap} = {
                    'index'       => 1,
                    'fs'          => 'swap',
                    'size'        => '4G',
                    'mbrparttype' => '82',
                    'gptparttype' => '8200',
                    'label'       => 'swap'
                };
            }

            $ret = UBOS::Install::DiskLayouts::MbrDiskBlockDevices->new(
                    $argvp,
                    $deviceTable );

        } elsif( $ret ) {
            error( 'Must be file or disk:', $first );
            $ret = undef;
        }
    } else {
        # Need at least one disk
        error( 'Must specify at least than one file or image for deviceclass=vbox' );
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

    my $errors = 0;

    $errors += $self->installGrub(
            $pacmanConfigFile,
            $diskLayout,
            {
                'target'         => 'i386-pc',
                'boot-directory' => $self->{target} . '/boot'
            } );

    $errors += $self->installSystemdBoot(
            $pacmanConfigFile,
            $diskLayout );

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

    return 'x86_64';
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'vbox';
}

##
# Help text
sub help {
    return 'Virtual root disk for VirtualBox (needs additional conversion to .vmdk)';
}

1;
