# 
# Abstract superclass for device-specific installers. Device-specific parts are
# factored out in methods that can be overridden in subclasses.
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

package UBOS::Install::AbstractInstaller;

use fields qw( hostname
               target tempTarget
               repo
               channel
               kernelpackage
               basepackages devicepackages additionalpackages
               baseservices deviceservices additionalservices
               basemodules  devicemodules  additionalmodules
               additionalkernelparameters
               checksignatures
               packagedbs );
# basepackages: always installed, regardless
# devicepackages: packages installed for this device class, but not necessarily all others
# additionalpackages: packages installed because added on the command-line
# *services: same for systemd services
# *modules: same for kernel modules

use Cwd;
use File::Spec;
use File::Temp;
use UBOS::Logging;
use UBOS::Utils;

##
# Constructor
sub new {
    my $self = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    # set some defaults
    unless( $self->{hostname} ) {
        $self->{hostname} = 'ubos-device';
    }
    unless( $self->{channel} ) {
        $self->{channel} = 'yellow'; # FIXME once we have 'green';
    }
    unless( $self->{basepackages} ) {
        $self->{basepackages} = [ qw( ubos-base ubos-networking ) ];
    }
    unless( $self->{baseservices} ) {
        $self->{baseservices} = [ qw( ubos-admin ubos-ready sshd snapper-cleanup ) ];
    }
    unless( $self->{basemodules} ) {
        $self->{basemodules} = [];
    }
    unless( $self->{packagedbs} ) {
        $self->{packagedbs} = [ qw( os hl tools ) ];
    }

    return $self;
}

##
# Create a DiskLayout object that goes with this Installer.
# $argvp: remaining command-line arguments
sub createDiskLayout {
    my $self  = shift;
    my $argvp = shift;

    fatal( 'Must override:', ref( $self ));
}

##
# Set a different hostname
# $hostname: the new hostname
sub setHostname {
    my $self     = shift;
    my $hostname = shift;

    $self->{hostname} = $hostname;
}

##
# Set the target filesystem's mount point
# $target: the mount point, e.g. /mnt
sub setTarget {
    my $self   = shift;
    my $target = shift;

    $self->{target} = $target;
}

##
# Set the directory which contains the package databases
# $repo: the directory, so that $repo/<arch>/os/os.db exists
sub setRepo {
    my $self = shift;
    my $repo = shift;

    $self->{repo} = $repo;
}

##
# Set the channel
# $channel: the channel
sub setChannel {
    my $self    = shift;
    my $channel = shift;

    $self->{channel} = $channel;
}

##
# Add packages that are to be installed in addition
# @packages: array of package names
sub addPackages {
    my $self     = shift;
    my @packages = @_;

    push @{$self->{additionalpackages}}, @packages;
}

##
# Add services that are to be enabled in addition
# @services: array of service names
sub addServices {
    my $self     = shift;
    my @services = @_;

    push @{$self->{additionalservices}}, @services;
}

##
# Add kernel modules that are to be loaded in addition
# @modules: array of kernel module names
sub addModules {
    my $self    = shift;
    my @modules = @_;

    push @{$self->{additionalmodules}}, @modules;
}

##
# Add kernel parameters for the kernel boot
# @modules: array of parameter strings
sub addKernelParameters {
    my $self = shift;
    my @pars = @_;

    push @{$self->{additionalkernelparameters}}, @pars;
}

##
# Set whether package signatures should be checked. This applies to install
# time and to run-time.
# $check: never, optional or required
sub setCheckSignatures {
    my $self  = shift;
    my $check = shift;

    $self->{checksignatures} = $check;
}

