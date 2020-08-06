#!/usr/bin/perl
#
# If the Staff has WiFi client-side information, set it up.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SetupUpdateWifiClient;

use UBOS::HostStatus;
use UBOS::Logging;
use UBOS::Utils;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'SetupUpdateWifiClient::performAtLoad', $staffRootDir, $isActualStaffDevice );

    return loadCurrentWiFiConfiguration( $staffRootDir );
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'SetupUpdateWifiClient::performAtSave', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# Load WiFi configuration from this directory
# $staffRootDir the root directory of the Staff
# return: number of errors
sub loadCurrentWiFiConfiguration {
    my $staffRootDir = shift;

    my $errors = 0;
    if( -d "$staffRootDir/wifi" ) {

        trace( 'SetupUpdateWifiClient::loadCurrentWiFiConfiguration', $staffRootDir );

        my $out;
        if( UBOS::Utils::myexec( "pacman -Qi wpa_supplicant", undef, \$out, \$out )) {
            error( 'Cannot provision WiFi from staff device: package wpa_supplicant is not installed' );
            ++$errors;

        } else {
            my $confs    = UBOS::Utils::readFilesInDirectory( "$staffRootDir/wifi", '^[^\.].*\.conf$' );
            my $wlanNics = UBOS::HostStatus::wlanNics();

            if(( keys %$confs ) && ( keys %$wlanNics )) {
                unless( -d '/etc/wpa_supplicant' ) {
                    unless( UBOS::Utils::mkdir( '/etc/wpa_supplicant' )) {
                        ++$errors;
                    }
                }
                my $content = <<CONTENT;
eapol_version=1
ap_scan=1
fast_reauth=1

CONTENT
                $content .= join( "\n", map { "network={\n" . $_ . "\n}\n" } values %$confs );
                foreach my $nic ( keys %$wlanNics ) {
                    unless( UBOS::Utils::saveFile( "/etc/wpa_supplicant/wpa_supplicant-$nic.conf", $content )) {
                        ++$errors;
                    }

                    if( UBOS::Utils::myexec( 'systemctl is-enabled wpa_supplicant@' . $nic . ' > /dev/null || systemctl enable wpa_supplicant@' . $nic, undef, \$out, \$out )) {
                        ++$errors;
                    }
                    if( UBOS::Utils::myexec( 'systemctl is-active  wpa_supplicant@' . $nic . ' > /dev/null || systemctl start  wpa_supplicant@' . $nic, undef, \$out, \$out )) {
                        ++$errors;
                    }
                }
            }

            # Update regulatory domain
            if( -e "$staffRootDir/wifi/wireless-regdom" ) {
                unless( UBOS::Utils::copyRecursively( "$staffRootDir/wifi/wireless-regdom", '/etc/conf.d/wireless-regdom' )) {
                    ++$errors;
                }
            }
        }
    }
    return $errors;
}

1;
