#
# Abstract superclass for device-specific installers. Device-specific parts are
# factored out in methods that can be overridden in subclasses.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::AbstractInstaller;

use Cwd;
use File::Spec;
use File::Temp;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

use fields qw(
        hostname channel
        kernelPackage
        productInfo
        swap
        partitioningScheme

        basePackages         devicePackages         additionalPackages
        baseServices         deviceServices         additionalServices
        baseKernelModules    deviceKernelModules    additionalKernelModules
        baseKernelParameters deviceKernelParameters additionalKernelParameters

        installDepotRoot         runDepotRoot
        installCheckSignatures   runCheckSignatures
        installPackageDbs        runPackageDbs
        installDisablePackageDbs runDisablePackageDbs
        installAddPackageDbs     runAddPackageDbs
        installRemovePackageDbs  runRemovePackageDbs

        mbrBootloaderDevices
        bootPartitions
        rootPartitions
        ubosPartitions
        swapPartitions
        installTargets

        target
        tempMount
        volumeLayout
);

# installXXX: settings for installation time (e.g. which software depot to use)
# runXXX      settings for run-time when the installed devices is operated

# baseXXX:       always installed/activated, regardless of device class
# deviceXXX:     installed/activated for this device class, but not nothers
# additionalXXX: packages installed/activated because of extra options

# tempMount: where the being-installed system is mounted temporarily if it is
#            (most VolumeLayouts but not Directory)
# target:    the location of the being-installed system
#            (all VolumeLayouts)

##
# Constructor
sub new {
    my $self = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    # init happens in checkComplete()

    return $self;
}

##
# Obtain the target directory in which the installation takes place
# return: target directory
sub getTarget {
    my $self = shift;

    return $self->{target};
}

##
# Set the DeviceConfiguration from the provided hash.
# return: number of errors
sub setDeviceConfig {
    my $self         = shift;
    my $deviceConfig = shift;

    my $errors = 0;

    if( exists( $deviceConfig->{hostname} )) {
        $self->{hostname} = $deviceConfig->{hostname};
    }
    if( exists( $deviceConfig->{channel} )) {
        $self->{channel} = $deviceConfig->{channel};
    }
    if( exists( $deviceConfig->{productinfo} )) {
        $self->{productInfo} = $deviceConfig->{productinfo};
    }
    if( exists( $deviceConfig->{additionalpackages} )) {
        $self->{additionalPackages} = $deviceConfig->{additionalpackages};
    }
    if( exists( $deviceConfig->{additionalservices} )) {
        $self->{additionalServices} = $deviceConfig->{additionalservices};
    }
    if( exists( $deviceConfig->{additionalkernelmodules} )) {
        $self->{additionalKernelModules} = $deviceConfig->{additionalkernelmodules};
    }
    if( exists( $deviceConfig->{additionalkernelparameters} )) {
        $self->{additionalKernelParameters} = $deviceConfig->{additionalkernelparameters};
    }
    if( exists( $deviceConfig->{installdepotroot} )) {
        $self->{installDepotRoot} = $deviceConfig->{installdepotroot};
    }
    if( exists( $deviceConfig->{rundepotroot} )) {
        $self->{runDepotRoot} = $deviceConfig->{rundepotroot};
    }
    if( exists( $deviceConfig->{installchecksignatures} )) {
        $self->{installCheckSignatures} = $deviceConfig->{installchecksignatures};
    }
    if( exists( $deviceConfig->{runchecksignatures} )) {
        $self->{runCheckSignatures} = $deviceConfig->{runchecksignatures};
    }

    if( exists( $deviceConfig->{installaddpackagedbs} )) {
        $self->{installAddPackageDbs} = $deviceConfig->{installaddpackagedbs};
    }
    if( exists( $deviceConfig->{runaddpackagedbs} )) {
        $self->{runAddPackageDbs} = $deviceConfig->{runaddpackagedbs};
    }
    if( exists( $deviceConfig->{installdisablepackagedbs} )) {
        $self->{installDisablePackageDbs} = $deviceConfig->{installdisablepackagedbs};
    }
    if( exists( $deviceConfig->{rundisablepackagedbs} )) {
        $self->{runDisablePackageDbs} = $deviceConfig->{rundisablepackagedbs};
    }
    if( exists( $deviceConfig->{installremovepackagedbs} )) {
        $self->{installRemovePackageDbs} = $deviceConfig->{installremovepackagedbs};
    }
    if( exists( $deviceConfig->{runremovepackagedbs} )) {
        $self->{runRemovePackageDbs} = $deviceConfig->{runremovepackagedbs};
    }

    if( exists( $deviceConfig->{swap} )) {
        $self->{swap} = $deviceConfig->{swap};
    }
    if( exists( $deviceConfig->{partitioningscheme} )) {
        $self->{partitioningScheme} = $deviceConfig->{partitioningscheme};
    }
    if( exists( $deviceConfig->{mbrbootloaderdevices} )) {
        $self->{mbrBootloaderDevices} = $deviceConfig->{mbrbootloaderdevices};
    }
    if( exists( $deviceConfig->{bootpartitions} )) {
        $self->{bootPartitions} = $deviceConfig->{bootpartitions};
    }
    if( exists( $deviceConfig->{rootpartitions} )) {
        $self->{rootPartitions} = $deviceConfig->{rootpartitions};
    }
    if( exists( $deviceConfig->{ubospartitions} )) {
        $self->{ubosPartitions} = $deviceConfig->{ubospartitions};
    }
    if( exists( $deviceConfig->{swappartitions} )) {
        $self->{swapPartitions} = $deviceConfig->{swappartitions};
    }
    if( exists( $deviceConfig->{installtargets} )) {
        $self->{installTargets} = $deviceConfig->{installtargets};
    }

    return $errors;
}

