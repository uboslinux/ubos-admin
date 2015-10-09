# 
# Install UBOS for a Linux container.
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
# * no kernel, see https://bugs.archlinux.org/task/46591

use strict;
use warnings;
                                                  
package UBOS::Install::Installers::ContainerPc;

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
    $self->{kernelpackage} = undef; # no kernel
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw() ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( ubos-networking-client ) ];
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

    # Option 2: one device
    # ubos-install ... /dev/somedevice

    # Option 3: a directory

    my $directory;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'directory=s'        => \$directory );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    my $ret = 1; # set to something, so undef can mean error
    if( $directory ) {
        # Option 3
        if( @$argvp ) {
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

        } else {
            # Need at least one disk
            error( 'Must specify at least than one file or image for deviceclass=container-pc' );
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

    return 0;
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'container-pc';
}

1;
