#!/usr/bin/perl
#
# Command that lists the currently deployed sites.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Listsites;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::AnyBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $json          = 0;
    my $detail        = 0;
    my $brief         = 0;
    my $idsOnly       = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'         => \$verbose,
            'logConfig=s'      => \$logConfigFile,
            'debug'            => \$debug,
            'json'             => \$json,
            'detail'           => \$detail,
            'brief'            => \$brief,
            'ids-only|idsonly' => \$idsOnly );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( $json && ( $detail || $brief || $idsOnly ))
        || ( $detail && $brief )
        || ( $brief && $idsOnly )
        || ( $idsOnly && $detail )
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $sites = UBOS::Host::sites();

    if( $json ) {
        my $sitesJson = {};
        foreach my $siteId ( keys %$sites ) {
            $sitesJson->{$siteId} = $sites->{$siteId}->siteJson;
        }
        UBOS::Utils::writeJsonToStdout( $sitesJson );

    } elsif( $idsOnly ) {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->printSiteId();
        }
    } elsif( $brief ) {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->printBrief();
        }
    } elsif( $detail ) {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->printDetail();
        }
    } else {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->print();
        }
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show information about the sites currently deployed on this device.
SSS
        'detail' => <<DDD,
    If invoked as root, more information may be shown than when invoked
    as a different user (e.g. credentials, keys, values for
    customization points marked as "private").
DDD
        'cmds' => {
            '' => <<HHH
    Show all currently deployed sites.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--json' => <<HHH,
    Use JSON as the output format, instead of human-readable text.
HHH
            '--detail' => <<HHH,
    Show more detail.
HHH
            '--brief' => <<HHH,
    Show less detail.
HHH
            '--ids-only' => <<HHH
    Show Site and AppConfiguration ids only.
HHH
        }
    };
}

1;
