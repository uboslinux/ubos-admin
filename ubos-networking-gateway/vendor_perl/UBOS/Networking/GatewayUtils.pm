#!/usr/bin/perl
#
# Factors out some code common to Gateway netconfigs. This is not an
# abstract superclass because netconfigs don't use inheritance, but it
# sort of acts like one.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Networking::GatewayUtils;

use JSON;
use UBOS::HostStatus;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;

# Default candidates for gateway devices, in order, if none has been specified.
# These are regexes.
my @defaultGatewayNicPatterns = (
    'en.*',
    'eth.*',
    'wifi.*',
    'wlan.*'
);

##
# Determine whether this network configuration could currently be activated.
# This return false, if, for example, this network configuration requires two
# ethernet interfaces, but the device has only one ethernet interface attached.
# This will also return true if this configuration is currently active.
# $gatewayNicPatterns: array of gateway device candidate regex, or default if undef
# return: 1 or 0
sub isPossible {
    my $gatewayNicPatterns        = shift || \@defaultGatewayNicPatterns;
    my $upUnconfiguredNicPatterns = shift || [];

    my $allNics = UBOS::HostStatus::nics();
    map {   my $nic = $_;
            foreach my $pattern ( @$upUnconfiguredNicPatterns ) {
                if( $nic =~ m!^$pattern$! ) {
                    delete $allNics->{$nic};
                    last;
                }
            }
        } sort keys %$allNics;

    if( keys %$allNics < 2 ) { # not enough nics
        return 0;
    }
    foreach my $gatewayNicPattern ( @$gatewayNicPatterns ) {
        my @gateways = grep { m!$gatewayNicPattern! } keys %$allNics;
        if( @gateways ) {
            return 1;
        }
    }
    return 0; # none of the found nics match the pattern
}

##
# Activate this network configuration.
# $name: name of the network configuration
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
# $force: do not read existing configuration, initialize netconfig from scratch
# $upstreamConfig: parameters for the upstream interface
# $lanConfig: parameters for the local network interfaces
# $gatewayNicPatterns: use those, instead of the defaults
# $upUnconfiguredNics: set those Nics to 'up', but do not otherwise configure (hash)
sub activate {
    my $name                      = shift;
    my $initOnly                  = shift;
    my $force                     = shift;
    my $upstreamConfig            = shift;
    my $lanConfig                 = shift;
    my $gatewayNicPatterns        = shift || \@defaultGatewayNicPatterns;
    my $upUnconfiguredNicPatterns = shift || [];

    my $allNics            = UBOS::HostStatus::nics();
    my $upUnconfiguredNics = {};
    map {   my $nic = $_;
            foreach my $pattern ( @$upUnconfiguredNicPatterns ) {
                if( $nic =~ m!^$pattern$! ) {
                    $upUnconfiguredNics->{$nic} = $allNics->{$nic};
                    delete $allNics->{$nic};
                    last;
                }
            }
        } sort keys %$allNics;

    my $conf    = undef;
    my $error   = 0;
    my $updated = 0;

    if( $force ) {
        $conf    = {};
        $updated = 1;
    } else {
        $conf = UBOS::Networking::NetConfigUtils::readNetconfigConfFileFor( $name );
    }
    unless( $conf ) {
        $conf  = {};
        $error = 1;
    }

    unless( $initOnly ) {
        # have we identified at least one gateway device?
        my $gateway = undef;
        foreach my $nic ( keys %$allNics ) {
            if( exists( $conf->{$nic} )) {
                if( exists( $conf->{$nic}->{masquerade} ) && $conf->{$nic}->{masquerade} ) {
                    $gateway = $nic;
                    last;
                }
            }
        }
        unless( $gateway ) {
            my @gateways;
            foreach my $gatewayNicPattern ( @$gatewayNicPatterns ) {
                @gateways = grep { m!$gatewayNicPattern! } sort UBOS::Networking::NetConfigUtils::compareNics keys %$allNics;
                if( @gateways ) {
                    last;
                }
            }
            unless( @gateways ) {
                error( 'Unable to find a suitable gateway interface' );
                return 0;
            }

            $gateway = shift @gateways;
            $conf->{$gateway} = $upstreamConfig; # overwrite what might have been there before
            $updated = 1;
        }
        $conf->{$gateway}->{appnic} = JSON::true;

        foreach my $nic ( sort keys %$allNics ) {
            unless( exists( $conf->{$nic} )) {
                my( $ip, $prefixsize ) = UBOS::Networking::NetConfigUtils::findUnusedNetwork( $conf );
                if( $ip ) {
                    foreach my $key ( keys %$lanConfig ) {
                        $conf->{$nic}->{$key} = $lanConfig->{$key};
                    }
                    $conf->{$nic}->{address}    = $ip;
                    $conf->{$nic}->{prefixsize} = $prefixsize;

                    $updated = 1;
                } else {
                    warning( 'Cannot find unallocated network for interface', $nic );
                }
            }
        }
    }

    foreach my $nic ( keys %$upUnconfiguredNics ) {
        $conf->{$nic} = {
            'state'    => 'switch',
            'priority' => 49
        };
    }

    my $ret = UBOS::Networking::NetConfigUtils::configure( $name, $conf, $initOnly );

    if( $updated && !$error ) {
        UBOS::Networking::NetConfigUtils::saveNetconfigConfFileFor( $name, $conf );
    }
    return $ret;
}

1;
