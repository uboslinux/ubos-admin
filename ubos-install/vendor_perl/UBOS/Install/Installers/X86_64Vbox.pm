#
# Install UBOS for a 64-bit PC emulated in VirtualBox.
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
        $self->{devicepackages} = [ qw( ubos-networking-client mkinitcpio grub virtualbox-guest ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged.service vboxservice.service systemd-timesyncd.service ) ];
    }
    $self->SUPER::new( @args );

    $self->{packagedbs}->{'virt'} = '$depotRoot/$channel/$arch/virt';

    return $self;
}

##
# Create a DiskLayout object that goes with this Installer.
# $argvp: remaining command-line arguments
sub createDiskLayout {
    my $self  = shift;
    my $argvp = shift;

    if( 'gpt' eq $self->{partitioningscheme} ) {
        fatal( 'Partitioning scheme GPT is not yet supported for deviceclass', $self->deviceClass );
    }

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
            $ret = UBOS::Install::DiskImages::MbrDiskImage->new(
                    $first,
                    {   '/' => {
                            'index' => 1,
                            'fs'    => 'btrfs'
                            # default partition type
                        },
                    } );
        } elsif( $ret && UBOS::Install::AbstractDiskLayout::isBlockDevice( $first )) {
            # Option 2
            $ret = UBOS::Install::DiskImages::MbrDiskBlockDevices->new(
                    $argvp,
                    {   '/' => {
                            'index' => 1,
                            'fs'    => 'btrfs'
                            # default partition type
                        },
                    } );

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
# $diskLayout: the disk layout
# return: number of errors
sub installBootLoader {
    my $self       = shift;
    my $diskLayout = shift;

    my $errors = 0;
    if( $self->{partitioningscheme} eq 'mbr' ) {
        $errors += $self->installGrub( $diskLayout, {
                    'target'         => 'i386-pc',
                    'boot-directory' => $self->{target} . '/boot'
            } );

    } elsif( $self->{partitioningscheme} eq 'gpt' ) {
        $errors += $self->installSystemdBoot( $diskLayout );

    } else {
        fatal( 'Unknown partitioningscheme:', $self->{partitioningscheme} );
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