##
# Install UBOS
# $diskLayout: the disk layout to use
sub install {
    my $self       = shift;
    my $diskLayout = shift;

    info( 'Installing UBOS with hostname', $self->{hostname} );

    unless( $self->{target} ) {
        $self->{tempTarget} = File::Temp->newdir( DIR => getcwd(), UNLINK => 1 );
        $self->{target}     = $self->{tempTarget}->dirname;
    }

    $self->check( $diskLayout ); # will exit if not valid

    my $pacmanConfigInstall = $self->generatePacmanConfigTarget( $self->{packagedbs} );
    my $errors = 0;

    $errors += $diskLayout->createDisks();
    if( $errors ) {
        return $errors;
    }
    $errors += $diskLayout->formatDisks();
    if( $errors ) {
        return $errors;
    }
    $errors += $diskLayout->mountDisks( $self->{target} );
    $errors += $self->mountSpecial();
    $errors += $diskLayout->createSubvols( $self->{target} );
    $errors += $self->installPackages( $pacmanConfigInstall->filename );
    unless( $errors ) {
        $errors += $self->savePacmanConfigProduction( $self->{packagedbs} );
        $errors += $self->saveHostname();
        $errors += $self->saveChannel();
        $errors += $diskLayout->saveFstab( $self->{target} );
        $errors += $self->saveModules();
        $errors += $self->saveSecuretty();
        $errors += $self->saveOther();
        $errors += $self->configureOs();
        $errors += $self->configureNetworkd();
        $errors += $self->doUpstreamFixes();

        $errors += $self->installBootLoader( $pacmanConfigInstall->filename, $diskLayout );
     
        my $chrootScript = <<'SCRIPT';
#!/bin/bash
# Script to be run in chroot
set -e

# In a container, there may be no /lib/modules
if [ -d /lib/modules ]; then
    for v in $(ls -1 /lib/modules | grep -v extramodules); do depmod -a $v; done
fi

systemctl set-default multi-user.target

SCRIPT
        $errors += $self->addGenerateLocaleToScript( \$chrootScript );
        $errors += $self->addEnableServicesToScript( \$chrootScript );
        $errors += $self->addConfigureNetworkingToScript( \$chrootScript );
        $errors += $self->addConfigureSnapperToScript( \$chrootScript, $diskLayout );

        debug( "chroot script:\n" . $chrootScript );
        my $out;
        my $err;
        if( UBOS::Utils::myexec( "chroot '" . $self->{target} . "'", $chrootScript, \$out, \$err )) {
            error( "chroot script failed", $err );
            ++$errors;
        }
        $errors += $self->cleanup();
    }

    $errors += $self->umountSpecial();
    $errors += $diskLayout->umountDisks( $self->{target} );

    unlink( $pacmanConfigInstall->filename );

    return $errors;
}

##
# Check that provided parameters are correct. Exit if not.
sub check {
    my $self       = shift;
    my $diskLayout = shift;

    unless( $self->{hostname} ) {
        fatal( 'Hostname must not be empty' );
    }

    unless( $self->{target} ) {
        fatal( 'No target given' );
    }
    if( $self->{target} =~ m!/$! ) {
        fatal( 'Target must not have a trailing slash:', $self->{target} );
    }
    unless( -d $self->{target} ) {
        fatal( 'Target is not a directory:', $self->{target} );
    }

    if( $self->{repo} ) {
        # if not given, use default depot.ubos.net
        unless( -d $self->{repo} ) {
            fatal( 'Repo must be an existing directory, is not:', $self->{repo} );
        }
        my $archRepo = $self->{repo} . '/' . $self->arch;
        my $osDb     = $archRepo . '/os/os.db';
        unless( -l $osDb ) {
            fatal( 'Not a valid repo, cannot find:', $osDb );
        }
    }

    unless( $self->{channel} ) {
        fatal( 'No channel given' );
    }
    if( $self->{channel} ne 'dev' && $self->{channel} ne 'red' && $self->{channel} ne 'yellow' && $self->{channel} ne 'green' ) {
        fatal( 'Invalid channel:', $self->{channel} );
    }

    # Would be nice to check that packages actually exist, but that's hard if
    # they are remote
}

##
# Mount special devices in target dir, so packages can install correctly
sub mountSpecial {
    my $self = shift;

    debug( "Executing mountSpecial" );

    my $target = $self->{target};
    my $errors = 0;

    my $s = <<END;
mkdir -m 0755 -p $target/var/{cache/pacman/pkg,lib/pacman,log} $target/{dev,run,etc}
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

    debug( "Executing unmountSpecial" );

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
    if( UBOS::Utils::myexec( $s )) {
        ++$errors;
    }
    return $errors;
}

