#!/usr/bin/perl
#
# Command that changes the current network configuration. The assumption
# is that the configuration is unknown prior to the invocation of this
# command. As a result, there is no ->deactivate, but each configuration
# tries to clean up as many cases as it can before activating.
#
# This file is part of ubos-networking.
# (C) 2012-2015 Indie Computing Corp.
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

package UBOS::Commands::Setnetconfig;

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

    my $verbose       = 0;
    my $logConfigFile = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', 'setnetconfig', $verbose, $logConfigFile );

    if( !$parseOk || @args != 1 || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation: setnetconfig', @_, '(add --help for help)' );
    }

    my $newConfigName = shift @args;

    return UBOS::Networking::NetConfigUtils::activateNetConfig( $newConfigName );
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        '<name>' => <<HHH
    Sets the active network configuration.
HHH
    };
}

1;
