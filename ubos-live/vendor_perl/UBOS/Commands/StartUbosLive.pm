#!/usr/bin/perl
#
# Command that starts the UBOS Live service
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::StartUbosLive;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Live::UbosLive;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    my $verbose         = 0;
    my $logConfigFile   = undef;
    my $token           = undef;
    my $registrationurl = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'          => \$verbose,
            'logConfig=s'       => \$logConfigFile,
            'token=s'           => \$token,
            'registrationurl=s' => \$registrationurl );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( UBOS::Live::UbosLive::isRegisteredWithUbosLive()) {
        if( $token ) {
            fatal( 'Already registered with UBOS Live. Do not provide a --token.' );
        }
        if( $registrationurl ) {
            fatal( 'Already registered with UBOS Live. Do not provide a --registrationurl.' );
        }

    } else {            
        unless( $token ) {
            fatal( 'Not yet registered With UBOS Live. You must provide a --token argument.' );
        }
        if( UBOS::Live::UbosLive::registerWithUbosLive( $token, $registrationurl )) {
            fatal( 'Registration failed' );
        }
    }

    if( UBOS::Live::UbosLive::isUbosLiveRunning()) {
        fatal( 'UBOS Live is running already.' );
    }

    return UBOS::Live::UbosLive::startUbosLive();
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Start the UBOS Live service for this device.
SSS
        'cmds' => {
            <<SSS => <<HHH,
    [--token <token>]
SSS
    Start the UBOS Live service for this device. On the first
    invocation, the UBOS Live token <token> must be provided.
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
