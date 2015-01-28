# 
# Install UBOS for a PC.
#

use strict;
use warnings;

package UBOS::Install::Installers::Pc;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

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
    $self->SUPER::new( @args );

    return $self;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'x86_64';
}

##
# Parameterized the DiskLayout as appropriate for this Installer.
# $diskLayout: the DiskLayout
sub parameterizeDiskLayout {
    my $self       = shift;
    my $diskLayout = shift;

    $diskLayout->setBootParameters( 'ext4',  '100M' );
    $diskLayout->setRootParameters( 'btrfs', '100G' );
    $diskLayout->setVarParameters(  'btrfs' );

    return 0;
}

##
# Format the disks as appropriate for the provided DiskLayout
# $diskLayout: the DiskLayout
sub formatDisks {
    my $self       = shift;
    my $diskLayout = shift;

    my $errors = 0;
    $errors += $diskLayout->formatRoot( 'btrfs' );
    $errors += $diskLayout->formatVarIfExists( 'brtfs' );
    $errors += $diskLayout->formatBootIfExists( 'ext4' );

    return $errors;
}

##
# Mount the disk(s) as appropriate for the provided DiskLayout
# $diskLayout: the DiskLayout
# $target: the directory to which to mount the disk(s)
sub mountDisks {
    my $self       = shift;
    my $diskLayout = shift;
    my $target     = shift;

    my $errors = 0;
    $errors += $diskLayout->mountRoot( 'brtfs' );
    $errors += $diskLayout->mountBootIfExists( 'ext4' );
    $errors += $diskLayout->mountVarIfExists( 'brtfs' );
}

##
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# $bootDevice: device to install the bootloader on
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;
    my $bootDevice       = shift;

    my $errors = 0;
    my $target = $self->{target};

    # Ramdisk
    debug( "Generating ramdisk" );

    # The optimized ramdisk doesn't always boot, so we always skip the optimization step
    UBOS::Utils::saveFile( "$target/etc/mkinitcpio.d/linux.preset", <<'END', 0644, 'root', 'root' );
# mkinitcpio preset file for the 'linux' package, modified for UBOS
#
# Do not autodetect, as the device booting the image is most likely different
# from the device that created the image

ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"

PRESETS=('default')
BINARIES="/usr/bin/btrfsck"

#default_config="/etc/mkinitcpio.conf"
default_image="/boot/initramfs-linux.img"
default_options="-S autodetect"
END

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "sudo chroot '$target' mkinitcpio -p linux", undef, \$out, \$err ) ) {
        error( "Generating ramdisk failed:", $err );
        ++$errors;
    }

    # Boot loader
    debug( "Installing grub" );
    my $pacmanCmd = "sudo pacman"
            . " -r '$target'"
            . " -S"
            . " '--config=" . $pacmanConfigFile . "'"
            . " --cachedir '$target/var/cache/pacman/pkg'"
            . " --noconfirm"
            . " grub";
    if( UBOS::Utils::myexec( $pacmanCmd, undef, \$out, \$err )) {
        error( "pacman failed", $err );
        ++$errors;
    }
    if( UBOS::Utils::myexec( "sudo grub-install '--boot-directory=$target/boot' --recheck '$bootDevice'", undef, \$out, \$err )) {
        error( "grub-install failed", $err );
        ++$errors;
    }

    # Create a script that can be passed to chroot:
    # 1. grub configuration
    # 2. Depmod so modules can be found. This needs to use the image's kernel version,
    #    not the currently running one
    # 3. Default "run-level" (multi-user, not graphical)
    # 4. Enable services
    
    my $chrootScript = <<'END';
set -e

perl -pi -e 's/GRUB_DISTRIBUTOR=".*"/GRUB_DISTRIBUTOR="UBOS"/' /etc/default/grub
perl -pi -e 's/^.*SystemMaxUse=.*$/SystemMaxUse=50M/'          /etc/systemd/journald.conf

grub-mkconfig -o /boot/grub/grub.cfg

for v in $(ls -1 /lib/modules | grep -v extramodules); do depmod -a $v; done

systemctl set-default multi-user.target
END

    if( UBOS::Utils::myexec( "sudo chroot '$target'", $chrootScript, \$out, \$err )) {
        error( "bootloader chroot script failed", $err );
    }

    return $errors;
}

1;