##
# Generate pacman config file for installation into target
# $dbs: array of package database names
# return: File object of the generated temp file
sub generatePacmanConfigTarget {
    my $self = shift;
    my $dbs  = shift;

    debug( "Executing generatePacmanConfigTarget" );

    my $repo = $self->{repo};
    my $arch = $self->arch;
    my $dbRoot;
    if( $repo ) {
        $dbRoot = "file://$repo/$arch";
    } else {
        my $channel = $self->{channel};
        $dbRoot = "http://depot.ubos.net/$channel/$arch";
    }

    my $levelString = $self->getSigLevelString();

    # Generate pacman config file for creating the image
    my $file = File::Temp->new( UNLINK => 1 );
    print $file <<END;
#
# Pacman config file for installing packages
#

[options]
SigLevel           = $levelString
LocalFileSigLevel  = $levelString
RemoteFileSigLevel = $levelString
END

    foreach my $db ( @$dbs ) {
        print $file <<END;

[$db]
Server = $dbRoot/$db
END
    }
    close $file;
    return $file;
}

##
# Install the packages that need to be installed
# $pacmanConfig: pacman config file to use
#
sub installPackages {
    my $self         = shift;
    my $pacmanConfig = shift;

    info( "Installing packages" );

    my $target = $self->{target};
    my $errors = 0;

    my @allPackages = ();
    if( $self->{kernelpackage} ) {
        push @allPackages, $self->{kernelpackage};
    }
    push @allPackages, @{$self->{basepackages}};
    if( defined( $self->{devicepackages} )) {
        push @allPackages, @{$self->{devicepackages}};
    }
    if( defined( $self->{additionalpackages} )) {
        push @allPackages, @{$self->{additionalpackages}};
    }

    my $cmd = "pacman"
            . " -r '$target'"
            . " -Sy"
            . " '--config=$pacmanConfig'"
            . " --cachedir '$target/var/cache/pacman/pkg'"
            . " --noconfirm"
            . ' ' . join( ' ', @allPackages );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
        error( "pacman failed:", $err );
        debug( "pacman configuration was:\n", sub { UBOS::Utils::slurpFile( $pacmanConfig ) } );
        ++$errors;
    }

    return $errors;
}

##
# Generate and save the pacman config file for production
sub savePacmanConfigProduction {
    my $self = shift;
    my $dbs  = shift;

    debug( "Executing savePacmanConfigProduction" );

    my $errors      = 0;
    my $arch        = $self->arch;
    my $channel     = $self->{channel};
    my $target      = $self->{target};
    my $levelString = $self->getSigLevelString();

    my $pacmanConfigProduction = <<END;
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
    unless( UBOS::Utils::saveFile( "$target/etc/pacman.conf", $pacmanConfigProduction, 0644 )) {
        ++$errors;
    }

    unless( -d "$target/etc/pacman.d/repositories.d" ) {
        UBOS::Utils::mkdir( "$target/etc/pacman.d/repositories.d" );
    }

    foreach my $db ( @$dbs ) {
        unless( UBOS::Utils::saveFile( "$target/etc/pacman.d/repositories.d/$db", <<END, 0644 )) {
[$db]
Server = http://depot.ubos.net/$channel/\$arch/$db
END
            # Note what is and isn't escaped here
            ++$errors;
        }
    }

    UBOS::Utils::regeneratePacmanConf( "$target/etc/pacman.conf", "$target/etc/pacman.d/repositories.d" );
    return $errors;
}

##
# Generate and save the /etc/hostname file
sub saveHostname {
    my $self = shift;

    debug( "Executing saveHostname" );

    # hostname
    if( UBOS::Utils::saveFile(
            $self->{target}   . '/etc/hostname',
            $self->{hostname} . "\n",
            0644, 'root', 'root' )) {

        return 0;

    } else {
        return 1;
    }
}

##
# Generate and save the /etc/ubos/channel file
sub saveChannel {
    my $self = shift;
    
    debug( "Executing saveChannel" );

    # hostname
    if( UBOS::Utils::saveFile(
            $self->{target}   . '/etc/ubos/channel',
            $self->{channel} . "\n",
            0644, 'root', 'root' )) {

        return 0;

    } else {
        return 1;
    }
}

