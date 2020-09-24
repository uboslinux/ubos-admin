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

    my $channel         = undef;
    my $verbose         = 0;
    my $logConfigFile   = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'channel=s'   => \$channel,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( UBOS::Live::UbosLive::ubosLiveActivate( $channel )) {
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
            '' => <<HHH,
    Activate UBOS Live for this previously registered device.
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
