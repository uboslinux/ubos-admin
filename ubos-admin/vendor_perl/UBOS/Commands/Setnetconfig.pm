#!/usr/bin/perl
#
# Command that changes the current network configuration. The assumption
# is that the configuration is unknown prior to the invocation of this
# command. As a result, there is no ->deactivate, but each configuration
# tries to clean up as many cases as it can before activating.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Setnetconfig;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Lock;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Terminal;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    unless( UBOS::Lock::acquire() ) {
        colPrintError( "$@\n" );
        exit -2;
    }

    my $initOnly      = 0;
    my $force         = 0;
    my $verbose       = 0;
    my $logConfigFile = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'init-only'     => \$initOnly, # undocumented
            'force'         => \$force,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args != 1 || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $newConfigName = shift @args;

    return UBOS::Networking::NetConfigUtils::activateNetConfig( $newConfigName, $initOnly, $force );
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Activate a particular network configuration.
SSS
        'detail' => <<DDD,
    A network configuration determines which of the device's networking
    interfaces (Ethernet, WiFi) are active, how IP addresses are
    assigned (e.g. static vs DHCP), which ports are open and which are
    firewalled on which interface, and the like.
    To determine which network configurations are available, use
    "ubos-admin listnetconfigs".
DDD
        'cmds' => {
            <<SSS => <<HHH,
    <name>
SSS
    Activate network configuration with name <name>. If this network
    configuration had been set previously, it will attempt to reuse
    the previous configuration values (e.g. same static IP addresses
    allocated to the same local network interfaces)
HHH
            <<SSS => <<HHH,
    --force <name>
SSS
    Activate network configuration with name <name>. Ignore previously
    set values for this configuration and act as if this network
    configuration had never been set before.
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
