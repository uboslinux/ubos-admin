#!/usr/bin/perl
#
# Command that deactivates UBOS Live
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::UbosLiveDeactivate;

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

    my $verbose       = 0;
    my $logConfigFile = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    unless( UBOS::Live::UbosLive::isUbosLiveActive()) {
        fatal( 'UBOS Live is not active.' );
    }

    return UBOS::Live::UbosLive::ubosLiveDeactivate();
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Deactivate UBOS Live for this device.
SSS
        'cmds' => {
            '' => <<HHH,
    Deactivate UBOS Live for this device.
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
