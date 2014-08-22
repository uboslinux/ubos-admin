#!/usr/bin/perl
#
# This command is not directly invoked by the user, but by Update.pm
# to re-install sites with the new code, instead of the old code.
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

package UBOS::Commands::UpdateStage2;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Commands::Update;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    # May not be interrupted, bad things may happen if it is
	UBOS::Host::preventInterruptions();

    my $verbose = 0;
    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose' => \$verbose );

    if( !$parseOk || @args ) {
        error( 'Invalid command-line arguments, but attempting to restore anyway' );
    }

    UBOS::Utils::myexec( 'sudo systemctl daemon-reload' );
    
    my $backupManager = new UBOS::BackupManagers::ZipFileBackupManager();

    debug( 'Restoring configuration' );
    if( $verbose ) {
        print( "Restoring configuration\n" );
    }
    
    my @candidateFiles = <"$UBOS::Commands::Update::updateStatusDir/*">;

    my $statusFile = undef;
    my $bestTs     = undef;
    foreach my $candidate ( @candidateFiles ) {
        if( $candidate =~ m!^\Q$UBOS::Commands::Update::updateStatusDir/$UBOS::Commands::Update::updateStatusPrefix\E(.*)\Q$UBOS::Commands::Update::updateStatusSuffix\E$! ) {
            my $ts = $1;
            if( !$bestTs || $ts gt $bestTs ) {
                $bestTs     = $ts;
                $statusFile = $candidate;
            }
        }
    }
    unless( $statusFile ) {
        fatal( 'Cannot restore, no status file found in', $UBOS::Commands::Update::updateStatusDir );
    }
    
    my $statusJson = UBOS::Utils::readJsonFromFile( $statusFile );
    
    my $oldSites     = {};
    my $adminBackups = {};
    while( my( $siteId, $frag ) = each %{$statusJson->{sites}} ) {
        my $backupFile = $frag->{backupfile};
        my $backup     = $backupManager->newFromArchive( $backupFile );
        
        my $site = $backup->{sites}->{$siteId};
        $oldSites->{$siteId} = $site;
        $adminBackups->{$siteId} = $backup;
    }

    debug( 'Redeploying sites' );
    if( $verbose ) {
        print( "Redeploying sites\n" );
    }

    my $deployTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $site->deploy( $deployTriggers );
        
        $adminBackups->{$site->siteId}->restoreSite( $site );

        UBOS::Host::siteDeployed( $site );
    }
    UBOS::Host::executeTriggers( $deployTriggers );

    debug( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
    }
    UBOS::Host::executeTriggers( $resumeTriggers );

    debug( 'Running upgraders' );

    foreach my $site ( values %$oldSites ) {
        foreach my $appConfig ( @{$site->appConfigs} ) {
            $appConfig->runUpgrader();
        }
    }
    
    UBOS::Utils::deleteFile( $statusFile );

    $backupManager->purgeAdminBackups();

    debug( 'Purging cache' );
    
    UBOS::Host::purgeCache( 1 );
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return undef; # user is not supposed to invoke this
}

1;
