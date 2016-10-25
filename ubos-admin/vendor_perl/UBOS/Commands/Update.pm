#!/usr/bin/perl
#
# Update all code on this device. This command will perform all steps
# until the actual installation of a new code version, and then
# pass on to UpdateStage2 to complete with the update code instead of
# the old code.
#
# This file is part of ubos-admin.
# (C) 2012-2016 Indie Computing Corp.
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
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose          = 0;
    my $logConfigFile    = undef;
    my $restIsPackages   = 0;
    my @packageFiles     = ();
    my $reboot           = 0;
    my $noreboot         = 0;
    my $nosync           = 0;
    my $noPackageUpgrade = 0;
    my $showPackages     = 0;
    my $stage1Only       = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'         => \$verbose,
            'logConfig=s'      => \$logConfigFile,
            'pkgFiles'         => \$restIsPackages,
            'reboot'           => \$reboot,
            'noreboot'         => \$noreboot,
            'nosynchronize'    => \$nosync,
            'showpackages'     => \$showPackages,
            'nopackageupgrade' => \$noPackageUpgrade, # This option is not public, but helpful for development
            'stage1Only'       => \$stage1Only ); # This option is not public

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( $restIsPackages ) {
        @packageFiles = @args;
        $args = ();
    }

    if( !$parseOk || @args || ( $verbose && $logConfigFile ) || ( @packageFiles && $noPackageUpgrade ) || ( $reboot && $noreboot )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    # Need to keep a copy of the logConfigFile, new package may not have it any more
    my $stage2LogConfigFile;
    if( $logConfigFile ) {
         my $tmp = File::Temp->new( UNLINK => 0, SUFFIX => '.conf' );
         $stage2LogConfigFile = $tmp->filename;
         UBOS::Utils::myexec( "cp '$logConfigFile' '$stage2LogConfigFile'" );
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

    UBOS::UpdateBackup::checkReadyOrQuit();

    if( keys %$oldSites ) {
        info( 'Suspending sites' );

        my $suspendTriggers = {};
        foreach my $site ( values %$oldSites ) {
            $ret &= $site->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
        }
        UBOS::Host::executeTriggers( $suspendTriggers );

        info( 'Backing up' );

        my $backup = UBOS::UpdateBackup->new();
        $ret &= $backup->create( $oldSites );

        info( 'Undeploying' );

        my $adminBackups = {};
        my $undeployTriggers = {};
        foreach my $site ( values %$oldSites ) {
            $ret &= $site->undeploy( $undeployTriggers );
        }
        UBOS::Host::executeTriggers( $undeployTriggers );
    } else {
        info( 'No need to suspend sites, none deployed' );
    }

    UBOS::Utils::regeneratePacmanConf();
    UBOS::Utils::removeDanglingSymlinks( '/etc/httpd/ubos/mods-enabled' );

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

    if( $stage1Only ) {
        print "Stopping after stage 1 as requested. To complete the update:\n";
        print "1. Install upgraded packages via pacman (pacman -S or pacman -U)\n";
        print "2. If you installed a new kernel: reboot. Stage 2 of the update will run automatically\n";
        print "3. If you did not reboot: manually run stage 2: $stage2Cmd\n";
        exit 0;
    }

    info( 'Updating code' );

    my $rebootHeuristics = 0;
    if( $noPackageUpgrade ) {
        # do nothing
    } elsif( @packageFiles ) {
        UBOS::Host::installPackageFiles( \@packageFiles, $showPackages );
    } else {
        if( UBOS::Host::updateCode( $nosync ? 0 : 1, $showPackages || UBOS::Logging::isInfoActive() ) == -1 ) {
            $rebootHeuristics = 1;
        }
    }

    my $doReboot;
    if( $reboot ) {
        info( 'Rebooting.' );
        $doReboot = 1;

    } elsif( $rebootHeuristics ) {
        if( $noreboot ) {
            info( 'Reboot recommended, but --noreboot was specified. Not rebooting.' );
            debug( 'Handing over to update-stage2' );
            $doReboot = 0;

        } else {
            info( 'Detected updates that recommend a reboot. Rebooting.' );
            $doReboot = 1;
        }

    } else {
        debug( 'Handing over to update-stage2' );
        $doReboot = 0;
    }

    if( $doReboot ) {
        UBOS::Host::addAfterBootCommands( 'perleval:use UBOS::Commands::UpdateStage2; UBOS::Commands::UpdateStage2::finishUpdate( 0 );' );
        exec( 'shutdown -r now' ) || fatal( 'Failed to issue reboot command' );

    } else {
        # Reload systemd first, as .service files might have been updated
        UBOS::Utils::myexec( 'systemctl daemon-reload' );

        exec( $stage2Cmd ) || fatal( "Failed to run ubos-admin update-stage2" );
    }
    # Never gets here
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--reboot | --noreboot] [--showpackages]
SSS
    Update all code installed on this device. This will perform
    package updates, configuration updates, database migrations
    et al as needed.
    Use heuristics to determine whether the device needs to be rebooted,
    e.g. because the kernel was updated. If --reboot is specified, always
    reboot. If --noreboot is specified, do not reboot.
    --showpackages will print the packages that were updated.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--reboot | --noreboot] [--showpackages] --nosynchronize
SSS
    Update all code installed on this device, but do not update the list
    of available packages first. This will effectively only update code that
    has been downloaded and cached already. This will perform package updates,
    configuration updates, database migrations et al as needed.
    Use heuristics to determine whether the device needs to be rebooted,
    e.g. because the kernel was updated. If --reboot is specified, always
    reboot. If --noreboot is specified, do not reboot.
    --showpackages will print the packages that were updated.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--reboot | --noreboot] --pkgfiles <package-file>...
SSS
    Update this device, but only install the provided package files
    as if they were the only code that can be upgraded. Any number of package
    files more than 1 may be specified. This will perform
    package updates, configuration updates, database migrations
    et al as needed. This implies --nosynchronize.
    Use heuristics to determine whether the device needs to be rebooted,
    e.g. because the kernel was updated. If --reboot is specified, always
    reboot. If --noreboot is specified, do not reboot.
    --showpackages will print the packages that were updated.
HHH
    };
}

1;
