#!/usr/bin/perl
#
# Update all code on this device. This command will perform all steps
# until the actual installation of a new code version, and then
# pass on to UpdateStage2 to complete with the update code instead of
# the old code.
#
# This file is part of indiebox-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Commands::Update;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray );
use IndieBox::BackupManagers::ZipFileBackupManager;
use IndieBox::Host;
use IndieBox::Logging;
use IndieBox::Utils;

# Do not change the following filenames and paths unless you also update
# UpdateStage2 so it can still find the old location and restore.
# They aren't in config.json so that nobody is tempted to change them accidentally
# Do not write them into /tmp or such, because we still want to be able to do
# UpdateStage2 even after reboot

our $updateStatusDir = '/var/lib/indiebox/backups/admin';
our $updateStatusPrefix = 'update.';
our $updateStatusSuffix = '.status';

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    my $quiet   = 0;
    my $verbose = 0;
    my $parseOk = GetOptionsFromArray(
            \@args,
            'quiet'   => \$quiet,
            'verbose' => \$verbose );

    if( !$parseOk || @args ) {
        fatal( 'Invalid command-line arguments, add --help for help' );
    }

    my $ts         = IndieBox::Host::config->get( 'now.tstamp' );
    my $statusFile = "$updateStatusDir/$updateStatusPrefix$ts$updateStatusSuffix";
    if( -e $statusFile ) {
        if( ! -w $statusFile ) {
            fatal( 'Cannot write to status file', $statusFile, ', not updating' );
        }
    } else {
        if( ! -e dirname( $statusFile )) {
            fatal( 'Cannot create status file', $statusFile, ', not updating' );
        }
    }

    my $oldSites = IndieBox::Host::sites();
    foreach my $oldSite ( values %$oldSites ) {
        $oldSite->checkUndeployable();
        $oldSite->checkDeployable(); # FIXME: this should check against the new version of the code
                                     # to do that right, we'll have to implement some kind of package rollback
                                     # this is the best we can do so far
    }

    # May not be interrupted, bad things may happen if it is
	IndieBox::Host::preventInterruptions();

    debug( 'Suspending sites' );
    if( $verbose ) {
        print( "Suspending sites\n" );
    }

    my $suspendTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $site->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
    }
    IndieBox::Host::executeTriggers( $suspendTriggers );

    debug( 'Backing up and undeploying' );
    
    my $backupManager = new IndieBox::BackupManagers::ZipFileBackupManager();

    my $adminBackups = {};
    my $undeployTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $adminBackups->{$site->siteId} = $backupManager->adminBackupSite( $site );
        $site->undeploy( $undeployTriggers );
    }
    IndieBox::Host::executeTriggers( $undeployTriggers );

    debug( 'Preserving current configuration' );
    if( $verbose ) {
        print( "Preserving current configuration\n" );
    }

    my $statusJson = {};
    while( my( $siteId, $backup ) = each %$adminBackups ) {
        $statusJson->{sites}->{$siteId} = { 'backupfile' => $backup->fileName };
    }

    IndieBox::Utils::writeJsonToFile( $statusFile, $statusJson, '0600' );

    debug( 'Updating code' );
    if( $verbose ) {
        print( "Updating code\n" );
    }

    IndieBox::Host::updateCode( $quiet );

    # Will look into the know spot and restore from there
    
    debug( 'Handing over to update-stage2' );
    if( $verbose ) {
        print( "Handing over to update-stage2\n" );
    }

    if( $verbose ) {
        exec( "indiebox-admin update-stage2 --verbose" ) || fatal( "Failed to run indiebox-admin update-stage2" );
    } else {
        exec( "indiebox-admin update-stage2" ) || fatal( "Failed to run indiebox-admin update-stage2" );
    }
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--quiet]
SSS
    Update all code installed on this device. This will perform
    package updates, configuration updates, database migrations
    et al as needed.
HHH
    };
}

1;
