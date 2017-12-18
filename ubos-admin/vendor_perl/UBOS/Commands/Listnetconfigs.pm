#!/usr/bin/perl
#
# Command that lists the available network configurations.
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

package UBOS::Commands::Listnetconfigs;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $all           = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'all'           => \$all );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $active     = UBOS::Networking::NetConfigUtils::activeNetConfigName();
    my $netConfigs = UBOS::Networking::NetConfigUtils::findNetConfigs();
    print UBOS::Utils::hashAsColumns(
            $netConfigs,
            sub {
                my $netConfig = shift;

                if( !$all && !UBOS::Utils::invokeMethod( $netConfig . '::isPossible' ) ) {
                    return undef; # skip this
                }
                my $text = UBOS::Utils::invokeMethod( $netConfig . '::help' );
                if( $active && UBOS::Utils::invokeMethod( $netConfig . '::name' ) eq $active ) {
                    $text =~ s!\.$!!;
                    $text .= ' (active).';
                }
                return $text;
            } );

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show information about known network configurations.
SSS
        'detail' => <<DDD,
    To activate a network configuration with name <name>, use
    "ubos-admin setnetconfig <name>".
DDD
        'cmds' => {
            '' => <<HHH,
    Show available network configurations.
HHH
            <<SSS => <<HHH,
    --all
SSS
    Show all network configurations, even those that cannot be activated.
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
