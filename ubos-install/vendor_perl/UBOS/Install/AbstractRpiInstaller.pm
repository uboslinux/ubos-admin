#
# Abstract superclass for Raspberry Pi installers.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: PI has /dev/hwrng, so we run rngd, and patch its
#   configuration file during ubos-install, as long as Arch ARM hasn't updated the
#   default configuration they ship, which is identical as the x86 one:
#   http://archlinuxarm.org/forum/viewtopic.php?f=60&t=8571,

use strict;
use warnings;

package UBOS::Install::AbstractRpiInstaller;

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
    $self->{kernelpackage} = 'linux-raspberrypi';
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( ubos-networking-client
                raspberrypi-firmware raspberrypi-bootloader
                raspberrypi-bootloader-x archlinuxarm-keyring
                rng-tools smartmontools wpa_supplicant crda ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( rngd.service systemd-timesyncd.service ) ];
    }
    unless( $self->{devicemodules} ) {
        $self->{devicemodules} = [ qw( snd-bcm2835 ) ];
    }

    $self->SUPER::new( @args );

    return $self;
}

##
# Create a DiskLayout object that goes with this Installer.
# $noswap: if true, do not create a swap partition
# $argvp: remaining command-line arguments
# return: the DiskLayout object
sub createDiskLayout {
    my $self  = shift;
    my $noswap = shift;
    my $argvp = shift;

    # Option 1: a single image file
    # ubos-install ... image.img

    # Option 2: a single disk device
    # ubos-install ... /dev/sda

    # Option 3: a boot partition device, one or more root partition devices
    # ubos-install ... --bootpartition /dev/sda1 --rootpartition /dev/sda2 --rootpartition /dev/sdb1

    # Option 4: a boot partition device, one or more root partition devices, one or more var partition devices
    # as #3, plus add --varpartition /dev/sda3 --varpartition /dev/sdd1

    # Option 5: a directory (invalid)

    my $bootpartition;
    my @rootpartitions;
    my @varpartitions;
    my $directory;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'bootpartition=s' => \$bootpartition,
            'rootpartition=s' => \@rootpartitions,
            'varpartition=s'  => \@varpartitions,
            'directory=s'     => \$directory );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    my $ret = 1; # set to something, so undef can mean error
    if( $directory ) {
        # Option 5 (invalid)
        error( 'Invalid invocation: --directory cannot be used with this device class. Did you mean to install for a container?' );
        $ret = undef;

    } elsif( $bootpartition || @rootpartitions || @varpartitions ) {
        # Option 3 or 4
        if( $noswap ) {
            error( 'Invalid invocation: --noswap cannot be used if specifying partitions' );
            $ret = undef;
        }
        if( $ret && @$argvp ) {
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
            error( 'Provided bootpartition is not a partition:', $bootpartition );
            $ret = undef;
        }
        my %haveAlready = ();
        if( defined( $bootpartition )) {
            $haveAlready{$bootpartition} = 1;
        }

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
        if( $ret && @varpartitions == 0 ) {
            # Option 3
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
                    {   '/boot' => {
                            'index'       => 1,
                            'fs'          => 'vfat',
                            'devices'     => [ $bootpartition ],
                            'mbrboot'     => 1,
                            'mbrparttype' => 'c'
                            # default partition type for gpt
                        },
                        '/' => {
                            'index'  => 2,
                            'fs'      => 'btrfs',
                            'devices' => \@rootpartitions
                             # default partition type
                        }
                    } );
        } elsif( $ret ) {
            # Options 4
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevices->new(
                    {   '/boot' => {
                            'index'       => 1,
                            'fs'          => 'vfat',
                            'devices'     => [ $bootpartition ],
                            'mbrboot'     => 1,
                            'mbrparttype' => 'c'
                            # default partition type for gpt
                        },
                        '/' => {
                            'index'   => 2,
                            'fs'      => 'btrfs',
                            'devices' => \@rootpartitions
                             # default partition type
                        },
                        '/var' => {
                            'index'  => 3,
                            'fs'      => 'btrfs',
                            'devices' => \@varpartitions
                             # default partition type
                        }
                    } );
        }

    } else {
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
                            {   '/boot' => {
                                    'index'       => 1,
                                    'fs'          => 'vfat',
                                    'size'        => 200 * 1024, # 100M at 512/sector
                                    'mbrparttype' => 'c'
                                    # default partition type for gpt
                                },
                                '/' => {
                                    'index' => 2,
                                    'fs'    => 'btrfs'
                                    # default partition type
                                },
                            } );
                }
            } elsif( $ret && UBOS::Install::AbstractDiskLayout::isDisk( $rootDiskOrImage )) {
                # Option 2
                my $deviceTable = {
                    '/boot' => {
                        'index'       => 1,
                        'fs'          => 'vfat',
                        'size'        => 200 * 1024, # 100M at 512/sector
                        'mbrparttype' => 'c',
                        'label'       => 'UBOS boot'
                        # default partition type for gpt
                    },
                    '/' => {
                        'index' => 2,
                        'fs'    => 'btrfs',
                        'label' => 'UBOS root'
                        # default partition type
                    },
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

                $ret = UBOS::Install::DiskLayouts::GptDiskBlockDevices->new(
                        [   $rootDiskOrImage    ],
                        $deviceTable );
            } elsif( $ret ) {
                error( 'Must be file or disk:', $rootDiskOrImage );
                $ret = undef;
            }
        } elsif( @$argvp > 1 ) {
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
# Generate and save different other files if needed
# return: number of errors
sub saveOther {
    my $self = shift;

    my $ret    = 0;
    my $target = $self->{target};

    # Use hardware random generator by default

    unless( UBOS::Utils::saveFile( "$target/etc/conf.d/rngd", <<CONTENT )) {
# Changed for UBOS
RNGD_OPTS="-o /dev/random -r /dev/hwrng"
CONTENT
        ++$ret;
    }

    unless( UBOS::Utils::saveFile( "$target/etc/udev/rules.d/raspberrypi.rules", <<CONTENT )) {
SUBSYSTEM=="vchiq|input", MODE="0777"
KERNEL=="mouse*|mice|event*", MODE="0777"
CONTENT
        ++$ret;
    }

    return $ret;
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

1;