##
# Generate and save kernel module load files if needed
sub saveModules {
    my $self  = shift;

    my $target = $self->{target};
    my $errors = 0;

    foreach my $t ( qw( basemodules devicemodules additionalmodules )) {
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
    my $kernelPackage = $self->{kernelpackage};
    my $errors        = 0;

    # Limit size of system journal
    debug( "System journal" );
    UBOS::Utils::myexec( "perl -pi -e 's/^\\s*(#\\s*)?SystemMaxUse=.*\$/SystemMaxUse=50M/' '$target/etc/systemd/journald.conf'" );

    # version
    debug( "OS version info" );
    my $issue = <<ISSUE;

+--------------------------------------------------------------------------+
|                                                                          |
|                           Welcome to UBOS (tm)                           |
|                                                                          |
|                                 ubos.net                                 |
|                                                                          |
ISSUE
    $issue .= sprintf( "|%74s|\n", "device class: $deviceClass, channel: $channel " );
    $issue .= <<ISSUE;
+--------------------------------------------------------------------------+

ISSUE
    UBOS::Utils::saveFile( $target . '/etc/issue', $issue, 0644, 'root', 'root' );

    my $osRelease = <<OSRELEASE;
NAME="UBOS"
ID="ubos"
ID_LIKE="arch"
PRETTY_NAME="UBOS"
HOME_URL="http://ubos.net/"
BUILD_ID="$buildId"
UBOS_DEVICECLASS="$deviceClass"
OSRELEASE
    if( $kernelPackage ) {
        $osRelease .= <<OSRELEASE;
UBOS_KERNELPACKAGE="$kernelPackage"
OSRELEASE
    }
    UBOS::Utils::saveFile( $target . '/etc/os-release', $osRelease, 0644, 'root', 'root' );

    return 0;
}

##
# Configure systemd-networkd
# return: number of errors
sub configureNetworkd {
    my $self = shift;

    my $target = $self->{target};

    UBOS::Utils::deleteFile( $target . '/etc/resolv.conf' );
    UBOS::Utils::symlink( '/run/systemd/resolve/resolv.conf', $target . '/etc/resolv.conf' );

    return 0;
}

##
# Do whatever necessary to fix upstream bugs
sub doUpstreamFixes {
    my $self = shift;

    return 0;
}

##
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# $bootLoaderDevice: device to install the bootloader on
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;
    my $bootLoaderDevice = shift;

    error( 'Method installBootLoader() must be overridden for', ref( $self ));

    return 1;
}

##
# Add commands to the provided script, to be run in a chroot, that generates the locale
# $chrootScriptP: pointer to script
sub addGenerateLocaleToScript {
    my $self          = shift;
    my $chrootScriptP = shift;

    debug( "Executing addGenerateLocaleToScript" );

    # Run perl with the old locale 
    $$chrootScriptP .= "perl -pi -e 's/^#en_US\.UTF-8.*\$/en_US.UTF-8 UTF-8/g' '/etc/locale.gen'\n";
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

    debug( "Executing addEnableServicesToScript" );

    my @allServices = ();
    
    if( defined( $self->{baseservices} )) {
        push @allServices, @{$self->{baseservices}};
    }
    if( defined( $self->{deviceservices} )) {
        push @allServices, @{$self->{deviceservices}};
    }
    if( defined( $self->{additionalservices} )) {
        push @allServices, @{$self->{additionalservices}};
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
    my $diskLayout    = shift;

    my $errors = 0;
    my @mountPoints = $diskLayout->snapperBtrfsMountPoints();
    foreach my $mountPoint ( @mountPoints ) {
        my $configName = $mountPoint;
        $configName =~ s!/!!g;
        $$chrootScriptP .= "snapper -c '$configName' create-config -t ubos-default '$mountPoint'\n";
    }
    return $errors;
}

##
# Clean up after install is done
sub cleanup {
    my $self = shift;
    
    my $target = $self->{target};
    my $ret    = 0;

    # don't need installation history
    if( -e "$target/root/.bash_history" ) {
        UBOS::Utils::deleteFile( "$target/root/.bash_history" );
    }

    # Removing content of /var/cache makes image smaller
    opendir(DIR, "$target/var/cache" ) or return $ret;
    my @dirs = ();
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

    if( @dirs ) {
        unless( UBOS::Utils::deleteRecursively( @dirs )) {
            $ret = 1;
        }
    }
    # create /var/cache/pacman/pkg or there will be an unnecessary warning
    UBOS::Utils::mkdirDashP( "$target/var/cache/pacman/pkg", 0755 );

    return $ret;
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
# Convert the checksignatures field into a string that can be added to
# a pacman.conf file.
# return: string, such as "Optional TrustAll"
sub getSigLevelString {
    my $self = shift;

    my $ret;
    # ubos-install makde sure it is all lowercase
    if( 'never' eq $self->{checksignatures} ) {
        $ret = 'Never';
    } elsif( 'optional' eq $self->{checksignatures} ) {
        $ret = 'Optional TrustAll';
    } else { # can't be anything else
        $ret = 'Required TrustedOnly';
    }
    return $ret;
}

1;
