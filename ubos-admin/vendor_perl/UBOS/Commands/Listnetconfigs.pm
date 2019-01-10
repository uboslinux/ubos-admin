#!/usr/bin/perl
#
# Command that lists the available network configurations.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Listnetconfigs;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
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
    colPrint( UBOS::Utils::hashAsColumns(
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
            } ));

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
