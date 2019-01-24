#!/usr/bin/perl
#
# Update all code on this device. This command will perform all steps
# until the actual installation of a new code version, and then
# pass on to UpdateStage2 to complete with the update code instead of
# the old code.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Update;

use Cwd;
use File::Basename;
use File::Temp;
use Getopt::Long qw( GetOptionsFromArray :config pass_through ); # for parsing by BackupOperation, DataTransferProtocol
use UBOS::BackupOperation;
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::UpdateBackup;
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

    my $verbose           = 0;
    my $logConfigFile     = undef;
    my $debug             = undef;
    my $restIsPackages    = 0;
    my @packageFiles      = ();
    my $reboot            = 0;
    my $noreboot          = 0;
    my $nosync            = 0;
    my $noPackageUpgrade  = 0;
    my $noSnap            = 0;
    my $showPackages      = 0;
    my $stage1Only        = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'                        => \$verbose,
            'logConfig=s'                     => \$logConfigFile,
            'debug'                           => \$debug,
            'pkgFiles'                        => \$restIsPackages,
            'reboot'                          => \$reboot,
            'noreboot'                        => \$noreboot,
            'nosynchronize'                   => \$nosync,
            'nosnapshot'                      => \$noSnap,
            'showpackages'                    => \$showPackages,
            'nopackageupgrade'                => \$noPackageUpgrade, # This option is not public, but helpful for development
            'stage1Only'                      => \$stage1Only ); # This option is not public

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( @packageFiles && $noPackageUpgrade )
        || ( $reboot && $noreboot )
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $backupOperation = UBOS::BackupOperation::parseArgumentsPartial( \@args );
    unless( $backupOperation ) {
        if( $@ ) {
            fatal( $@ );
        } else {
            fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
        }
    }

    if( $restIsPackages ) {
        @packageFiles = @args;
        @args         = ();
    }

    # Need to keep a copy of the logConfigFile, new package may not have it any more
    my $stage2LogConfigFile;
    if( $logConfigFile ) {
        my $tmpDir = UBOS::Host::vars()->getResolve( 'host.tmp', '/tmp' );

        my $tmp = File::Temp->new( DIR => $tmpDir, UNLINK => 0, SUFFIX => '.conf' );
        $stage2LogConfigFile = $tmp->filename;

        debugAndSuspend( 'Copy logConfigFile to', $stage2LogConfigFile );
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

    my $snapNumber = undef;
    if( !$noSnap && UBOS::Host::vars()->getResolve( 'host.snapshotonupgrade', 0 )) {
        debugAndSuspend( 'Create filesystem snapshot' );
        $snapNumber = UBOS::Host::preSnapshot()
    }

    UBOS::UpdateBackup::checkReadyOrQuit();

    my $backupSucceeded = 1;

    if( keys %$oldSites ) {
        info( 'Suspending sites' );

        my $suspendTriggers = {};
        foreach my $site ( values %$oldSites ) {
            debugAndSuspend( 'Suspend site', $site->siteId );
            $ret &= $site->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
        }
        debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
        UBOS::Host::executeTriggers( $suspendTriggers );

        info( 'Backing up' );

        my @siteIdsToBackup = map { $_->siteId() } values %$oldSites;
        $backupSucceeded = $backupOperation->performBackupOfSuspendedSites( \@siteIdsToBackup );

        if( $backupSucceeded ) {
            my $updateBackup = UBOS::UpdateBackup->new();
            debugAndSuspend( 'Backup old sites', keys %$oldSites );
            $ret &= $updateBackup->create( $oldSites );

            info( 'Undeploying' );

            my $adminBackups = {};
            my $undeployTriggers = {};
            foreach my $site ( values %$oldSites ) {
                debugAndSuspend( 'Undeploy site', $site->siteId );
                $ret &= $site->undeploy( $undeployTriggers );
            }
            debugAndSuspend( 'Execute triggers', keys %$undeployTriggers );
            UBOS::Host::executeTriggers( $undeployTriggers );
        }

    } else {
        info( 'No need to suspend or backup sites, none deployed' );
    }

    unless( $backupSucceeded ) {
        info( 'Resuming sites' );

        my $resumeTriggers = {};
        foreach my $site ( values %$oldSites ) {
            debugAndSuspend( 'Resuming site', $site->siteId() );
            $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
        }
        debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
        UBOS::Host::executeTriggers( $resumeTriggers );
        $ret = 0;

    } else {
        debugAndSuspend( 'Regenerate pacman.conf' );
        UBOS::Utils::regeneratePacmanConf();
        UBOS::Utils::regenerateEtcIssue();
        debugAndSuspend( 'Remove dangling symlinks in /etc/httpd/mods-enabled' );
        UBOS::Utils::removeDanglingSymlinks( '/etc/httpd/mods-enabled' );

        my $stage2Cmd = 'ubos-admin update-stage2';
        if( defined( $snapNumber )) {
            $stage2Cmd .= ' --snapnumber ' . $snapNumber;
        }
        for( my $i=0 ; $i<$verbose ; ++$i ) {
            $stage2Cmd .= ' -v';
        }
        if( $stage2LogConfigFile ) {
            $stage2Cmd .= ' --logConfig ' . $stage2LogConfigFile;
        }
        if( $debug ) {
            $stage2Cmd .= ' --debug';
        }
        unless( $ret ) {
            $stage2Cmd .= ' --stage1exit 1';
        }

        if( $stage1Only ) {
            colPrint( "Stopping after stage 1 as requested. To complete the update:\n" );
            colPrint( "1. Install upgraded packages via pacman (pacman -S or pacman -U)\n" );
            colPrint( "2. If you installed a new kernel: reboot. Stage 2 of the update will run automatically\n" );
            colPrint( "3. If you did not reboot: manually run stage 2: $stage2Cmd\n" );
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
                trace( 'Handing over to update-stage2:', $stage2Cmd );
                $doReboot = 0;

            } elsif( $debug ) {
                info( 'Reboot recommended, but --debug was given. Not rebooting.' );
                $doReboot = 0;

            } else {
                info( 'Detected updates that recommend a reboot. Rebooting.' );
                $doReboot = 1;
            }

        } else {
            trace( 'Handing over to update-stage2:', $stage2Cmd );
            $doReboot = 0;
        }

        if( $doReboot ) {
            my $afterBoot = 'perleval:use UBOS::Commands::UpdateStage2; UBOS::Commands::UpdateStage2::finishUpdate( ';
            if( defined( $snapNumber )) {
                $afterBoot .= '"' . $snapNumber . '"';
            } else {
                $afterBoot .= 'undef';
            }
            $afterBoot .= ' );';

            debugAndSuspend( 'Add after-boot commands', $afterBoot );
            UBOS::Host::addAfterBootCommands( $afterBoot );

            debugAndSuspend( 'Reboot now' );
            exec( 'systemctl reboot' ) || fatal( 'Failed to issue reboot command' );

        } else {
            # .service files and/or systemd might have been updated
            debugAndSuspend( 'systemctl daemon-reexec' );
            UBOS::Utils::myexec( 'systemctl daemon-reexec' );

            debugAndSuspend( 'Hand over to stage2' );
            exec( $stage2Cmd ) || fatal( "Failed to run ubos-admin update-stage2" );
        }
        # Never gets here
    }
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Update all code installed on this device.
SSS
        'detail' => <<DDD,
    This command will perform package upgrades, configuration updates,
    database migrations and the like as needed. It uses heuristics to
    determine whether the device needs to be rebooted. If UBOS
    determines that a reboot is needed, it will automatically do so,
    finishing the update as soon as the device is back up. If this is
    run on a filesystem that supports shapshots (e.g. btrfs), a
    filesystem snapshot will be created just prior to the update and a
    second one just after the update.
