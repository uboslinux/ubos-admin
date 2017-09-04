#!/usr/bin/perl
#
# Utilities that make it easier to implement backup commands.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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

package UBOS::BackupUtils;

use Cwd;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Perform the core backup function.
# $backup: the backup type to use, as instantiated object of the right type
# $backupOut: the file to write the backup to
# @siteIds: the SiteIds of the Sites to back up
# @appConfigIds: the AppConfigIds of the AppConfigs to back up
# $noTls: if true, no TLS info (key, cert...) will be backed up
# $noTorKey: if true, for Tor sites, the Tor private key will not be backed up
# return: desired exit code
sub performBackup {
    my $backup        = shift;
    my $backupOut     = shift;
    my @siteIds       = @{shift()};
    my @appConfigIds  = @{shift()};
    my $noTls         = shift;
    my $noTorKey      = shift;

    my $ret = 1;

    # first make sure there is no overlap between them
    my $sites         = {};
    my $appConfigs    = {};
    my $torSitesCount = 0;

    foreach my $appConfigId ( @appConfigIds ) {
        my $appConfig = UBOS::Host::findAppConfigurationByPartialId( $appConfigId );
        unless( $appConfig ) {
            fatal( $@ );
        }
        if( exists( $appConfigs->{$appConfig->appConfigId} )) {
            fatal( 'App config id specified more than once:', $appConfig->appConfigId );
        }
        $appConfigs->{$appConfig->appConfigId} = $appConfig;
    }
    foreach my $siteId ( @siteIds ) {
        my $site = UBOS::Host::findSiteByPartialId( $siteId );
        unless( $site ) {
            fatal( $@ );
        }
        if( exists( $sites->{$site->siteId} )) {
            fatal( 'Site id specified more than once:', $site->siteId );
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
                fatal( 'App config id', $appConfig->appConfigId . 'is also part of site:', $site->siteId );
            }
            $appConfigs->{$appConfig->appConfigId} = $appConfig;
        }
        if( $site->isTor() ) {
            ++$torSitesCount;
        }
    }
    if( $noTorKey && !$torSitesCount ) {
        fatal( 'No Tor site found, but --notorkey specified.' );
    }

    my $sitesToSuspendResume = {};

    # We have all AppConfigs of all Sites, so doing this is sufficient
    foreach my $appConfig ( values %$appConfigs ) {
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

    $ret &= $backup->create( [ values %$sites ], [ values %$appConfigs ], $noTls, $noTorKey, $backupOut );

    info( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( values %$sitesToSuspendResume ) {
        debugAndSuspend( 'Site', $site->siteId() );
        $ret &= $site->resume( $resumeTriggers );
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    unless( $ret ) {
        error( "Backup failed." );
    }
    return $ret;
}

1;
