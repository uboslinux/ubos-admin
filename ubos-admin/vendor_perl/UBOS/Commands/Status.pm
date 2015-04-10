#!/usr/bin/perl
#
# Command that determines and prints the current state of the device.
#
# This file is part of ubos-admin.
# (C) 2012-2015 Indie Computing Corp.
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

package UBOS::Commands::Status;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $showJson      = 0;
    my $showAll       = 0;
    my $showPacnew    = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'json'         => \$showJson,
            'all'          => \$showAll,
            'pacnew'       => \$showPacnew );

    UBOS::Logging::initialize( 'ubos-admin', 'status', $verbose, $logConfigFile );

    if( !$parseOk || ( $showAll && $showPacnew ) || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation: status', @_, '(add --help for help)' );
    }
    if( $showAll ) {
        $showPacnew = 1;

    } elsif( !$showPacnew ) {
        # default
        $showPacnew = 1;
    }

    my $json = $showJson ? {} : undef;

    if( $showPacnew ) {
        debug( 'Looking for .pacnew files' );

        my $out;
        UBOS::Utils::myexec( "find /boot /etc /usr -name '*.pacnew' -print", undef, \$out );

        if( $out ) {
            my @items = split /\n/, $out;
            if( $json ) {
                $json->{pacnew} = \@items;
            } else {
                my $count = scalar @items;
                my $msg = <<MSG;
pacnew:
    Eplanation: You manually modified $count configuration file(s) that need an
        upgrade. Because you modified them, UBOS cannot automatically upgrade
        them. Instead, the new versions were saved next to the modified files
        with the extension .pacnew. Please review them, one by one, update them,
        and when you are done, remove the version with the .pacnew extension.
        Here's the list:
MSG
                $msg .= '    ' . join( "\n    ", @items ) . "\n";
                print( $msg );
            }
        }
    }

    if( keys %$json ) {
        UBOS::Utils::writeJsonToStdout( $json );
    }
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [ --json ]
SSS
    Show the status of the device in default format
    --json: show it in JSON format
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [ --json ] --all
SSS
    Show the full status of the device.
    --json: show it in JSON format
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [ --json ] --pacnew
SSS
    Show the modified configuration files on the device that UBOS
    cannot continue to upgrade.
HHH
    };
}

1;
