#!/usr/bin/perl
#
# Command that shows the current network configuration.
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

package IndieBox::Commands::Shownetconfig;

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

    if( @args) {
        fatal( 'Invalid command-line arguments' );
    }

    my $netConfigs      = IndieBox::Networking::NetConfigUtils::findNetConfigs();
    my $activeName      = undef;
    my $activeNetConfig = undef;
    
    while( my( $name, $netConfig ) = each %$netConfigs ) {
        if( IndieBox::Utils::invokeMethod( $netConfig . '::isActive' )) {
            $activeName      = $name;
            $activeNetConfig = $netConfig;
            last;
        }
    }
    if( $activeName ) {
        print "$activeName\n";
    }
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        '' => <<HHH
    Display the currently active network configuration.
HHH
    };
}

1;
