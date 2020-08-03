#
# Install UBOS for a PC.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# Device-specific notes:
# * random number generator: we do nothing

use strict;
use warnings;

package UBOS::Install::Installers::X86_64Pc;

use base qw( UBOS::Install::AbstractPcInstaller );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskImage;
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::Directory;
use UBOS::Install::DiskLayouts::GptDiskBlockDevices;
use UBOS::Install::DiskLayouts::GptDiskImage;
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
        $self->{hostname} = 'ubos-pc';
    }
    $self->{kernelpackage} = 'linux';
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw(
                ubos-networking-client ubos-networking-gateway ubos-networking-standalone
                rng-tools mkinitcpio linux-firmware
                smartmontools
                wpa_supplicant crda
                ubos-deviceclass-pc
        ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged.service systemd-timesyncd.service smartd.service ) ];
    }

    unless( $self->{partitioningscheme} ) {
        $self->{partitioningscheme} = 'gpt'; # default
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

    # Option 2: one or more disk devices (raid mode)
    # Will create /boot (ext4), swap and / (btrfs) partitions
    # Will install boot loader on first disk
    # ubos-install ... /dev/sda
    # ubos-install ... /dev/sda /dev/sdb /dev/sdc

    # Option 3: one or more boot partition devices, one more more root partition devices (raid mode),
    #           zero or more ubos partition devices, and possibly swap partition devices
    # ubos-install ... --bootloaderdevice /dev/sda --bootpartition /dev/sda1 --bootpartition /dev/sdb1
    #                  --rootpartition /dev/sda2 --rootpartition /dev/sdb2
    #                  --ubospartition /dev/sda3 --ubospartition /dev/sdb3
    #                  --swappartition /dev/sda4 --swappartition /dev/sdb4

    # Option 4: a directory (invalid)

    my $bootloaderdevice;
    my $bootpartition;
    my @rootpartitions;
    my @ubospartitions;
    my @swappartitions;
    my $directory;

    my $parseOk = GetOptionsFromArray(
            $argvp,
            'bootloaderdevice=s' => \$bootloaderdevice,
            'bootpartition=s'    => \$bootpartition,
            'rootpartition=s'    => \@rootpartitions,
            'ubospartition=s'    => \@ubospartitions,
            'swappartitions=s'   => \@swappartitions,
            'directory=s'        => \$directory );
    if( !$parseOk ) {
        error( 'Invalid invocation.' );
        return undef;
    }

    if( !$bootloaderdevice && exists( $config->{bootloaderdevice} )) {
        $bootloaderdevice = $config->{bootloaderdevice};
    }
    if( !$bootpartition && exists( $config->{bootpartition} )) {
        $bootpartition = $config->{bootpartition};
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
    unless( $self->replaceDevSymlinks( $argvp )) {
        error( $@ );
        return undef;
    }

    my $ret = 1; # set to something, so undef can mean error
    if( $directory ) {
        # Option 4 (invalid)
        error( 'Invalid invocation: --directory cannot be used with this device class. Did you mean to install for a container?' );
        $ret = undef;

    } elsif( $bootloaderdevice || $bootpartition || @rootpartitions || @ubospartitions || @swappartitions ) {
        # Option 3
        $self->{partitioningscheme} = 'mbr';

        if( $noswap ) {
            error( 'Invalid invocation: --noswap cannot be used if specifying partitions' );
            $ret = undef;
        }

        if( $ret && @$argvp ) {
            error( 'Invalid invocation: either specify entire disks, or partitions; do not mix' );
            $ret = undef;
        }
        if( $ret && !$bootloaderdevice ) {
            error( 'Invalid invocation: Device class pc requires a --bootloaderdevice parameter when specifying partitions' );
            $ret = undef;
        }
        if( $ret && @rootpartitions == 0 ) {
            error( 'Invalid invocation: A --rootpartition must be provided when specifying partitions' );
            $ret = undef;
        }
        if( $ret && !UBOS::Install::AbstractDiskLayout::isDisk( $bootloaderdevice ) && !UBOS::Install::AbstractDiskLayout::isLoopDevice( $bootloaderdevice )) {
            error( 'Provided bootloaderdevice is not a disk:', $bootloaderdevice );
            $ret = undef;
        }
        if( $ret && $bootpartition && !UBOS::Install::AbstractDiskLayout::isPartition( $bootpartition )) {
            error( 'Provided bootpartition is not a partition:', $bootpartition );
            $ret = undef;
        }
        my %haveAlready = ();
        if( defined( $bootpartition )) {
            $haveAlready{$bootpartition} = 1;
        }

        if( $ret ) {
            foreach my $part ( @rootpartitions, @ubospartitions, @swappartitions ) {
                if( $haveAlready{$part}) {
                    error( 'Specified more than once:', $part );
                    $ret = undef;
                    last;
                }
                unless( UBOS::Install::AbstractDiskLayout::isPartition( $part )) {
                    error( 'Not a partition:', $part );
                    $ret = undef;
                    last;
                }
                if( UBOS::Install::AbstractDiskLayout::determineMountPoint( $part )) {
                    error( 'Cannot install to mounted disk:', $part );
                    $ret = undef;
                    last;
                }
                $haveAlready{$part} = 1;
            }
        }
        if( $ret ) {
            my $devicetable      = {};
            my $devicetableIndex = 1;

            if( $bootpartition ) {
                $devicetable->{'/boot'} = {
                    'index'   => $devicetableIndex++,
                    'fs'      => 'ext4',
                    'devices' => [ $bootpartition ],
                    'mbrboot' => 1
                     # default partition type
                };
            }
            $devicetable->{'/'} = {
                'index'   => $devicetableIndex++,
                'fs'      => 'btrfs',
                'devices' => \@rootpartitions
                     # default partition type
            };
            if( @ubospartitions ) {
                $devicetable->{'/ubos'} = {
                    'index'   => $devicetableIndex++,
                    'fs'      => 'btrfs',
                    'devices' => \@ubospartitions
                         # default partition type
                };
            }
            if( @swappartitions ) {
                $devicetable->{'swap'} = {
                    'index'       => $devicetableIndex++,
                    'fs'          => 'swap',
                    'devices'     => \@swappartitions,
                    'mbrparttype' => '82',
                    'gptparttype' => '8200'
                };
            }
            $ret = UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector->new(
                    $bootloaderdevice,
                    $devicetable );
        }

    } else {
        # Option 1 or 2
        if( @$argvp ) {
            my $first = $argvp->[0];
            if( $ret && UBOS::Install::AbstractDiskLayout::isFile( $first )) {
                # Option 1
                if( $noswap ) {
                    error( 'Invalid invocation: --noswap cannot be used when installing to a file' );
                    $ret = undef;
                } elsif( @$argvp>1 ) {
                    error( 'Do not specify more than one disk image; cannot RAID disk images' );
                    $ret = undef;
                } else {
                    if( 'gpt' eq $self->{partitioningscheme} ) {
                        $ret = UBOS::Install::DiskLayouts::GptDiskImage->new(
                                $first,
                                {
                                    '/mbr' => {
                                        'index'       => 1,
                                        'size'        => 2048, # 1M at 512/sector
                                        'gptparttype' => 'EF02',
                                        'label'       => 'BIOS_boot'
                                        # no filesystem, do not mount
                                    },
                                    '/boot' => {
                                        'index'       => 2,
                                        'fs'          => 'vfat',
                                        'size'        => 1024*1024, # 512M at 512/sector
                                        'mkfsflags'   => '-F32',
                                        'gptparttype' => 'EF00',
                                        'label'       => 'UBOS_boot'
                                    },
                                    '/' => {
                                        'index' => 3,
                                        'fs'    => 'btrfs',
                                        'label' => 'UBOS_root'
                                        # default partition type
                                    }
                                } );
                    } else {
                        $ret = UBOS::Install::DiskLayouts::MbrDiskImage->new(
                                $first,
                                {   '/boot' => {
                                        'index'   => 1,
                                        'fs'      => 'ext4',
                                        'size'    => 200 * 1024, # 100M at 512/sector
                                        'mbrboot' => 1
                                        # default partition type
                                    },
                                    '/' => {
                                        'index' => 2,
                                        'fs'    => 'btrfs'
                                        # default partition type
                                    }
                                } );
                    }
                }
            } elsif( $ret && UBOS::Install::AbstractDiskLayout::isBlockDevice( $first )) {
                # Option 2
                if( UBOS::Install::AbstractDiskLayout::determineMountPoint( $first )) {
                    error( 'Cannot install to mounted disk:', $first );
                    $ret = undef;
                } else {
                    my %haveAlready = ( $first => 1 );
                    foreach my $disk ( @$argvp ) {
                        if( $first eq $disk ) {
                            next;
                        }
                        if( $haveAlready{$disk} ) {
                            error( 'Specified more than once:', $disk );
                            $ret = undef;
                            last;
                        }
                        unless( UBOS::Install::AbstractDiskLayout::isBlockDevice( $disk )) {
                            error( 'Not a block device:', $disk );
                            $ret = undef;
                            last;
                        }
                        $haveAlready{$disk} = 1;
                    }
                    if( $ret ) {
                        if( 'gpt' eq $self->{partitioningscheme} ) {
                            my $deviceTable = {
                                '/mbr' => {
                                     'index'       => 1,
                                     'size'        => 2048, # 1M at 512/sector
                                     'gptparttype' => 'EF02',
                                     'label'       => 'BIOS_boot'
                                     # no filesystem, do not mount
                                },
                                '/boot' => {
                                    'index'       => 2,
                                    'fs'          => 'vfat',
                                    'size'        => 1024 * 1024, # 512M at 512/sector
                                    'mkfsflags'   => '-F32',
                                    'gptparttype' => 'EF00',
                                    'label'       => 'UBOS_boot'
                                },
                                '/' => {
                                    'index' => 3,
                                    'fs'    => 'btrfs',
                                    'label' => 'UBOS_root'
                                    # default partition type
                                }
                            };
                            unless( $noswap ) {
                                $deviceTable->{swap} = {
                                    'index'       => 4,
                                    'fs'          => 'swap',
                                    'size'        => 8192 * 1024, # 4G at 512/sector
                                    'mbrparttype' => '82',
                                    'gptparttype' => '8200',
                                    'label'       => 'swap'
                                };
                            }
                            $ret = UBOS::Install::DiskLayouts::GptDiskBlockDevices->new(
                                    $argvp,
                                    $deviceTable );
                        } else {
                            my $deviceTable = {
                                '/boot' => {
                                    'index'   => 1,
                                    'fs'      => 'ext4',
                                    'size'    => '100M',
                                    'mbrboot' => 1
                                    # default partition type
                                },
                                '/' => {
                                    'index' => 2,
                                    'fs'    => 'btrfs'
                                    # default partition type
                                }
                            };
                            unless( $noswap ) {
                                $deviceTable->{swap} = {
                                    'index'       => 3,
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
                    }
                }
            } elsif( $ret ) {
                error( 'Must be file or disk:', $first );
                $ret = undef;
            }
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

    return 'pc';
}

##
# Help text
sub help {
    return 'Root disk for PC (x86_64)';
}
1;
