# 
# Install UBOS on an SD Card for a Raspberry Pi.
#

use strict;
use warnings;

package UBOS::Install::Installers::Rpi;

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
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'armv6h';
}

##
# Parameterized the DiskLayout as appropriate for this Installer.
# $diskLayout: the DiskLayout
sub parameterizeDiskLayout {
    my $self       = shift;
    my $diskLayout = shift;

    $diskLayout->setBootParameters( 'vfat',  '100M' );
    $diskLayout->setRootParameters( 'btrfs' );

    return 0;
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
    $errors += $diskLayout->mountBootIfExists( 'vfat' );

    return $errors;
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

    # Copied from the ArmLinuxARM Raspberry Pi image
    
    UBOS::Utils::saveFile( $targetDir . '/boot/cmdline.txt', <<CONTENT, 0644, 'root', 'root' );
selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=btrfs elevator=noop rootwait
CONTENT

    UBOS::Utils::saveFile( $targetDir . '/boot/config.txt', <<CONTENT, 0644, 'root', 'root' );
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