##
# Check that provided information is correct, and complete incomplete items
# from defaults.
# return: number of errors.
sub checkComplete {
    my $self = shift;

    my $errors = $self->checkCompleteParameters();

    $errors += $self->checkCreateVolumeLayout();

    return $errors;
}

##
# Check that the provided parameters are correct, and complete incomplete items from
# default except for the disk layout.
# return: number of errors.
sub checkCompleteParameters {
    my $self = shift;

    my $errors = 0;

    if( $self->{partitioningScheme} ) {
        if( $self->{partitioningScheme} ne 'gpt' && $self->{partitioningScheme} ne 'mbr' && $self->{partitioningScheme} ne 'gpt+mbr' ) {
            error( 'Partitioning scheme must be one of gpt, mbr or gpt+mbr, not:', $self->{partitioningScheme} );
            ++$errors;
        }
    }

    unless( $self->{hostname} ) {
        $self->{hostname} = 'ubos-' . $self->arch() . '-' . $self->deviceClass();
    }
    $self->{hostname} = UBOS::Utils::isValidHostname( $self->{hostname} );
    unless( $self->{hostname} ) {
        error( $@ );
        ++$errors;
    }

    unless( $self->{channel} ) {
        $self->{channel} = 'green';
    }
    $self->{channel} = UBOS::Utils::isValidChannel( $self->{channel} );
    unless( $self->{channel} ) {
        error( $@ );
        ++$errors;
    }

    if( $self->{productInfo} ) {
        foreach my $entry ( qw( name vendor sku )) {
            if( exists( $self->{productInfo}->{$entry} )) {
                if( ref( $self->{productInfo}->{$entry} )) {
                    error( 'Product info entry', $entry, 'must be a string' );
                }
            }
        }
    }

    unless( $self->{basePackages} ) {
        $self->{basePackages} = [
            qw( ubos-base )
        ];
    }

    unless( $self->{devicePackages} ) {
        $self->{devicePackages} = [];
    }

    unless( $self->{additionalPackages} ) {
        $self->{additionalPackages} = [];
    }

    unless( $self->{baseServices} ) {
        $self->{baseServices} = [
             qw( ubos-admin.service ubos-ready.service sshd.service snapper-timeline.timer snapper-cleanup.timer )
        ];
    }

    unless( $self->{deviceServices} ) {
        $self->{deviceServices} = [];
    }

    unless( $self->{additionalServices} ) {
        $self->{additionalServices} = [];
    }

    unless( $self->{baseKernelModules} ) {
        $self->{baseKernelModules} = [];
    }

    unless( $self->{deviceKernelModules} ) {
        $self->{deviceKernelModules} = [];
    }

    unless( $self->{additionalKernelModules} ) {
        $self->{additionalKernelModules} = [];
    }

    unless( $self->{baseKernelParameters} ) {
        $self->{baseKernelParameters} = [
            'init=/usr/lib/systemd/systemd'
        ];
    }

    unless( $self->{deviceKernelParameters} ) {
        $self->{deviceKernelParameters} = [];
    }

    unless( $self->{additionalKernelParameters} ) {
        $self->{additionalKernelParameters} = [];
    }

    unless( $self->{installDepotRoot} ) {
        $self->{installDepotRoot} = 'http://depot.ubos.net';
    }
    if( $self->{installDepotRoot} !~ m!^(http|https|ftp)://! && ! -d $self->{installDepotRoot} ) {
        error( 'Install depot root must be a URL or a directory:', $self->{installDepotRoot} );
        ++$errors;
    }

    unless( $self->{runDepotRoot} ) {
        $self->{runDepotRoot} = $self->{installDepotRoot};
    }
    if( $self->{runDepotRoot} !~ m!^(http|https|ftp)://! ) {
        error( 'Run depot root must be a URL:', $self->{runDepotRoot} );
        ++$errors;
    }

    # Would be nice to check that repos exist, but that's hard if
    # they are remote

    unless( $self->{installCheckSignatures} ) {
        $self->{installCheckSignatures} = 'always';
    }
    if( $self->{installCheckSignatures} !~ m!^(never|optional|always)$! ) {
        error( 'Install check signatures must be one of never, optional, always:', $self->{installCheckSignatures} );
        ++$errors;
    }

    unless( $self->{runCheckSignatures} ) {
        $self->{runCheckSignatures} = $self->{installCheckSignatures};
    }
    if( $self->{runCheckSignatures} !~ m!^(never|optional|always)$! ) {
        error( 'Run check signatures must be one of never, optional, always:', $self->{runCheckSignatures} );
        ++$errors;
    }

    unless( $self->{installPackageDbs} ) {
        $self->{installPackageDbs} = {
                'os'      => '$depotRoot/$channel/$arch/os',
                'hl'      => '$depotRoot/$channel/$arch/hl',
                'tools'   => '$depotRoot/$channel/$arch/tools',
                'toyapps' => '$depotRoot/$channel/$arch/toyapps',

                'os-experimental'    => '$depotRoot/$channel/$arch/os-experimental',
                'hl-experimental'    => '$depotRoot/$channel/$arch/hl-experimental',
                'tools-experimental' => '$depotRoot/$channel/$arch/tools-experimental'
        }; # These constants get replaced later
    }

    unless( $self->{runPackageDbs} ) {
        $self->{runPackageDbs} = $self->{installPackageDbs};
    }

    unless( $self->{installDisablePackageDbs} ) {
        $self->{installDisablePackageDbs} = [ qw(
                toyapps
                os-experimental
                hl-experimental
                tools-experimental
        ) ];
    }

    unless( $self->{runDisablePackageDbs} ) {
        $self->{runDisablePackageDbs} = $self->{installDisablePackageDbs}; # same
    }

    unless( $self->{installAddPackageDbs} ) {
        $self->{installAddPackageDbs} = {};
    }

    unless( $self->{runAddPackageDbs} ) {
        $self->{runAddPackageDbs} = $self->{installAddPackageDbs};
    }

    unless( $self->{installRemovePackageDbs} ) {
        $self->{installRemovePackageDbs} = {};
    }

    unless( $self->{runRemovePackageDbs} ) {
        $self->{runRemovePackageDbs} = $self->{installRemovePackageDbs};
    }

    unless( $self->{mbrBootloaderDevices} ) {
        $self->{mbrBootloaderDevices} = [];
    }

    unless( $self->{bootPartitions} ) {
        $self->{bootPartitions} = [];
    }

    unless( $self->{rootPartitions} ) {
        $self->{rootPartitions} = [];
    }

    unless( $self->{ubosPartitions} ) {
        $self->{ubosPartitions} = [];
    }

    unless( $self->{swapPartitions} ) {
        $self->{swapPartitions} = [];
    }

    if( $self->{installTargets} ) {
        $self->replaceDevSymlinks( $self->{installTargets} );
    } else {
        $self->{installTargets} = [];
    }

    return $errors;
}

