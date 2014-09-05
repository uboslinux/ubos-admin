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
use UBOS::BackupManagers::ZipFileBackupManager;
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

    my $oldSites = UBOS::Host::sites();
    my $resumeSites = ();
    my $suspendTriggers = {};

    debug( 'Suspending sites' );

    if( @siteIds != 0 || @appConfigIds != 0 ) {
        # first make sure there is no overlap between them
        foreach my $siteId ( @siteIds ) {
            my $oldSite = UBOS::Host::findSiteByPartialId( $siteId );
            if( $oldSite ) {
                if( @appConfigIds ) {
                    foreach my $oldSiteAppConfig ( $oldSite->appConfigs ) {
                        foreach my $appConfigId ( @appConfigIds ) {
                            if( $oldSiteAppConfig->appConfigId eq $appConfigId ) {
                                fatal( "AppConfiguration $appConfigId is already part of site $siteId" );
                            }
                        }
                    }
                }
            } else {
                fatal( "Cannot find site $siteId" );
            }
        }
        foreach my $siteId ( @siteIds ) {
            my $oldSite = UBOS::Host::findSiteByPartialId( $siteId );
            if( $oldSite ) {
                $oldSite->suspend( $suspendTriggers );
                $resumeSites->{$siteId} = $oldSite;
            }
        }
        foreach my $appconfigId ( @appConfigIds ) {
			my $oldSites = UBOS::Host::sites();
            foreach my $oldSite ( values %$oldSites ) {
                my $foundAppConfig;
                foreach my $oldAppconfig ( @{$oldSite->appconfigs()} ) {
                    if( $appconfigId eq $oldAppconfig->appConfigId() ) {
                        my $foundAppConfig = $oldAppconfig;
                        last;
                    }
                }
                if( $foundAppConfig ) {
                    $oldSite->suspend( $suspendTriggers );
                    $resumeSites->{$oldSite->siteId} = $oldSite;
                } else {
                    fatal( "Cannot find appconfiguration $appconfigId" );
                }
            }
        }
    } else {
		my $oldSites = UBOS::Host::sites();
        foreach my $oldSite ( values %$oldSites ) {
            $oldSite->suspend( $suspendTriggers );
            $resumeSites->{$oldSite->siteId} = $oldSite;
        }
    }
    UBOS::Host::executeTriggers( $suspendTriggers );

    debug( 'Creating and exporting backup' );

    my $backupManager = new UBOS::BackupManagers::ZipFileBackupManager();
    my $backup        = $backupManager->backup( \@siteIds, \@appConfigIds, $out );

    debug( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( values %$resumeSites ) {
        $site->resume( $resumeTriggers );
    }
    UBOS::Host::executeTriggers( $resumeTriggers );
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] --siteid <siteid> --out <backupfile>
SSS
    Back up all data from all applications installed at a currently
    deployed site with siteid to backupfile.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>]--appconfigid <appconfigid> --out <backupfile>
SSS
    Back up all data from the currently deployed application at
    AppConfiguration appconfigid to backupfile.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>]--out <backupfile>
SSS
    Back up all data from all currently deployed applications at all
    deployed sites to backupfile.
HHH
    };
}

1;
