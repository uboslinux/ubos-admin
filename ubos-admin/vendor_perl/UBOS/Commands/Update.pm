#!/usr/bin/perl
#
# Update all code on this device. This command will perform all steps
# until the actual installation of a new code version, and then
# pass on to UpdateStage2 to complete with the update code instead of
# the old code.
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

package UBOS::Commands::Update;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::BackupManagers::ZipFileBackupManager;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

# Do not change the following filenames and paths unless you also update
# UpdateStage2 so it can still find the old location and restore.
# They aren't in config.json so that nobody is tempted to change them accidentally
# Do not write them into /tmp or such, because we still want to be able to do
# UpdateStage2 even after reboot

our $updateStatusDir = '/var/lib/ubos/backups/admin';
our $updateStatusPrefix = 'update.';
our $updateStatusSuffix = '.status';

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $quiet        = 0;
    my $verbose      = 0;
    my @packageFiles = ();
    my $parseOk = GetOptionsFromArray(
            \@args,
            'quiet'     => \$quiet,
            'verbose'   => \$verbose,
            'pkgFile=s' => \@packageFiles );

    if( !$parseOk || @args ) {
        fatal( 'Invalid invocation: update', @_, '(add --help for help)' );
    }

    my $ts         = UBOS::Host::config->get( 'now.tstamp' );
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

    my $oldSites = UBOS::Host::sites();
    foreach my $oldSite ( values %$oldSites ) {
        $oldSite->checkUndeployable();
        $oldSite->checkDeployable(); # FIXME: this should check against the new version of the code
                                     # to do that right, we'll have to implement some kind of package rollback
                                     # this is the best we can do so far
    }

    # May not be interrupted, bad things may happen if it is
	UBOS::Host::preventInterruptions();

    debug( 'Suspending sites' );
    if( $verbose ) {
        print( "Suspending sites\n" );
    }

    my $suspendTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $site->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
    }
    UBOS::Host::executeTriggers( $suspendTriggers );

    debug( 'Backing up and undeploying' );
    
    my $backupManager = new UBOS::BackupManagers::ZipFileBackupManager();

    my $adminBackups = {};
    my $undeployTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $adminBackups->{$site->siteId} = $backupManager->adminBackupSite( $site );
        $site->undeploy( $undeployTriggers );
    }
    UBOS::Host::executeTriggers( $undeployTriggers );

    debug( 'Preserving current configuration' );
    if( $verbose ) {
        print( "Preserving current configuration\n" );
    }

    my $statusJson = {};
    while( my( $siteId, $backup ) = each %$adminBackups ) {
        $statusJson->{sites}->{$siteId} = { 'backupfile' => $backup->fileName };
    }

    UBOS::Utils::writeJsonToFile( $statusFile, $statusJson, '0600' );

    debug( 'Updating code' );
    if( $verbose ) {
        print( "Updating code\n" );
    }

    if( @packageFiles ) {
        UBOS::Host::installPackageFiles( \@packageFiles );
    } else {
        UBOS::Host::updateCode( $quiet );
    }

    # Will look into the know spot and restore from there
    
    debug( 'Handing over to update-stage2' );
    if( $verbose ) {
        print( "Handing over to update-stage2\n" );
    }

    if( $verbose ) {
        exec( "ubos-admin update-stage2 --verbose" ) || fatal( "Failed to run ubos-admin update-stage2" );
    } else {
        exec( "ubos-admin update-stage2" ) || fatal( "Failed to run ubos-admin update-stage2" );
    }
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--quiet][--verbose]
SSS
    Update all code installed on this device. This will perform
    package updates, configuration updates, database migrations
    et al as needed.
HHH
        <<SSS => <<HHH
    [--quiet][--verbose] --pkgfile <package-file>
SSS
    Update this device, but only install the provided package files
    as if they were the only code that can be upgraded. This will perform
    package updates, configuration updates, database migrations
    et al as needed.
HHH
    };
}

1;
