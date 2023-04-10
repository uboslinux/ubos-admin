#
# Install UBOS on an SD Card for a Raspberry Pi 2.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Installers::Armv7hRpi2;

use UBOS::Install::AbstractVolumeLayout;
use UBOS::Logging;
use UBOS::Utils;

use base qw( UBOS::Install::AbstractRpiInstaller );
use fields;

## Constructor inherited from superclass

##
# Check that the provided parameters are correct, and complete incomplete items from
# default except for the disk layout.
# return: number of errors.
sub checkCompleteParameters {
    my $self = shift;

    # override some defaults

    unless( $self->{hostname} ) {
        $self->{hostname}      = 'ubos-raspberry-pi2';
    }

    unless( $self->{kernelPackage} ) {
        $self->{kernelPackage} = 'linux-rpi';
    }

    my $errors = $self->SUPER::checkCompleteParameters();

    push @{$self->{devicePackages}}, 'ubos-deviceclass-rpi2';

    return $errors;
}


##
# Install the bootloader
# $pacmanConfigFile: the Pacman config file to be used to install packages
# $diskLayout: the disk layout
# return: number of errors
sub installBootLoader {
    my $self             = shift;
    my $pacmanConfigFile = shift;

    info( 'Installing boot loader' );

    # Copied from the ArchLinuxARM Raspberry Pi image

    my $kernelPars = $self->getAllKernelParameters();

    my $rootDevice;
    if( $self->{rootDevice} ) {
        $rootDevice = $self->{rootDevice};

    } else {
        $rootDevice = 'PARTUUID=' . UBOS::Install::AbstractVolumeLayout::determinePartUuid(
                $self->{volumeLayout}->getRootVolume()->getDeviceNames() );
    }

    my $cmdline = <<CONTENT;
root=$rootDevice rw rootwait rootfstype=btrfs console=ttyAMA0,115200 console=tty1 kgdboc=ttyAMA0,115200 selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 elevator=noop $kernelPars
CONTENT

    UBOS::Utils::saveFile( $self->{target} . '/boot/cmdline.txt', $cmdline, 0644, 'root', 'root' );

    UBOS::Utils::saveFile( $self->{target} . '/boot/config.txt', <<CONTENT, 0644, 'root', 'root' );
# Uncomment some or all of these to enable the optional hardware interfaces
# Params:
#         i2c_arm                  Set to "on" to enable the ARM's i2c interface
#                                  (default "off")
#         i2c_vc                   Set to "on" to enable the i2c interface
#                                  usually reserved for the VideoCore processor
#                                  (default "off")
#         i2c_arm_baudrate         Set the baudrate of the ARM's i2c interface
#                                  (default "100000")
#         i2c_vc_baudrate          Set the baudrate of the VideoCore i2c interface
#                                  (default "100000")
#         i2c_baudrate             An alias for i2c_arm_baudrate
#         i2s                      Set to "on" to enable the i2s interface
#                                  (default "off")
#         spi                      Set to "on" to enable the spi interfaces
#                                  (default "off")
#         act_led_trigger          Choose which activity the LED tracks.
#                                  Use "heartbeat" for a nice load indicator.
#                                  (default "mmc")
#         act_led_activelow        Set to "on" to invert the sense of the LED
#                                  (default "off")
#         act_led_gpio             Set which GPIO pin to use for the activity LED
#                                  (in case you want to connect it to an external
#                                  device)
#                                  (default "16" on a non-Plus board, "47" on a
#                                  Plus or Pi 2)
#         N.B. It is recommended to only enable those interfaces that are needed.
#         Leaving all interfaces enabled can lead to unwanted behaviour (i2c_vc
#         interfering with Pi Camera, I2S and SPI hogging GPIO pins, etc.)
#         Note also that i2c, i2c_arm and i2c_vc are aliases for the physical
#         interfaces i2c0 and i2c1. Use of the numeric variants is still possible
#         but deprecated because the ARM/VC assignments differ between board
#         revisions. The same board-specific mapping applies to i2c_baudrate,
#         and the other i2c baudrate parameters.

#device_tree_param=i2c_arm=on
#device_tree_param=i2c_vc=on
#device_tree_param=i2s=on
#device_tree_param=spi=on
#device_tree_param=act_led_trigger=mmc

# Uncomment one of these lines to enable an audio interface
#device_tree_overlay=hifiberry-dac
#device_tree_overlay=hifiberry-dacplus
#device_tree_overlay=hifiberry-digi
#device_tree_overlay=hifiberry-amp
#device_tree_overlay=iqaudio-dac
#device_tree_overlay=iqaudio-dacplus

# Uncomment to enable the lirc-rpi module
# Params: gpio_out_pin             GPIO pin for output (default "17")
#         gpio_in_pin              GPIO pin for input (default "18")
#         gpio_in_pull             Pull up/down/off on the input pin
#                                  (default "down")
#         sense                    Override the IR receive auto-detection logic:
#                                    "1" = force active high
#                                    "0" = force active low
#                                    "-1" = use auto-detection
#                                  (default "-1")
#         softcarrier              Turn the software carrier "on" or "off"
#                                  (default "on")
#         invert                   "on" = invert the output pin (default "off")
#         debug                    "on" = enable additional debug messages
#                                  (default "off")
#device_tree_overlay=lirc-rpi
#device_tree_param=gpio_out_pin=17
#device_tree_param=gpio_in_pin=18
#device_tree_param=gpio_in_pull=down

# Uncomment to enable the w1-gpio Onewire interface module
# Use this overlay if you *don't* need a pin to drive an external pullup
# N.B. The parasitic power feature is not yet functional using DT.
# Params: gpiopin                  GPIO pin for I/O (default "4")
#device_tree_overlay=w1-gpio
#device_tree_param=gpiopin=4

# Uncomment to enable the w1-gpio Onewire interface module
# Use this overlay if you *do* need a pin to drive an external pullup
# N.B. The parasitic power feature is not yet functional using DT.
# Params: gpiopin                  GPIO pin for I/O (default "4")
#         pullup                   GPIO pin for external pullup (default "5")
#device_tree_overlay=w1-gpio
#device_tree_param=gpiopin=4
#device_tree_param=pullup=5

# Uncomment to enable pps-gpio (pulse-per-second time signal via GPIO)
# Params: gpiopin                  GPIO input pin (default "18")
#device_tree_overlay=pps-gpio
#device_tree_param=gpiopin=18

# Uncomment to enable a generic I2C RTC overlay supporting ds1307, ds3231, pcf2127, and pcf8523
#device_tree_overlay=i2c-rtc

# Uncomment to enable the PCF8523 Real Time Clock
#device_tree_overlay=pcf8523-rtc

# Uncomment to enable the DS1307 Real Time Clock
#device_tree_overlay=ds1307-rtc

# Uncomment to enable the BMP085/BMP180 temperature/pressure sensor
#device_tree_overlay=bmp085_i2c-sensor

# Uncomment if you get no picture on HDMI for a default "safe" mode
#hdmi_safe=1

# Uncomment this if your display has a black border of unused pixels visible
# and your display can output without overscan
#disable_overscan=1

# Uncomment the following to adjust overscan. Use positive numbers if console
# goes off screen, and negative if there is too much border
#overscan_left=16
#overscan_right=16
#overscan_top=16
#overscan_bottom=16

# Uncomment to force a console size. By default it will be display's size minus
# overscan.
#framebuffer_width=1280
#framebuffer_height=720

# Uncomment if hdmi display is not detected and composite is being output
#hdmi_force_hotplug=1

# Uncomment to force a specific HDMI mode (this will force VGA)
#hdmi_group=1
#hdmi_mode=1

# Uncomment to force a HDMI mode rather than DVI. This can make audio work in
# DMT (computer monitor) modes
#hdmi_drive=2

# Uncomment to set monitor mode to DMT
#hdmi_group=2

# Uncomment to increase signal to HDMI, if you have interference, blanking, or
# no display
#config_hdmi_boost=4

# Uncomment for composite PAL
#sdtv_mode=2

# Uncomment to overclock the ARM core. 700 MHz is the default.
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

gpu_mem=64

# hardware clock of the Desktop Pi
device_tree_overlay=i2c-rtc,pcf8563

CONTENT

    return 0;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    return 'armv7h';
}

##
# Returns the device class
sub deviceClass {
    return 'rpi2';
}

##
# Help text
sub help {
    return 'SD card or USB disk for Raspberry Pi 2 or 3';
}

1;
