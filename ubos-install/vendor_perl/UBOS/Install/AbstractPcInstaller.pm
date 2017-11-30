#
# Abstract superclass for PC installers.
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
# * random number generator: we do nothing

use strict;
use warnings;

package UBOS::Install::AbstractPcInstaller;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

use UBOS::Logging;
use UBOS::Utils;

##
# Install a Ram disk
# $diskLayout: the disk layout
# $kernelPostfix: allows us to add -ec2 to EC2 kernels
# return: number of errors
sub installRamdisk {
    my $self          = shift;
    my $diskLayout    = shift;
    my $kernelPostfix = shift || '';

    my $errors = 0;
    my $target = $self->{target};

    # Ramdisk
    trace( "Generating ramdisk" );

    # The optimized ramdisk doesn't always boot, so we always skip the optimization step
    UBOS::Utils::saveFile( "$target/etc/mkinitcpio.d/linux$kernelPostfix.preset", <<END, 0644, 'root', 'root' );
# mkinitcpio preset file for the 'linux' package, modified for UBOS
#
# Do not autodetect, as the device booting the image is most likely different
# from the device that created the image

ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux$kernelPostfix"

PRESETS=('default')
BINARIES="/usr/bin/btrfsck"
MODULES=('btrfs')

#default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux$kernelPostfix.img"
default_options="-S autodetect"
END

    debugAndSuspend( 'Invoking mkinitcpio in chroot:', $target );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "chroot '$target' mkinitcpio -p linux$kernelPostfix", undef, \$out, \$err ) ) {
        error( "Generating ramdisk failed:", $err );
        ++$errors;
    }
    return $errors;
}

##
# Install the grub bootloader
# $diskLayout: the disk layout
# $args: hash of parameters for grub-install
# return: number of errors
sub installGrub {
    my $self       = shift;
    my $diskLayout = shift;
    my $args       = shift;

    info( 'Installing grub boot loader' );

    my $errors = 0;
    my $target = $self->{target};

    my $bootLoaderDevice = $diskLayout->determineBootLoaderDevice();

    my $out;
    my $err;

    # Boot loader
    if( $bootLoaderDevice ) {
        my $cmd = 'grub-install';
        if( $args ) {
            $cmd .= ' ' . join( ' ', map { "--$_=" . $args->{$_} } keys %$args );
        }
        $cmd .= " --recheck '$bootLoaderDevice'";
        if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
            error( "grub-install failed", $err );
            ++$errors;
        }

        my $chrootScript = <<'END';
set -e

perl -pi -e 's/GRUB_DISTRIBUTOR=".*"/GRUB_DISTRIBUTOR="UBOS"/' /etc/default/grub
END

        if( defined( $self->{additionalkernelparameters} ) && @{$self->{additionalkernelparameters}} ) {
            my $addParString = '';
            map { $addParString .= ' ' . $_ } @{$self->{additionalkernelparameters}};
            $addParString =~ s!(["'/])!\$1!g; # escape quotes and slash

            $chrootScript .= <<END;
perl -pi -e 's/GRUB_CMDLINE_LINUX_DEFAULT="(.*)"/GRUB_CMDLINE_LINUX_DEFAULT="\$1$addParString"/' /etc/default/grub
END
        }

        $chrootScript .= <<'END';
grub-mkconfig -o /boot/grub/grub.cfg
END

        debugAndSuspend( 'Invoking bootloader script in chroot:', $target, "\n$chrootScript" );

        if( UBOS::Utils::myexec( "chroot '$target'", $chrootScript, \$out, \$err )) {
            error( "bootloader chroot script failed:", $err, "\nwas", $chrootScript );
            ++$errors;
        }
    }
    return $errors;
}

##
# Install the systemd-boot bootloader
# $diskLayout: the disk layout
# return: number of errors
sub installSystemdBoot {
    my $self             = shift;
    my $diskLayout       = shift;

    info( 'Installing systemd-boot boot loader' );

    my $errors = 0;

    if( UBOS::Utils::myexec( "bootctl '--path=$self->{target}/boot' install" )) {
        ++$errors;
    }

    unless( -d $self->{target} . '/boot/loader/entries' ) {
        UBOS::Utils::mkdirDashP( $self->{target} . '/boot/loader/entries' );
    }

    UBOS::Utils::saveFile( $self->{target} . '/boot/loader/loader.conf', <<CONTENT );
timer 4
default ubos
CONTENT

    my $rootPartUuid = $self->getPartUuid( $diskLayout->getRootDeviceNames() );

    UBOS::Utils::saveFile( $self->{target} . '/boot/loader/entries/ubos.conf', <<CONTENT );
title UBOS
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$rootPartUuid rw
CONTENT

    return 0;
}

1;

