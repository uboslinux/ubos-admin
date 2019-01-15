#!/usr/bin/perl
#
# Utilities that make it easier to implement backup commands.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::BackupUtils;

use Cwd;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Shortcut to analyze and perform a backup
sub analyzePerformBackup {
    my $backup        = shift;
    my $backupOut     = shift;
    my $siteIdsP      = shift;
    my $appConfigIdsP = shift;
    my $noTls         = shift;
    my $noTorKey      = shift;

    my( $sitesP, $appConfigsP ) = analyzeBackup( $siteIdsP, $appConfigIdsP );
    if( $sitesP ) {
        return performBackUp( $backup, $backupOut, $sitesP, $appConfigsP, $noTls, $noTorKey );
    } else {
        return undef;
    }
}

##
# Analyze the provided parameters and determine what to do
# @siteIds: the SiteIds of the Sites to back up
# @appConfigIds: the AppConfigIds of the AppConfigs to back up
# return: ( list of Sites, list of AppConfigurations ) to back up
sub analyzeBackup {
    my @siteIds       = @{shift()};
    my @appConfigIds  = @{shift()};

    # first make sure there is no overlap between them
    my $sites      = {};
    my $appConfigs = {};

    foreach my $appConfigId ( @appConfigIds ) {
        my $appConfig = UBOS::Host::findAppConfigurationByPartialId( $appConfigId );
        unless( $appConfig ) {
            fatal( $@ );
        }
        if( exists( $appConfigs->{$appConfig->appConfigId} )) {
            fatal( 'Appconfigid specified more than once:', $appConfig->appConfigId );
        }
        $appConfigs->{$appConfig->appConfigId} = $appConfig;
    }
    foreach my $siteId ( @siteIds ) {
        my $site = UBOS::Host::findSiteByPartialId( $siteId );
        unless( $site ) {
            fatal( $@ );
        }
        if( exists( $sites->{$site->siteId} )) {
            fatal( 'Siteid specified more than once:', $site->siteId );
        }
        $sites->{$site->siteId} = $site;
    }

    if( !@appConfigIds && !@siteIds ) {
        $sites = UBOS::Host::sites();
    }
    foreach my $site ( values %$sites ) {
        my $appConfigsAtSite = $site->appConfigs;

        foreach my $appConfig ( @$appConfigsAtSite ) {
            if( exists( $appConfigs->{$appConfig->appConfigId} )) {
                fatal( 'Appconfigid', $appConfig->appConfigId . 'is also part of site:', $site->siteId );
            }
            $appConfigs->{$appConfig->appConfigId} = $appConfig;
        }
    }
    if( keys %$appConfigs == 0 ) {
        $@ = 'No installed apps found. Nothing to do.';
        return undef;
    }
    return( [ values %$sites ], [ values %$appConfigs ] );
}

##
# Perform the core backup function.
# $backup: the backup type to use, as instantiated object of the right type
# $backupOut: the file to write the backup to
# @sites: list of Sites to back up
# @appConfigs: list of AppConfigurations to back up
# $noTls: if true, no TLS info (key, cert...) will be backed up
# $noTorKey: if true, for Tor sites, the Tor private key will not be backed up
# return: 1 if ok, 0 if error
sub performBackup {
    my $backup     = shift;
    my $backupOut  = shift;
    my @sites      = @{shift()};
    my @appConfigs = @{shift()};
    my $noTls      = shift;
    my $noTorKey   = shift;

    my $ret = 1;

    my $sitesToSuspendResume = {};

    # We have all AppConfigs of all Sites, so doing this is sufficient
    foreach my $appConfig ( @appConfigs ) {
        my $site = $appConfig->site;
        $sitesToSuspendResume->{$site->siteId} = $site; # may be set more than once
    }

    info( 'Suspending sites' );

    my $suspendTriggers = {};
    foreach my $site ( values %$sitesToSuspendResume ) {
        debugAndSuspend( 'Site', $site->siteId() );
        $ret &= $site->suspend( $suspendTriggers );
    }

    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Creating and exporting backup' );

    $ret &= $backup->create( \@sites, \@appConfigs, $noTls, $noTorKey, $backupOut );

    info( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( values %$sitesToSuspendResume ) {
        debugAndSuspend( 'Site', $site->siteId() );
        $ret &= $site->resume( $resumeTriggers );
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    unless( $ret ) {
        @$ = 'Backup failed.';
    }
    return $ret;
}

1;
