#!/usr/bin/perl
#
# Tor abstraction.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Tor;

use Time::HiRes qw( gettimeofday );
use UBOS::Logging;

my $running = 0;
my $pidDir  = '/run/tor';
my $pidFile = "$pidDir/pidfile";

##
# Ensure that Tor is running, using the provided systemctl command
# $command: the Apache systemd command, such as 'restart' or 'reload'
sub _ensureTor {
    my $command = shift;

    trace( 'Tor::_ensureTor', $command );

    if( $running ) {
        return 1;
    }

    if( UBOS::Host::ensurePackages( [ 'tor' ] ) < 0 ) {
        warning( $@ );
    }

    my $out;
    my $err;
    debugAndSuspend( 'Check that tor.service is running' );
    UBOS::Utils::myexec( 'systemctl enable tor',   undef, \$out, \$err );
    UBOS::Utils::myexec( "systemctl $command tor", undef, \$out, \$err );

    my $max  = 15;
    my $poll = 0.2;

    my( $seconds, $microseconds ) = gettimeofday;
    my $until = $seconds + 0.000001 * $microseconds + $max;

    while( 1 ) {
        if( -e $pidFile ) {
            sleep( 2 ); # two more seconds
            trace( 'Detected Tor restart' );
            last;
        }

        ( $seconds, $microseconds ) = gettimeofday;
        my $delta = $seconds + 0.000001 * $microseconds - $until;

        if( $delta >= $max ) {
            warning( 'Tor restart not finished within', $max, 'seconds' );
            return 1;
        }

        select( undef, undef, undef, $poll ); # apparently a tricky way of sleeping for $poll seconds that works with fractions
    }

    $running = 1;

    1;
}

##
# Reload configuration
sub reload {
    _ensureTor( 'reload' );
}

##
# Restart configuration
sub restart {
    _ensureTor( 'restart' );
}

1;
