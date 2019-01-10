#!/usr/bin/perl
#
# Command that displays the host id.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Hostid;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $hostid = UBOS::Host::hostId();

    colPrint( "$hostid\n" );

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Displays a unique identified for this device.
SSS
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
