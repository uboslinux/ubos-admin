#!/usr/bin/perl
#
# Command that lists the available data transfer protocols.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::ListDataTransferProtocols;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );

use UBOS::AbstractDataTransferProtocol;
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;

##
# Execute this command. Does not need UBOS::Lock.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $transferProtocols = UBOS::AbstractDataTransferProtocol::availableDataTransferProtocols();

    foreach my $shortPackageName ( sort keys %$transferProtocols ) {
        my $package     = $transferProtocols->{$shortPackageName};
        my $description = UBOS::Utils::invokeMethod( $package . '::description' ) || '';
        my $protocol    = UBOS::Utils::invokeMethod( $package . '::protocol' );

        colPrint( $protocol . "\n" );

        $description =~ s!^\s+!!gm;
        $description =~ s!\s+$!!gm;
        $description =~ s!^!    !gm;

        colPrint( "$description\n\n" );
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Shows available data transfer protocols for backups and restores.
SSS
        'detail' => <<DDD,
    To use a particular transfer protocol, specify the appropriate
    URL protocol in the source or destination. For example,
    using https://example.com/foo would use the backup destination
    responsible for the https protocol.
DDD
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