##
# Check the VolumeLayout parameters, and create a VolumeLayout member.
# return: number of errors
sub checkCreateVolumeLayout {
    my $self = shift;

    error( 'checkCreateVolumeLayout Must be overridden' );

    return 1;
}

##
# Install UBOS
# $diskLayout: the disk layout to use
sub install {
    my $self = shift;

    info( 'Installing UBOS with hostname', $self->{hostname} );

    unless( $self->{target} ) {
        my $tmpDir = UBOS::Host::vars()->getResolve( 'host.tmp', '/tmp' );
        $self->{tempMount} = File::Temp->newdir( DIR => $tmpDir, UNLINK => 1 );
        $self->{target}    = $self->{tempMount}->dirname;
    }

    my $errors = 0;

    my $pacmanConfigInstallContent = $self->generateInstallPacmanConfig();

    my $pacmanConfigInstall = File::Temp->new( UNLINK => 1 );
    if( $pacmanConfigInstall ) {
        print $pacmanConfigInstall $pacmanConfigInstallContent;
        close $pacmanConfigInstall;

    } else {
        error( 'Failed to create temporary pacman config file' );
        ++$errors;
    }
    if( $errors ) {
        goto DONE;
    }

    my $evalResult = eval {
        $errors += $self->{volumeLayout}->createVolumes();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->{volumeLayout}->createLoopDevices();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->{volumeLayout}->formatVolumes();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->{volumeLayout}->mountVolumes( $self );
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->mountSpecial();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->{volumeLayout}->createSubvols( $self );
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->installPackages( $pacmanConfigInstall );
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->saveRunPacmanConfig();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->saveHostname();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->saveChannel();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->{volumeLayout}->saveFstab( $self );
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->saveModules();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->saveSecuretty();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->saveOther();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->configureOs();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->configureNetworkd();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->doUpstreamFixes();
        if( $errors ) {
            goto DONE;
        }

        $errors += $self->installRamdisk();
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->installBootLoader( $pacmanConfigInstall );
        if( $errors ) {
            goto DONE;
        }

        my $chrootScript = <<'SCRIPT';
#!/bin/bash
# Script to be run in chroot
set -e

# In a container, there may be no /lib/modules
if [ -d /lib/modules ]; then
    for v in $(ls -1 /lib/modules | grep -v extramodules); do depmod -a $v; done
    # Force the version; required so it works to install a newer kernel
    # version compared to that of the currently running system
fi

systemctl set-default multi-user.target

echo 'root:ubos!4vr' | chpasswd

SCRIPT
        $errors += $self->addGenerateLocaleToScript( \$chrootScript );
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->addEnableServicesToScript( \$chrootScript );
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->addConfigureNetworkingToScript( \$chrootScript );
        if( $errors ) {
            goto DONE;
        }
        $errors += $self->addConfigureSnapperToScript( \$chrootScript );
        if( $errors ) {
            goto DONE;
        }

        trace( "chroot script:\n" . $chrootScript );

        my $out;
        my $err;
        if( UBOS::Utils::myexec( "chroot '" . $self->{target} . "'", $chrootScript, \$out, \$err )) {
            error( "chroot script failed", $err );
            ++$errors;
            debugAndSuspend( 'Check what went wrong?' );
            if( $errors ) {
                goto DONE;
            }
        }

        $errors += $self->cleanup();
        if( $errors ) {
            goto DONE;
        }
        1;
    };
    unless( $evalResult ) {
        error( 'An unexpected error occurred:', $@ );
        ++$errors;
    }

    DONE:

    # No GOTO from here in case of errors, we are trying to clean up
    $errors += $self->umountSpecial();
    $errors += $self->{volumeLayout}->umountVolumes( $self );

    $errors += $self->{volumeLayout}->deleteLoopDevices();

    return $errors;
}

