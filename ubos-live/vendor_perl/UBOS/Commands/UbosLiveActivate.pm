#!/usr/bin/perl
#
# Command that activates UBOS Live
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::UbosLiveActivate;

use Getopt::Long qw( GetOptionsFromArray );

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

    if( UBOS::Live::UbosLive::ubosLiveActivate( $token, $registrationUrl )) {
        return 0;

    } else {
        error( 'Failed to activate UBOS Live:', $@ );
        return 1;
    }
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Activate UBOS Live for this device.
SSS
        'cmds' => {
            <<SSS => <<HHH,
    [--token <token>]
SSS
    Activate UBOS Live for this device. If provided, use registration
    token <token>; otherwise use the existing one, or generate a new one.
HHH
    # --registrationurl is for development/testing only, so not documented

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
