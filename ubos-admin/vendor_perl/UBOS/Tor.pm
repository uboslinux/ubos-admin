#!/usr/bin/perl
#
# Tor abstraction.
#
# This file is part of ubos-admin.
# (C) 2012-2016 Indie Computing Corp.
#
# ubos-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Tor;

use Time::HiRes qw( gettimeofday );
use UBOS::Logging;

my $running = 0;
my $pidDir  = '/run/ubos-tor';
my $pidFile = "$pidDir/pidfile";

##
# Ensure that Tor is running, using the provided systemctl command
# $command: the Apache systemd command, such as 'restart' or 'reload'
sub _ensureTor {
    my $command = shift;

    debug( 'Tor::_ensureTor', $command );

    if( $running ) {
        return 1;
    }

    if( UBOS::Host::ensurePackages( [ 'tor' ] ) < 0 ) {
        warning( $@ );
    }

    my $out;
    my $err;
    UBOS::Utils::myexec( 'systemctl enable ubos-tor',   undef, \$out, \$err );
    UBOS::Utils::myexec( "systemctl $command ubos-tor", undef, \$out, \$err );

    my $max  = 15;
    my $poll = 0.2;

    my( $seconds, $microseconds ) = gettimeofday;
    my $until = $seconds + 0.000001 * $microseconds + $max;

    while( 1 ) {
        if( -e $pidFile ) {
            sleep( 2 ); # two more seconds
            debug( 'Detected Tor restart' );
            last;
        }
        unless( -d $pidDir ) {
            # need to create here: cannot create in package (/run gets recreated at each boot)
            # and writable by the tor:tor daemon
            UBOS::Utils::mkdir( $pidDir, 0755, 'tor', 'tor' );
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