##
# Mount special devices in target dir, so packages can install correctly
sub mountSpecial {
    my $self = shift;

    trace( "Executing mountSpecial" );

    my $target = $self->{target};
    my $errors = 0;

    my $s = <<END;
mkdir -m 0755 -p $target/var/{cache/pacman/pkg,lib/pacman} $target/{dev,run,etc}
mkdir -m 1777 -p $target/tmp
mkdir -m 0555 -p $target/{sys,proc}

mount proc   $target/proc    -t proc     -o nosuid,noexec,nodev
mount sys    $target/sys     -t sysfs    -o nosuid,noexec,nodev,ro
mount udev   $target/dev     -t devtmpfs -o mode=0755,nosuid
mount devpts $target/dev/pts -t devpts   -o mode=0620,gid=5,nosuid,noexec
mount shm    $target/dev/shm -t tmpfs    -o mode=1777,nosuid,nodev
mount run    $target/run     -t tmpfs    -o nosuid,nodev,mode=0755
mount tmp    $target/tmp     -t tmpfs    -o mode=1777,strictatime,nodev,nosuid
END

    if( UBOS::Utils::myexec( $s )) {
        ++$errors;
    }
    return $errors;
}

##
# Unmount special devices from target dir
sub umountSpecial {
    my $self = shift;

    trace( "Executing unmountSpecial" );

    my $target = $self->{target};
    my $errors = 0;

    my $s = <<END;
umount $target/tmp
umount $target/run
umount $target/dev/shm
umount $target/dev/pts
umount $target/dev
umount $target/sys
umount $target/proc
END

    # If something went wrong earlier, these may not be mounted, so we ignore errors.
    my $out;
    UBOS::Utils::myexec( $s, undef, \$out, \$out );
    trace( 'Unmounting result:', $out );

    return $errors;
}

