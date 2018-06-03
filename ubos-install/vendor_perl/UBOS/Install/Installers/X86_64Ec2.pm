#
# Install UBOS for Amazon EC2
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: haveged for artificial entropy.
# * cloud-init for ssh keys
# * we use linux-ec2 as the name for the kernel, but we do not use
#   mkinitcpio's linux-ec2.preset but plain linux.preset instead

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Ec2;

use base qw( UBOS::Install::AbstractPcInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskBlockDevices;
use UBOS::Install::AbstractDiskImage;
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::MbrDiskBlockDevices;
use UBOS::Install::DiskLayouts::MbrDiskImage;
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
    $self->{kernelpackage} = 'linux-ec2';
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( ubos-networking-cloud mkinitcpio ec2-keyring ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged.service systemd-timesyncd.service ) ];
    }
    unless( $self->{additionalkernelparameters} ) {
        $self->{additionalkernelparameters} = [
                'ro',
                'rootwait',
                'nomodeset',
                'console=hvc0',
                'earlyprintk=xen,verbose',
                'loglevel=7' ];
    }

    $self->SUPER::new( @args );

    return $self;
}

##
# Create a DiskLayout object that goes with this Installer.
# $noswap: if true, do not create a swap partition
# $argvp: remaining command-line arguments
# $product: the product JSON if a JSON file was given on the command-line
# return: the DiskLayout object
sub createDiskLayout {
    my $self    = shift;
    my $noswap  = shift;
    my $argvp   = shift;
    my $product = shift;

    # Option 1: a single image file
    # ubos-install ... image.img

    # Option 2: a disk device
    # ubos-install ... /dev/somedevice

    if( !@$argvp ) {
        if( exists( $product->{devices} )) {
            @$argvp = $product->{devices};
        } elsif( exists( $product->{device} )) {
            @$argvp = ( $product->{device} );
        }
    }

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
                error( 'Invalid invocation: --noswap cannot be used if installing to a file' );
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
            if( UBOS::Install::AbstractDiskLayout::determineMountPoint( $first )) {
                error( 'Cannot install to mounted disk:', $first );
                $ret = undef;
            } else {
                my $deviceTable = {
                    '/' => {
                        'index' => 1,
                        'fs'    => 'btrfs'
                        # default partition type
                    }
                };
                unless( $noswap ) {
                    $deviceTable->{swap} = {
                        'index'       => 2,
                        'fs'          => 'swap',
                        'size'        => 8192 * 1024, # 4G at 512/sector
                        'mbrparttype' => '82',
                        'gptparttype' => '8200'
                    };
                }
                $ret = UBOS::Install::DiskLayouts::MbrDiskBlockDevices->new(
                        $argvp,
                        $deviceTable );
            }

        } elsif( $ret ) {
            error( 'Must be file or disk:', $first );
            $ret = undef;
        }
    } else {
        # Need at least one disk
        error( 'Must specify at least than one file or image for deviceclass=ec2' );
        $ret = undef;
    }

    return $ret;
}

##
# Install a Ram disk -- overridden for EC2 so we can get the -ec2 kernel
# $diskLayout: the disk layout
# $kernelPostfix: allows us to add -ec2 to EC2 kernels
# return: number of errors
sub installRamdisk {
    my $self          = shift;
    my $diskLayout    = shift;

    return $self->SUPER::installRamdisk( $diskLayout, '-ec2' );
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

    $$chrootScriptP .= "ubos-admin setnetconfig --skip-check-ready --init-only cloud\n";

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

    return 'ec2';
}

##
# Help text
sub help {
    return 'Amazon EC2 disk image (needs additional conversion to AMI)';
}

1;
