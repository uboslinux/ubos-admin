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

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;

##
# Install the grub bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# $diskLayout: the disk layout
# $kernelPostfix: allows us to add -ec2 to EC2 kernels
# return: number of errors
sub installGrub {
    my $self             = shift;
    my $pacmanConfigFile = shift;
    my $diskLayout       = shift;
    my $kernelPostfix    = shift || '';

    info( 'Installing grub boot loader' );

    my $errors = 0;
    my $target = $self->{target};

    my $bootLoaderDevice = $diskLayout->determineBootLoaderDevice();

    # Ramdisk
    debug( "Generating ramdisk" );

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

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "chroot '$target' mkinitcpio -p linux$kernelPostfix", undef, \$out, \$err ) ) {
        error( "Generating ramdisk failed:", $err );
        ++$errors;
    }

    # Boot loader
    if( $bootLoaderDevice ) {
        debug( "Installing grub" );
        
        if( UBOS::Utils::myexec( "grub-install '--boot-directory=$target/boot' --recheck '$bootLoaderDevice'", undef, \$out, \$err )) {
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

        if( UBOS::Utils::myexec( "chroot '$target'", $chrootScript, \$out, \$err )) {
            error( "bootloader chroot script failed:", $err, "\nwas", $chrootScript );
            ++$errors;
        }
    }

    return $errors;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'x86_64';
}

1;

