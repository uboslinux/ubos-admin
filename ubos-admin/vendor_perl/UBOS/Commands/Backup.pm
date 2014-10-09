#!/usr/bin/perl
#
# Command that backs up data on this device.
#
# This file is part of ubos-admin.
# (C) 2012-2014 Indie Computing Corp.
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

package UBOS::Commands::Backup;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $out           = undef;
    my @siteIds       = ();
    my @appConfigIds  = ();

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'out=s',        => \$out,
            'siteid=s'      => \@siteIds,
            'appconfigid=s' => \@appConfigIds );

    UBOS::Logging::initialize( 'ubos-admin', 'backup', $verbose, $logConfigFile );

    if( !$parseOk || @args || !$out || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation: backup', @_, '(add --help for help)' );
    }

    # May not be interrupted, bad things may happen if it is
	UBOS::Host::preventInterruptions();
    my $ret = 1;

    # first make sure there is no overlap between them
    my $sites      = {};
    my $appConfigs = {};

    foreach my $appConfigId ( @appConfigIds ) {
        my $appConfig = UBOS::Host::findAppConfigurationByPartialId( $appConfigId );
        if( exists( $appConfigs->{$appConfig->appConfigId} )) {
            fatal( 'App config id specified more than once:', $appConfig->appConfigId );
        }
        $appConfigs->{$appConfig->appConfigId} = $appConfig;
    }
    foreach my $siteId ( @siteIds ) {
        my $site = UBOS::Host::findSiteByPartialId( $siteId );
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
    }

    my $sitesToSuspendResume = {};

    # We have all AppConfigs of all Sites, so doing this is sufficient
    foreach my $appConfig ( values %$appConfigs ) {
        my $site = $appConfig->site;
        $sitesToSuspendResume->{$site->siteId} = $site; # may be set more than once
    }

    debug( 'Suspending sites' );

    my $suspendTriggers = {};
    foreach my $site ( values %$sitesToSuspendResume ) {
        $ret &= $site->suspend( $suspendTriggers );
    }

    UBOS::Host::executeTriggers( $suspendTriggers );

    debug( 'Creating and exporting backup' );

    my $backup = UBOS::Backup::ZipFileBackup->new();
    $ret &= $backup->create( [ values %$sites ], [ values %$appConfigs ], $out );

    debug( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( values %$sitesToSuspendResume ) {
        $ret &= $site->resume( $resumeTriggers );
    }
    UBOS::Host::executeTriggers( $resumeTriggers );

    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] --siteid <siteid> --out <backupfile>
SSS
    Back up all data from all apps and accessories installed at a currently
    deployed site with siteid to backupfile. More than one siteid may be
    specified.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] --appconfigid <appconfigid> --out <backupfile>
SSS
    Back up all data from the currently deployed app and its accessories at
    AppConfiguration appconfigid to backupfile. More than one appconfigid
    may be specified.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>]--out <backupfile>
SSS
    Back up all data from all currently deployed apps and accessories at all
    deployed sites to backupfile.
HHH
    };
}

1;
