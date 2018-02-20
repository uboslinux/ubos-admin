#!/usr/bin/perl
#
# Command that undeploys one or more sites.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Undeploy;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my @siteIds       = ();
    my @hosts         = ();
    my $all           = 0;
    my $file          = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug,
            'siteid=s'    => \@siteIds,
            'hostname=s'  => \@hosts,
            'all'         => \$all,
            'file=s'      => \$file );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( !@siteIds && !@hosts && !$all && !$file )
                           || ( @siteIds && @hosts )
                           || ( @siteIds && $file )
                           || ( @hosts && $file )
                           || ( $all && ( @siteIds || @hosts || $file ))
                           || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    trace( 'Looking for site(s)' );

    my $oldSites = {};
    if( @hosts ) {
        foreach my $host ( @hosts ) {
            my $site = UBOS::Host::findSiteByHostname( $host );
            if( $site ) {
                $oldSites->{$site->siteId} = $site;
            } else {
                fatal( "Cannot find site with hostname $host. Not undeploying any site." );
            }
        }

    } elsif( $all ) {
        $oldSites = UBOS::Host::sites();

    } else {
        if( $file ) {
            # if $file is given, construct @siteIds from there
            my $json = readJsonFromFile( $file );
            unless( $json ) {
                fatal();
            }
            $json = UBOS::Utils::insertSlurpedFiles( $json, dirname( $file ) );

            if( ref( $json ) eq 'HASH' && %$json ) {
                # This is either a site json directly, or a hash of site jsons (for which we ignore the keys)
                if( defined( $json->{siteid} )) {
                    @siteIds = ( $json->{siteid} );
                } else {
                    @siteIds = map { $_->{siteid} || fatal( 'No siteid found in JSON file' ) } values %$json;
                }
            } elsif( ref( $json ) eq 'ARRAY' ) {
                if( !@$json ) {
                    fatal( 'No site given' );
                } else {
                    @siteIds = map { $_->{siteid} || fatal( 'No siteid found in JSON file' ) } @$json;
                }
            }
        }

        foreach my $siteId ( @siteIds ) {
            my $site = UBOS::Host::findSiteByPartialId( $siteId );
            if( $site ) {
                $oldSites->{$site->siteId} = $site;
            } else {
                fatal( "$@Not undeploying any site." );
            }
        }
    }

    foreach my $site ( values %$oldSites ) {
        unless( $site->checkUndeployable ) {
            fatal( 'Cannot undeploy site', $site->siteId );
        }
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();
    my $ret = 1;

    trace( 'Suspending site(s)' );

    my $suspendTriggers = {};
    foreach my $oldSite ( values %$oldSites ) {
        debugAndSuspend( 'Suspend site', $oldSite->siteId );
        $ret &= $oldSite->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $suspendTriggers );

    trace( 'Disabling site(s)' );

    my $disableTriggers = {};
    foreach my $oldSite ( values %$oldSites ) {
        debugAndSuspend( 'Disable site', $oldSite->siteId );
        $ret &= $oldSite->disable( $disableTriggers ); # replace with "404 page"
    }
    debugAndSuspend( 'Execute triggers', keys %$disableTriggers );
    UBOS::Host::executeTriggers( $disableTriggers );

    info( 'Undeploying' );

    my $undeployTriggers = {};
    foreach my $oldSite ( values %$oldSites ) {
        debugAndSuspend( 'Undeploy site', $oldSite->siteId );
        $ret &= $oldSite->undeploy( $undeployTriggers );

        if( $oldSite->hasLetsEncryptTls()) {
            # If we don't do this, a new site with the same hostname may be deployed, and then things get messy
            $ret &= $oldSite->removeLetsEncryptCertificate();
        }
    }

    UBOS::Networking::NetConfigUtils::updateOpenPorts();

    debugAndSuspend( 'Execute triggers', keys %$undeployTriggers );
    UBOS::Host::executeTriggers( $undeployTriggers );

    unless( $ret ) {
        error( "Undeploy failed." );
    }
    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Undeploy one or more currently deployed websites.
SSS
        'detail' => <<DDD,
    This command will remove the virtual host(s) configuration, web
    application and accessory configuration, and delete all data of the
    undeployed site(s), such as databases and files. If you do not wish
    to lose data, back up your site(s) first.
DDD
        'cmds' => {
            <<SSS => <<HHH,
    --siteid <siteid> [--siteid <siteid>]...
SSS
    Identify the to-be-undeployed site or sites by site id <siteid>.
HHH
            <<SSS => <<HHH,
    --hostname <hostname> [--hostname <hostname>]...
SSS
    Identify the to-be-undeployed site or sites by hostname <hostname>.
HHH
            <<SSS => <<HHH,
    --file <site.json>
SSS
    Undeploy those sites whose Site JSON is contained in local file
    <site.json>. This is a convenience method so deploy and undeploy
    commands can use the same arguments.
HHH
        <<SSS => <<HHH
    --all
SSS
    Undeploy all currently deployed site(s).
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