##
# Generate the content of the install-time pacman config file
# $dbs: array of package database names
# return: File object of the generated temp file
sub generateInstallPacmanConfig {
    my $self = shift;

    trace( "Executing generateInstallPacmanConfig" );

    my $depotRoot   = $self->{installDepotRoot};
    my $channel     = $self->{channel};
    my $arch        = $self->arch;
    my $levelString = $self->getPacmanSigLevelStringFor( $self->{installCheckSignatures} );

    my $ret  = <<END;
#
# Pacman config file for installing packages
#

[options]
Architecture = $arch

SigLevel           = $levelString
LocalFileSigLevel  = $levelString
RemoteFileSigLevel = $levelString
END

    my %bothDbs = ( %{ $self->{installPackageDbs} }, %{ $self->{installAddPackageDbs} } );
    foreach my $dbKey ( sort keys %bothDbs ) {
        if( exists( $self->{installRemovePackageDbs}->{$dbKey} )) {
            next;
        }

        my $dbValue = $bothDbs{$dbKey};
        $dbValue =~ s!\$depotRoot!$depotRoot!g;
        $dbValue =~ s!\$channel!$channel!g;

        my $prefix = '';
        if( grep /^$dbKey$/, @{$self->{installDisablePackageDbs}} ) {
            $prefix = '# ';
        }
        my $dbFile  = $prefix . "[$dbKey]\n";
        $dbFile    .= $prefix . "Server = $dbValue\n";

        $ret .= "\n" . $dbFile;
    }
    return $ret;
}

##
# Install the packages that need to be installed
# $installPacmanConfig: the pacman config file to use
#
sub installPackages {
    my $self                = shift;
    my $installPacmanConfig = shift;

    info( "Installing packages" );

    my $target = $self->{target};
    my $errors = 0;

    my @allPackages = ();
    if( $self->{kernelPackage} ) {
        push @allPackages, $self->{kernelPackage};
    }
    push @allPackages, @{$self->{basePackages}};
    if( defined( $self->{devicePackages} )) {
        push @allPackages, @{$self->{devicePackages}};
    }
    if( defined( $self->{additionalPackages} )) {
        push @allPackages, @{$self->{additionalPackages}};
    }

    my $cmd = "pacman"
            . " --root '$target'"
            . " -Sy"
            . " '--config=$installPacmanConfig'"
            . " --cachedir '/var/cache/pacman/pkg'"
            . " --noconfirm"
            . ' ' . join( ' ', @allPackages );

    debugAndSuspend( 'Installing packages', @allPackages );

    my $out;
    if( UBOS::Utils::myexec( $cmd, undef, \$out, \$out )) {
        error( "pacman failed:", $out );
        trace( "pacman configuration was:\n" . UBOS::Utils::slurpFile( $installPacmanConfig ));
        ++$errors;
    }

    return $errors;
}

##
# Generate and save the pacman config file for the device run-time
sub saveRunPacmanConfig {
    my $self = shift;

    trace( "Executing savePacmanConfigProduction" );

    my $errors      = 0;
    my $arch        = $self->arch;
    my $channel     = $self->{channel};
    my $target      = $self->{target};
    my $depotRoot   = $self->{runDepotRoot};
    my $levelString = $self->getPacmanSigLevelStringFor( $self->{runCheckSignatures} );

    my $runPacmanConfig = <<END;
#
# Pacman config file for UBOS
#

[options]
Architecture = $arch
CheckSpace

SigLevel           = $levelString
LocalFileSigLevel  = $levelString
RemoteFileSigLevel = $levelString

END
    unless( UBOS::Utils::saveFile( "$target/etc/pacman.conf", $runPacmanConfig, 0644 )) {
        ++$errors;
    }

    unless( -d "$target/etc/pacman.d/repositories.d" ) {
        unless( UBOS::Utils::mkdir( "$target/etc/pacman.d/repositories.d" )) {
            ++$errors;
        }
    }

    my %bothDbs = ( %{ $self->{runPackageDbs} }, %{ $self->{runAddPackageDbs} } );
    foreach my $dbKey ( sort keys %bothDbs ) {
        if( exists( $self->{runRemovePackageDbs}->{$dbKey} )) {
            next;
        }

        my $dbValue = $bothDbs{$dbKey};
        $dbValue =~ s!\$depotRoot!$depotRoot!g;

        my $prefix = '';
        my $dbFile = '';
        if( grep /^$dbKey$/, @{$self->{runDisablePackageDbs}} ) {
            $prefix = '# ';
            $dbFile .= $prefix . "Remove the # from the next two lines and run `ubos-admin update' to enable package db $dbKey\n";
        }
        $dbFile .= $prefix . "[$dbKey]\n";
        $dbFile .= $prefix . "Server = $dbValue\n";

        unless( UBOS::Utils::saveFile( "$target/etc/pacman.d/repositories.d/$dbKey", $dbFile, 0644 )) {
            ++$errors;
        }
    }

    unless( UBOS::Utils::regeneratePacmanConf( "$target/etc/pacman.conf", "$target/etc/pacman.d/repositories.d", $channel )) {
        ++$errors;
    }
    return $errors;
}

