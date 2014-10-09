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
use File::Temp;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::UpdateBackup;
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
    my @packageFiles  = ();

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'pkgFile=s'   => \@packageFiles );

    UBOS::Logging::initialize( 'ubos-admin', 'update', $verbose, $logConfigFile );

    if( !$parseOk || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation: update', @_, '(add --help for help)' );
    }

    # Need to keep a copy of the logConfigFile, new package may not have it any more
    my $stage2LogConfigFile;
    if( $logConfigFile ) {
         my $tmp = File::Temp->new( UNLINK => 0, SUFFIX => '.conf' );
         $stage2LogConfigFile = $tmp->filename;
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
    my $ret = 1;

    unless( UBOS::UpdateBackup::checkReady() ) {
        fatal( 'Cannot create temporary backup; backup directory is not empty' );
    }

    info( 'Suspending sites' );

    my $suspendTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $ret &= $site->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
    }
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Backing up' );

    my $backup = UBOS::UpdateBackup->create( $oldSites );

    info( 'Undeploying' );

    my $adminBackups = {};
    my $undeployTriggers = {};
    foreach my $site ( values %$oldSites ) {
        $ret &= $site->undeploy( $undeployTriggers );
    }
    UBOS::Host::executeTriggers( $undeployTriggers );

    info( 'Updating code' );

    if( @packageFiles ) {
        UBOS::Host::installPackageFiles( \@packageFiles );
    } else {
        UBOS::Host::updateCode();
    }

    # Will look into the know spot and restore from there
    
    debug( 'Handing over to update-stage2' );

    my $stage2Cmd = 'ubos-admin update-stage2';
    for( my $i=0 ; $i<$verbose ; ++$i ) {
        $stage2Cmd .= ' -v';
    }
    if( $stage2LogConfigFile ) {
        $stage2Cmd .= ' --logConfig ' . $stage2LogConfigFile;
    }
    unless( $ret ) {
        $stage2Cmd .= ' --stage1exit 1';
    }

    exec( $stage2Cmd ) || fatal( "Failed to run ubos-admin update-stage2" );

    # Never gets here
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>]
SSS
    Update all code installed on this device. This will perform
    package updates, configuration updates, database migrations
    et al as needed.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] --pkgfile <package-file>
SSS
    Update this device, but only install the provided package files
    as if they were the only code that can be upgraded. This will perform
    package updates, configuration updates, database migrations
    et al as needed.
HHH
    };
}

1;