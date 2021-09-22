#!/usr/bin/perl
#
# Command that shows information about a currently deployed appconfigid.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Showappconfig;

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
    my @custPoints        = ();
    my $privateCustPoints = 0;

    my $siteId;
    my $host;
    my $appConfigId;
    my $context = undef;
    my $url;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'                   => \$verbose,
            'logConfig=s'                => \$logConfigFile,
            'debug'                      => \$debug,
            'json'                       => \$json,
            'details'                    => \$detail,
            'brief'                      => \$brief,
            'ids-only|idsonly'           => \$idsOnly,
            'customizationpoint=s',      => \@custPoints,
            'privatecustomizationpoints' => \$privateCustPoints,
            'siteid=s'                   => \$siteId,
            'hostname=s'                 => \$host,
            'appconfigid=s'              => \$appConfigId,
            'context=s'                  => \$context,
            'url=s'                      => \$url );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    my $nDetail = 0;
    if( $detail ) {
        ++$nDetail;
    }
    if( $brief ) {
        ++$nDetail;
    }
    if( $idsOnly ) {
        ++$nDetail;
    }
    if( @custPoints ) {
        ++$nDetail;
    }

    if(    !$parseOk
        || ( $json && $nDetail )
        || ( $nDetail > 1 )
        || ( $appConfigId && ( $siteId || $host || defined( $context ) || $url ))
        || ( $siteId && $host )
        || ( $siteId && $url )
        || ( $host && $url )
        || (( $siteId || $host ) && !defined( $context ))
        || (( !$siteId && !$host ) && defined( $context ))
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $privateCustPoints && $< != 0 ) {
        fatal( 'Must be root to see values of private customizationpoints.' );
    }

    my $appConfig;
    if( $appConfigId ) {
        $appConfig = UBOS::Host::findAppConfigurationByPartialId( $appConfigId );
        unless( $appConfig ) {
            fatal( $@ );
        }
    } else {
        # Can use the same code here for url vs. host+context
        if( $url && $url =~ m!^(https?://)?([-a-z0-9_.]+)(/.*)?$! ) {
            $host    = $2;
            $context = $3;
        }
        my $site;

        if( $host ) {
            $site = UBOS::Host::findSiteByHostname( $host );
            unless( $site ) {
                fatal( $@ );
            }
        } elsif( $siteId ) {
            $site = UBOS::Host::findSiteByPartialId( $siteId );
            unless( $site ) {
                fatal( $@ );
            }
        }
        if( $site ) {
            $appConfig = $site->appConfigAtContext( $context );
            unless( $appConfig ) {
                if( $context ) {
                    fatal( 'Cannot find an appconfiguration at context path', $context,
                           'for site', $site->hostname, '(' . $site->siteId . ').' );
                } else {
                    fatal( 'Cannot find an appconfiguration at the root context',
                           'of site', $site->hostname, '(' . $site->siteId . ').' );
                }
            }
        } else {
            # check that there is only one AppConfig on the device
            my $sites = UBOS::Host::sites();
            if( keys %$sites == 1 ) {
                my $appConfigs = ( values %$sites )[0]->appConfigs();
                if( @$appConfigs == 1 ) {
                    $appConfig = $appConfigs->[0];
                }
            }
            unless( $appConfig ) {
                fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
            }
        }
    }

    if( $json ) {
        UBOS::Utils::writeJsonToStdout( $appConfig->appConfigurationJson );

    } elsif( $idsOnly ) {
        $appConfig->printAppConfigId();

    } elsif( $brief ) {
        $appConfig->printBrief();

    } elsif( $detail ) {
        $appConfig->printDetail( $privateCustPoints );

    } elsif( @custPoints ) {
        $appConfig->printAppCustomizationPoints( \@custPoints, $privateCustPoints );

    } else {
        $appConfig->print( $privateCustPoints );
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show information about one AppConfiguration currently deployed on
    this device.
SSS
        'detail' => <<DDD,
    If invoked as root, more information may be shown than when invoked
    as a different user (e.g. credentials, keys, values for
    customization points marked as "private").
DDD
        'cmds' => {
            <<SSS => <<HHH,
    --appconfigid <appconfigid>
SSS
    Show information about the AppConfiguration with the provided
    <appconfigid>.
HHH
            <<SSS => <<HHH,
    --siteid <siteid> --context <context>
SSS
    Show information about the AppConfiguration at the site with
    site id <siteid> and context path <context>.
HHH
            <<SSS => <<HHH,
    --hostname <hostname> --context <context>
SSS
    Show information about the AppConfiguration at the site with
    hostname <hostname> and context path <context>.
HHH
            <<SSS => <<HHH,
    --url <url>
SSS
    Show information about the AppConfiguration referred to by URL
    <url>.
HHH
            <<SSS => <<HHH
SSS
    No site or AppConfiguration needs to be specified if only one
    AppConfiguration is deployed on this device.
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
            '--customizationpoint <name>' => <<HHH,
    Show the value of the named customizationpoint of the App at this
    AppConfiguration. This does not apply to Accessories.
HHH
            '--privatecustomizationpoints' => <<HHH
    Do not mask the values for private customizationpoints.
HHH
        }
    };
}

1;
