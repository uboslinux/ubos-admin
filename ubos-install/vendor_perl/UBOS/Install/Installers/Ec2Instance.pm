#
# Install UBOS for Amazon EC2
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
# * random number generator: haveged for artificial entropy.
# * cloud-init for ssh keys
# * we use linux-ec2 as the name for the kernel, but we do not use
#   mkinitcpio's linux-ec2.preset but plain linux.preset instead

use strict;
use warnings;

package UBOS::Install::Installers::Ec2Instance;

use base qw( UBOS::Install::AbstractPcInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::DiskBlockDevices;
use UBOS::Install::DiskLayouts::DiskImage;
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
        $self->{devicepackages} = [ qw( ubos-networking-cloud mkinitcpio grub ec2-keyring ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged.service systemd-timesyncd.service ) ];
    }
    unless( $self->{additionalkernelparameters} ) {
        $self->{additionalkernelparameters} = [
                'ro',
                'rootwait',
                # 'rootfstype=btrfs', --not sure this is needed
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
# $argvp: remaining command-line arguments
sub createDiskLayout {
    my $self  = shift;
    my $argvp = shift;

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
            $ret = UBOS::Install::DiskLayouts::DiskImage->new(
                    $first,
                    {   '/' => {
                            'index' => 1,
                            'fs'    => 'btrfs'
                        },
                    } );
        } elsif( $ret && UBOS::Install::AbstractDiskLayout::isBlockDevice( $first )) {
            # Option 2
            $ret = UBOS::Install::DiskLayouts::DiskBlockDevices->new(
                    $argvp,
                    {   '/' => {
                            'index' => 1,
                            'fs'    => 'btrfs'
                        },
                    } );

        } elsif( $ret ) {
            error( 'Must be file or disk:', $first );
            $ret = undef;
        }
    } else {
        # Need at least one disk
        error( 'Must specify at least than one file or image for deviceclass=ec2-instance' );
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

    return $self->installGrub( $pacmanConfigFile, $diskLayout, '-ec2' );
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
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'ec2-instance';
}

##
# Help text
sub help {
    return 'Amazon EC2 disk image (needs additional conversion to AMI)';
}

1;