DDD
        'cmds' => {
            '' => <<HHH,
    Upgrade all packages that can be upgraded.
HHH
        <<SSS => <<HHH,
    --nosynchronize
SSS
    Upgrade all packages that have been downloaded already (such as with
    "pacman -Syuw") and that can be upgraded. Do not perform any network
    operations to determine which packages might exist in the cloud that
    could be upgraded.
HHH
        <<SSS => <<HHH
    --pkgfiles <package-file>...
SSS
    Upgrade using the provided package files only. Do not perform any
    network operations to determine which packages might exist in the
    cloud that could be upgraded.
    This is useful for development when the device needs to remain in
    the same state, while only repeatedly upgrading to new versions of
    a package under development.
HHH
        },
        'args' => {
            '--backuptofile <backupfileurl>' => <<HHH,
    Before updating the site(s), back up all data from all affected sites
    by saving all data from all apps and accessories at those sites into
    the named file <backupfileurl>, which can be a local file name or a URL.
HHH
            '--backuptodirectory <backupdirurl>' => <<HHH,
SSS
    Before updating the site(s), back up all data from all affected sites
    by saving all data from all apps and accessories at those sites into
    a file with an auto-generated name, which will be located in the
    directory <backupdirurl>, which can be a local directory name or a URL
    referring to a directory.
HHH
            '--notls' => <<HHH,
    If a backup is to be created, and a site uses TLS, do not put the TLS
    key and certificate into the backup.
HHH
            '--notorkey' => <<HHH,
    If a backup is to be created, and a site is on the Tor network, do
    not put the Tor key into the backup.
HHH
            '--reboot' => <<HHH,
    Skip the reboot heuristics, and always reboot.
HHH
            '--noreboot' => <<HHH,
    Skip the reboot heuristics, and do not reboot.
HHH
            '--nosnapshot' => <<HHH,
    Do not create filesystem shapshots before and after the upgrade.
HHH
            '--showpackages' => <<HHH,
    Print the names of the packages that were upgraded.
HHH
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
        }
    };
}

1;
