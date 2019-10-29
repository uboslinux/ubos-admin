#!/usr/bin/perl
#
# Command that registers this device with UBOS Live
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::UbosLiveRegister;

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
    my $account         = undef;
    my $token           = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'account=s'   => \$account,
            'token=s'     => \$token );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( UBOS::Live::UbosLive::ubosLiveRegister( $account, $token )) {
        return 0;

    } else {
        error( 'Failed to register for UBOS Live:', $@ );
        return 1;
    }
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Register UBOS Live for this device.
SSS
        'cmds' => {
            '[ --account <account> --token <token> ]' => <<HHH,
    Specify the UBOS Live account on which to register this device, and
    the security token.
HHH
            # Those do not need to be specified if they can be determined
            # from /etc/ubos/live.json or the current Staff
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
