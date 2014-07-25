#!/usr/bin/perl
#
# Command that changes the current network configuration. The assumption
# is that the configuration is unknown prior to the invocation of this
# command. As a result, there is no ->deactivate, but each configuration
# tries to clean up as many cases as it can before activating.
#
# This file is part of indiebox-networking.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-networking is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-networking is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-networking.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Commands::Setnetconfig;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use IndieBox::Logging;
use IndieBox::Networking::NetConfigUtils;
use IndieBox::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    unless( @args ) {
        fatal( 'Invalid command-line arguments' );
    }
    my $newConfigName = shift @args;

    if( @args) {
        fatal( 'Invalid command-line arguments' );
    }

    my $netConfigs = IndieBox::Networking::NetConfigUtils::findNetConfigs();
    my $newConfig  = $netConfigs->{$newConfigName};

    if( $newConfig ) {
        # if( !IndieBox::Utils::invokeMethod( $newConfig . '::isActive' )) {
            IndieBox::Utils::invokeMethod( $newConfig . '::activate' );

        # } else {
        #     error( 'Netconfig', $newConfigName, 'is active already.' );
        # }
    } else {
        fatal( 'Unknown netconfig', $newConfigName );
    }
    return 1;
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
