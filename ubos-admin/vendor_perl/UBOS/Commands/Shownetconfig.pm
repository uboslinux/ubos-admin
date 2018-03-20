#!/usr/bin/perl
#
# Command that shows information about the current network configuration.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Shownetconfig;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $json          = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'json'          => \$json );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $active = UBOS::Networking::NetConfigUtils::activeNetConfigName();
    unless( $active ) {
        fatal( 'Cannot determine active netconfig' );
    }
    my $activeConfig = UBOS::Networking::NetConfigUtils::readNetconfigConfFileFor( $active );

    if( $json ) {
        UBOS::Utils::writeJsonToStdout( $activeConfig );
    } else {
        print UBOS::Utils::hashAsColumns(
                $activeConfig,
                sub {
                    my $netconfig = shift;

                    my $s = '';

                    if( exists( $netconfig->{address} )) {
                        $s = $netconfig->{address};
                    } elsif( exists( $netconfig->{dhcp} )) {
                        $s = 'dhcp-client';
                        if( exists( $netconfig->{'dhcp-lease'} )) {
                            $s .= ':' . $netconfig->{'dhcp-lease'} . 'sec';
                        }
                    }

                    if(( exists( $netconfig->{dhcpserver} ) && $netconfig->{dhcpserver} )) {
                        $s .= ' dhcp-server';
                        if(( exists( $netconfig->{prefixsize} ) && $netconfig->{prefixsize} )) {
                            $s .= ':' . $netconfig->{prefixsize};
                        }
                    }
                    if(( exists( $netconfig->{state} ) && $netconfig->{state} )) {
                        $s .= ' ' . $netconfig->{state};
                    }
                    if(( exists( $netconfig->{forward} ) && $netconfig->{forward} )) {
                        $s .= ' forward';
                    }
                    if(( exists( $netconfig->{masquerade} ) && $netconfig->{masquerade} )) {
                        $s .= ' nat';
                    }
                    if(( exists( $netconfig->{mdns} ) && $netconfig->{mdns} )) {
                        $s .= ' mdns';
                    }
                    if(( exists( $netconfig->{ports} ) && $netconfig->{ports} )) {
                        $s .= ' ports';
                    }
                    if(( exists( $netconfig->{appnic} ) && $netconfig->{appnic} )) {
                        $s .= ' apps';
                    }
                    if(( exists( $netconfig->{ssh} ) && $netconfig->{ssh} )) {
                        $s .= ' ssh';
                        if(( exists( $netconfig->{sshratelimit} ) && $netconfig->{sshratelimit} )) {
                            $s .= ':' . $netconfig->{sshratelimitcount} . '/' . $netconfig->{sshratelimitseconds} . 'sec';
                        }
                    }
                    return $s;
                },
                sub {
                    my $a = shift;
                    my $b = shift;

                    return $a cmp $b;
                } );
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show information about the currently active network configuration.
SSS
        'detail' => <<DDD,
    The name of the network interface is printed first, and after the
    hyphen various attributes of that network interface are shown:

    x.x.x.x     : a static IP address has been assigned
    dhcp-client : will obtain an IP address as a client via DHCP; optional lease time
    dhcp-server : will issue IP addresses by acting as DHCP server, optional prefix size
    off         : interface is currently set to off
    forward     : interface forwards traffic for routing purposes
    nat         : interface is subject to Network Address Translation ("masquerade")
    mdns        : device will advertise itself via this network interface using MDNS
    public      : apps running on this device can be accessed via this network interface
    ssh         : ssh login is permitted via this network interface, optional rate limits
DDD
        'cmds' => {
            '' => <<HHH,
    Show the currently active network configurations.
HHH
            <<SSS => <<HHH,
    --json
SSS
    Use JSON as the output format, instead of human-readable text.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH
    Use an alternate log configuration file for this command.
HHH
        }
    };
}

1;
