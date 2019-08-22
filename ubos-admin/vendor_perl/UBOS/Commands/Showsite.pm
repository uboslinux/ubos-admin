#!/usr/bin/perl
#
# Command that shows information about a currently deployed site.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Showsite;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    unless( UBOS::Lock::acquire() ) {
        colPrintError( "$@\n" );
        exit -2;
    }

    my $verbose           = 0;
    my $logConfigFile     = undef;
    my $debug             = undef;
    my $json              = 0;
    my $detail            = 0;
    my $brief             = 0;
    my $idsOnly           = 0;
    my $privateCustPoints = 0;
    my $adminUser         = 0;
    my $siteId;
    my $host;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'                   => \$verbose,
            'logConfig=s'                => \$logConfigFile,
            'debug'                      => \$debug,
            'json'                       => \$json,
            'detail'                     => \$detail,
            'brief'                      => \$brief,
            'ids-only|idsonly'           => \$idsOnly,
            'privatecustomizationpoints' => \$privateCustPoints,
            'adminuser'                  => \$adminUser,
            'siteid=s'                   => \$siteId,
            'hostname=s'                 => \$host );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( $json && ( $detail || $brief || $idsOnly || $privateCustPoints ))
        || ( $adminUser && ( $json || $detail || $brief || $idsOnly ))
        || ( $detail && $brief )
        || ( $brief && $idsOnly )
        || ( $idsOnly && $detail )
        || ( !$siteId && !$host )
        || ( $siteId && $host )
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $privateCustPoints && $< != 0 ) {
        fatal( 'Must be root to see values of private customizationpoints.' );
    }

    my $site;
    if( $host ) {
        $site = UBOS::Host::findSiteByHostname( $host );
        unless( $site ) {
            fatal( 'Cannot find a site with hostname:', $host );
        }
    } else {
        $site = UBOS::Host::findSiteByPartialId( $siteId );
        unless( $site ) {
            fatal( $@ );
        }
    }

    if( $json ) {
        UBOS::Utils::writeJsonToStdout( $site->siteJson );

    } elsif( $idsOnly ) {
        $site->printSiteId();

    } elsif( $brief ) {
        $site->printBrief();

    } elsif( $detail ) {
        $site->printDetail( $privateCustPoints );

    } elsif( $adminUser ) {
        $site->printAdminUser();

    } else {
        $site->print( $privateCustPoints );
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show information about one site currently deployed on this device.
SSS
        'detail' => <<DDD,
    If invoked as root, more information may be shown than when invoked
    as a different user (e.g. credentials, keys, values for
    customization points marked as "private").
DDD
        'cmds' => {
            <<SSS => <<HHH,
    --siteid <siteid>
SSS
    Show information about the site with the provided site id <siteid>.
HHH
            <<SSS => <<HHH
    --hostname <hostname>
SSS
    Show information about the site with the provided hostname
    <hostname>.
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
            '--ids-only' => <<HHH,
    Show Site and AppConfiguration ids only.
HHH
            '--adminuser' => <<HHH,
    Show information about the Site administrator.
HHH
            '--privatecustomizationpoints' => <<HHH
    Do not mask the values for private customizationpoints.
HHH
        }
    };
}

1;
