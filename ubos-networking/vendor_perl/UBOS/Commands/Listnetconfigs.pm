#!/usr/bin/perl
#
# Command that lists the available network configurations.
#
# This file is part of ubos-networking.
# (C) 2012-2014 Indie Computing Corp.
#
# ubos-networking is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-networking is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-networking.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Commands::Listnetconfigs;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    my $all = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'all' => \$all );

    if( !$parseOk || @args) {
        fatal( 'Invalid command-line arguments' );
    }

    my $netConfigs = UBOS::Networking::NetConfigUtils::findNetConfigs();
    UBOS::Utils::printHashAsColumns(
            $netConfigs,
            sub {
                my $netConfig = shift;
                
                if( !$all && !UBOS::Utils::invokeMethod( $netConfig . '::isPossible' ) ) {
                    return undef; # skip this
                }
                UBOS::Utils::invokeMethod( $netConfig . '::help' );
            } );
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        '' => <<HHH,
    Show available network configurations.
HHH
        '--all' => <<HHH
    Show all network configurations, even those that cannot be activated.
HHH
    };
}

1;