##
# Generate and save the /etc/hostname file
sub saveHostname {
    my $self = shift;

    trace( "Executing saveHostname" );

    my $errors = 0;

    unless( UBOS::Utils::saveFile(
            $self->{target}   . '/etc/hostname',
            $self->{hostname} . "\n",
            0644, 'root', 'root' )) {
        ++$errors;
    }
    return $errors;
}

##
# Generate and save the /etc/ubos/channel file
sub saveChannel {
    my $self = shift;

    trace( "Executing saveChannel" );

    my $errors = 0;

    unless( UBOS::Utils::saveFile(
            $self->{target}   . '/etc/ubos/channel',
            $self->{channel} . "\n",
            0644, 'root', 'root' )) {
        ++$errors;
    }
    return $errors;
}

##
# Generate and save kernel module load files if needed
sub saveModules {
    my $self = shift;

    my $target = $self->{target};
    my $errors = 0;

    foreach my $t ( qw( baseKernelModules deviceKernelModules additionalKernelModules )) {
        if( defined( $self->{$t} ) && @{$self->{$t}} ) {
            unless( UBOS::Utils::saveFile( "$target/etc/modules-load.d/$t.conf", join( "\n", @{$self->{$t}} ) . "\n" )) {
                error( 'Failed to save modules load file for', $t );
                ++$errors;
            }
        }
    }

    return $errors;
}

##
# Generate and save a different /etc/securetty if needed
# return: number of errors
sub saveSecuretty {
    my $self  = shift;

    # do nothing by default

    return 0;
}

##
# Generate and save different other files if needed
# return: number of errors
sub saveOther {
    my $self = shift;

    # do nothing by default

    return 0;
}

##
# Configure the installed OS
# return: number of errors
sub configureOs {
    my $self = shift;

    my $target        = $self->{target};
    my $channel       = $self->{channel};
    my $buildId       = UBOS::Utils::time2string( time() );
    my $deviceClass   = $self->deviceClass();
    my $kernelPackage = $self->{kernelPackage};
    my $productInfo   = $self->{productInfo};
    my $errors        = 0;

    # Limit size of system journal
    trace( "System journal" );
    if( UBOS::Utils::myexec( "perl -pi -e 's/^\\s*(#\\s*)?SystemMaxUse=.*\$/SystemMaxUse=50M/' '$target/etc/systemd/journald.conf'" )) {
        error( 'Failed to limit size of system journal' );
        ++$errors;
    }

    # version
    trace( "OS version info" );

    unless( UBOS::Utils::regenerateEtcIssue( $deviceClass, $channel, $target )) {
        ++$errors;
    }

    my $osRelease = <<OSRELEASE;
NAME="UBOS"
ID="ubos"
ID_LIKE="arch"
PRETTY_NAME="UBOS"
HOME_URL="http://ubos.net/"
BUILD_ID="$buildId"
UBOS_DEVICECLASS="$deviceClass"
DOCUMENTATION_URL="https://ubos.net/docs/"
OSRELEASE
    if( $kernelPackage ) {
        $osRelease .= <<OSRELEASE;
UBOS_KERNELPACKAGE="$kernelPackage"
OSRELEASE
    }
    unless( UBOS::Utils::saveFile( $target . '/etc/os-release', $osRelease, 0644, 'root', 'root' )) {
        ++$errors;
    }

    if( $productInfo ) {
        unless( UBOS::Utils::writeJsonToFile( $target . '/etc/ubos/product.json', $productInfo, 0644, 'root', 'root' )) {
            ++$errors;
        }
    }
    return 0;
}

