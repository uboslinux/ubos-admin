# 
# Install UBOS on an SD Card for a Raspberry Pi.
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

use strict;
use warnings;

package UBOS::Install::Installers::Rpi;

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
        $self->{hostname} = 'ubos-raspberry-pi';
    }
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( linux-raspberrypi raspberrypi-firmware raspberrypi-firmware-bootloader
                                        raspberrypi-firmware-bootloader-x archlinuxarm-keyring ) ];
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

    # Option 3: a boot partition device, one or more root partition devices
    # ubos-install ... --bootpartition /dev/sda1 --rootpartition /dev/sda2 --rootpartition /dev/sdb1

    # Option 4: a boot partition device, one or more root partition devices, one or more var partition devices
    # as #3, plus add --varpartition /dev/sda3 --varpartition /dev/sdd1

    my $bootpartition;
    my @rootpartitions;
    my @varpartitions;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'bootpartition=s' => \$bootpartition,
            'rootpartition=s' => \@rootpartitions,
            'varpartition=s'  => \@varpartitions );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    my $ret = 1; # set to something, so undef can mean error
    if( $bootpartition || @rootpartitions || @varpartitions ) {
        # Option 3 or 4
        if( @$argvp ) {
            error( 'Invalid invocation: either specify entire disks, or partitions; do not mix' );
            $ret = undef;
        }
        if( $ret && !$bootpartition ) {
            error( 'Invalid invocation: Device class rpi requires a --bootpartition parameter when specifying partitions' );
            $ret = undef;
        }
        if( $ret && @rootpartitions == 0 ) {
            error( 'Invalid invocation: A --rootpartition must be provided when specifying partitions' );
            $ret = undef;
        }
        if( $ret && !UBOS::Install::AbstractDiskLayout::isPartition( $bootpartition )) {
            error( 'Not a partition:', $bootpartition );
        }
        my %haveAlready = ( $bootpartition => 1 );

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
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
                    {   '/boot' => {
                            'index'   => 1,
                            'fs'      => 'ext4',
                            'devices' => [ $bootpartition ],
                            'boot'    => 1
                        },
                        '/' => {
                            'index'  => 2,
                            'fs'      => 'btrfs',
                            'devices' => \@rootpartitions
                        }
                    } );
        } else {
            # Options 4
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
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
                            'index'  => 3,
                            'fs'      => 'btrfs',
                            'devices' => \@varpartitions
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
                        {   '/boot' => {
                                'index' => 1,
                                'fs'    => 'vfat',
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
                                'fs'    => 'vfat',
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
        } elsif( @argvp > 1 ) {
            # Don't do RAID here
            error( 'Do not specify more than one file or image for deviceclass=rpi' );
            $ret = undef;
        } else {
            # Need at least one disk
            error( 'Must specify at least than one file or image for deviceclass=rpi' );
            $ret = undef;
        }
    }
    
    return $ret;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'armv6h';
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

    info( 'Installing boot loader' );

    # Copied from the ArmLinuxARM Raspberry Pi image
    
    UBOS::Utils::saveFile( $self->{target} . '/boot/cmdline.txt', <<CONTENT, 0644, 'root', 'root' );
selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=btrfs elevator=noop rootwait
CONTENT

    UBOS::Utils::saveFile( $self->{target} . '/boot/config.txt', <<CONTENT, 0644, 'root', 'root' );
# uncomment if you get no picture on HDMI for a default "safe" mode
#hdmi_safe=1

# uncomment this if your display has a black border of unused pixels visible
# and your display can output without overscan
#disable_overscan=1

# uncomment the following to adjust overscan. Use positive numbers if console
# goes off screen, and negative if there is too much border
#overscan_left=16
#overscan_right=16
#overscan_top=16
#overscan_bottom=16

# uncomment to force a console size. By default it will be display's size minus
# overscan.
#framebuffer_width=1280
#framebuffer_height=720

# uncomment if hdmi display is not detected and composite is being output
#hdmi_force_hotplug=1

# uncomment to force a specific HDMI mode (this will force VGA)
#hdmi_group=1
#hdmi_mode=1

# uncomment to force a HDMI mode rather than DVI. This can make audio work in
# DMT (computer monitor) modes
#hdmi_drive=2

# uncomment to increase signal to HDMI, if you have interference, blanking, or
# no display
#config_hdmi_boost=4

# uncomment for composite PAL
#sdtv_mode=2

#uncomment to overclock the arm. 700 MHz is the default.
#arm_freq=800

# for more options see http://elinux.org/RPi_config.txt

## Some over clocking settings, governor already set to ondemand

##None
#arm_freq=700
#core_freq=250
#sdram_freq=400
#over_voltage=0

##Modest
#arm_freq=800
#core_freq=300
#sdram_freq=400
#over_voltage=0

##Medium
#arm_freq=900
#core_freq=333
#sdram_freq=450
#over_voltage=2

##High
#arm_freq=950
#core_freq=450
#sdram_freq=450
#over_voltage=6

##Turbo
#arm_freq=1000
#core_freq=500
#sdram_freq=500
#over_voltage=6

gpu_mem_512=64
gpu_mem_256=64
CONTENT
}

1;