##
# Configure systemd-networkd
# return: number of errors
sub configureNetworkd {
    my $self = shift;

    my $errors = 0;
    my $target = $self->{target};

    if( -e ( $target . '/etc/resolv.conf' ) && !UBOS::Utils::deleteFile( $target . '/etc/resolv.conf' )) {
        error( 'Failed to delete file', $target . '/etc/resolv.conf' );
        ++$errors;
    }
    unless( UBOS::Utils::symlink( '/run/systemd/resolve/resolv.conf', $target . '/etc/resolv.conf' )) {
        error( 'Failed to symlink', $target . '/etc/resolv.conf' );
        ++$errors;
    }

    # remove [!UNAVAIL=return]
    my $nsswitch = UBOS::Utils::slurpFile( $target . '/etc/nsswitch.conf' );
    if( $nsswitch ) {
        $nsswitch =~ s/\[!UNAVAIL=return\] *//;
        unless( UBOS::Utils::saveFile( $target . '/etc/nsswitch.conf', $nsswitch )) {
            error( 'Failed to save file', $target . '/etc/nsswitch.conf' );
            ++$errors;
        }
    } else {
        ++$errors;
    }

    # Set DNSSec=no
    my $conf = UBOS::Utils::slurpFile( $target . '/etc/systemd/resolved.conf' );
    if( $conf ) {
        $conf =~ s!^#*DNSSEC.*$!DNSSEC=No!m;
        unless( UBOS::Utils::saveFile( $target . '/etc/systemd/resolved.conf', $conf )) {
            error( 'Failed to save file', $target . '/etc/systemd/resolved.conf' );
            ++$errors;
        }
    } else {
        ++$errors;
    }

    return $errors;
}

##
# Do whatever necessary to fix upstream bugs
sub doUpstreamFixes {
    my $self = shift;

    return 0;
}

##
# Install a Ram disk
# return: number of errors
sub installRamdisk {
    my $self       = shift;

    # by default, do nothing

    return 0;
}

##
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;

    error( 'Method installBootLoader() must be overridden for', ref( $self ));

    return 1;
}

##
# Configure smartd (from smartmontools)
# return: number of errors
sub configureSmartd {
    my $self = shift;

    my $target = $self->{target};
    my $confFile = $target . '/etc/smartd.conf';

    if( -e $confFile ) {
        # override with "monitor all" if smartmontools are installed
        UBOS::Utils::saveFile( $confFile, <<CONTENT );
# UBOS default configuration, following Arch recommendation

#    -a (monitor all attributes)
#    -o on (enable automatic online data collection)
#    -S on (enable automatic attribute autosave)
#    -n standby,q (do not check if disk is in standby, and suppress log message to that effect so as not to cause a write to disk)
#    -s ... (schedule short and long self-tests)
#    -W ... (monitor temperature)
# but do not e-mail

DEVICESCAN -a -o on -S on -n standby,q -s (S/../.././02|L/../../6/03) -W 4,35,40

CONTENT
    }

    return 0;
}

##
# Add commands to the provided script, to be run in a chroot, that generates the locale
# $chrootScriptP: pointer to script
sub addGenerateLocaleToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    trace( "Executing addGenerateLocaleToScript" );

    # Run perl with the old locale
    $$chrootScriptP .= "LANG=C perl -pi -e 's/^#en_US\.UTF-8.*\$/en_US.UTF-8 UTF-8/g' '/etc/locale.gen'\n";
    $$chrootScriptP .= "echo LANG=en_US.utf8 > /etc/locale.conf\n";
    $$chrootScriptP .= "locale-gen\n";

    return 0;
}

##
# Add commands to the provided script, to be run in a chroot, that enable services
# $chrootScriptP: pointer to script
sub addEnableServicesToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    trace( "Executing addEnableServicesToScript" );

    my @allServices = ();

    if( defined( $self->{baseServices} )) {
        push @allServices, @{$self->{baseServices}};
    }
    if( defined( $self->{deviceServices} )) {
        push @allServices, @{$self->{deviceServices}};
    }
    if( defined( $self->{additionalServices} )) {
        push @allServices, @{$self->{additionalServices}};
    }
    if( @allServices ) {
        $$chrootScriptP .= 'systemctl enable ' . join( ' ', @allServices ) . "\n\n";
    }
    return 0;
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# networking in the default configuration for this deviceclass
# $chrootScriptP: pointer to script
sub addConfigureNetworkingToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    fatal( 'Method addConfigureNetworkingToScript() must be overridden in', ref( $self ));

    return 0;
}

##
# Add commands to the provided script, to be run in a chroot, that configures
# snapper
# $chrootScriptP: pointer to script
# $diskLayout: the disk layout to use
# return: number of errors
sub addConfigureSnapperToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    trace( "Executing addConfigureSnapperToScript" );

    my $target = $self->{target};

    my $errors = 0;
    my @mountPoints = $self->{volumeLayout}->snapperBtrfsMountPoints();
    foreach my $mountPoint ( @mountPoints ) {
        my $configName = $mountPoint;
        $configName =~ s!/!!g;
        unless( $configName ) {
            $configName = 'root';
        }
        unless( -e "$target/etc/snapper/configs/$configName" ) {
            $$chrootScriptP .= "snapper -c '$configName' --no-dbus create-config -t ubos-default '$mountPoint'\n";
        }
    }
    # Cannot invoke 'snapper setup-quota' here -- it fails with a dbus fatal exception.
    # Presumably it doesn't like the chroot it is running in.
    # So we will have to do this during boot
    return $errors;
}

##
# Clean up after install is done
# return: number of errors
sub cleanup {
    my $self = shift;

    trace( "Executing cleanup" );

    my $target = $self->{target};
    my $errors = 0;

    # don't need installation history
    if( -e "$target/root/.bash_history" ) {
        UBOS::Utils::deleteFile( "$target/root/.bash_history" );
    }

    # Removing content of /var/cache makes image smaller
    my @dirs = ();
    if( opendir(DIR, "$target/var/cache" )) {
        while( my $file = readdir(DIR) ) {
            if( $file eq '.' || $file eq '..' ) {
                next;
            }
            my $d = "$target/var/cache/$file";
            if( -d $d ) {
                push @dirs, $d;
            }
        }
        closedir(DIR);
    } else {
        ++$errors;
    }

    if( @dirs ) {
        unless( UBOS::Utils::deleteRecursively( @dirs )) {
            ++$errors;
        }
    }
    # create /var/cache/pacman/pkg or there will be an unnecessary warning
    unless( UBOS::Utils::mkdirDashP( "$target/var/cache/pacman/pkg", 0755 )) {
        error( 'Failed to create directory', "$target/var/cache/pacman/pkg" );
        ++$errors;
    }

    # /etc/machine-id must be unique, but file cannot be missing as /etc
    # might be mounted as read-only during boot
    unless( UBOS::Utils::saveFile( "$target/etc/machine-id", '' )) {
        error( 'Failed to create file', "$target/etc/machine-id" );
        ++$errors;
    }

    return $errors;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    fatal( 'Method arch() must be overridden in', ref( $self ));
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    fatal( 'Method deviceClass() must be overridden in', ref( $self ));
}

##
# Convert the value of a xxxCheckSignatures field into a string that can be added to
# a pacman.conf file.
# $value: the value provided, such as 'optional'
# return: string, such as "Optional TrustAll"
sub getPacmanSigLevelStringFor {
    my $self = shift;
    my $value = shift;

    my $ret;
    # ubos-install makes sure it is all lowercase
    if( 'never' eq $value ) {
        $ret = 'Never';
    } elsif( 'optional' eq $value ) {
        $ret = 'Optional TrustAll';
    } else { # can't be anything else
        $ret = 'Required TrustedOnly';
    }
    return $ret;
}

##
# Concatenate all kernel parameters
# return: string
sub getAllKernelParameters {
    my $self = shift;

    my $ret = join( ' ', ( @{$self->{baseKernelParameters}}, @{$self->{deviceKernelParameters}}, @{$self->{additionalKernelParameters}} ));
    return $ret;
}

##
# We may have been handed symlinks to devices, not the actual devices,
# so we centrally resolve them here.
# @$devices: device file names (modified in place)
# return: success or failure
sub replaceDevSymlinks {
    my $self    = shift;
    my $devices = shift;

    for( my $i=0 ; $i<@$devices ; ++$i ) {
        my $resolved = UBOS::Utils::absReadlink( $devices->[$i] );
        if( -b $resolved || -f $resolved ) {
            $devices->[$i] = $resolved;
        } else {
            $@ = 'Cannot find device: ' . $devices->[$i];
            return 0;
        }
    }
    return 1;
}

##
# Convenience method to check that no volume-specific parameters is provided other than a single
# installTarget. Used by a bunch of installers and factored out here for convenience.

sub _checkSingleInstallTargetOnly {
    my $self = shift;

    my $errors = 0;
    if( @{$self->{mbrBootloaderDevices}} ) {
        error( 'No MBR boot loader devices must be specified for this device class:', @{$self->{mbrBootloaderDevices}} );
        ++$errors;
    }
    if( @{$self->{bootPartitions}} ) {
        error( 'No boot partitions must be specified for this device class:', @{$self->{bootPartitions}} );
        ++$errors;
    }
    if( @{$self->{rootPartitions}} ) {
        error( 'No root partitions must be specified for this device class:', @{$self->{rootPartitions}} );
        ++$errors;
    }
    if( @{$self->{ubosPartitions}} ) {
        error( 'No ubos partitions must be specified for this device class:', @{$self->{ubosPartitions}} );
        ++$errors;
    }
    if( @{$self->{swapPartitions}} ) {
        error( 'No swap partitions must be specified for this device class:', @{$self->{swapPartitions}} );
        ++$errors;
    }
    if( @{$self->{installTargets}} != 1 ) {
        error( 'A single install target must be specified for this device class:'. @{$self->{installTargets}} );
        ++$errors;
    }
    return $errors;
}

1;
