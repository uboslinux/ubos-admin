#!/usr/bin/perl
#
# This command is not directly invoked by the user, but by Update.pm
# to re-install sites with the new code, instead of the old code.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::UpdateStage2;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
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

    unless( UBOS::Lock::acquire() ) {
        # This is most likely because we were invoked by update, and exec
        # does not release the locks, so this is fine.
        trace( 'UpdatedStage2::run', $@ );
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Lock::preventInterruptions();

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $stage1exit    = 0;
    my $snapNumber    = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'debug'        => \$debug,
            'stage1exit=s' => \$stage1exit,
            'snapNumber=s' => \$snapNumber );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile ) ) {
        error( 'Invalid command-line arguments, but attempting to restore anyway' );
    }

    my $ret = finishUpdate( $snapNumber );

    unless( $ret && !$stage1exit ) {
        error( "Update failed." );
    }

    return $ret && !$stage1exit;
}

##
# Factored-out method that is invoked from UpdateStage2::run and from
# ubos-ready after Update has invoked a reboot, and the system
# has rebooted.
# $snapNumber: if defined, create a "post" snapshot that corresponds to the "pre" snapshot with this number
sub finishUpdate {
    my $snapNumber = shift;

    my $ret = 1;

    my $backup  = UBOS::UpdateBackup->new();
    $ret       &= $backup->read();

    my $oldSites = $backup->sites();

    if( keys %$oldSites ) {

        foreach my $site ( values %$oldSites ) {
            foreach my $appConfig ( @{$site->appConfigs} ) {
                unless( $appConfig->completeImpliedAccessories()) {
                    error( $@ );
                }
                unless( $appConfig->checkCompleteCustomizationPointValues()) {
                    error( $@ );
                }
            }
        }

        info( 'Installing prerequisites' );
        my $prerequisites = {};
        foreach my $site ( values %$oldSites ) {
            $site->addDependenciesToPrerequisites( $prerequisites );
        }
        if( UBOS::Host::ensurePackages( $prerequisites ) < 0 ) {
            warning( $@ );
        }

        info( 'Redeploying sites and restoring data' );

        my $deployTriggers = {};
        foreach my $site ( values %$oldSites ) {
            debugAndSuspend( 'Deploy site', $site->siteId );
            $ret &= $site->deploy( $deployTriggers );

            debugAndSuspend( 'Restore site', $site->siteId );
            $ret &= $backup->restoreSite( $site );

            debugAndSuspend( 'Run upgraders at site', $site->siteId );
            $ret &= $site->runInstallersOrUpgraders( $site );
            # Site configuration remains the same
        }
        $deployTriggers->{'httpd-restart'} = 1;

        debugAndSuspend( 'Execute triggers', keys %$deployTriggers );
        UBOS::Host::executeTriggers( $deployTriggers );

        info( 'Resuming sites' );

        my $resumeTriggers = {};
        foreach my $site ( values %$oldSites ) {
            debugAndSuspend( 'Resume site', $site->siteId );
            $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
        }
        UBOS::Networking::NetConfigUtils::updateOpenPorts();

        debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
        UBOS::Host::executeTriggers( $resumeTriggers );
    }

    if( $ret ) {
        trace( 'Deleting update backup' );
        debugAndSuspend( 'Delete update backup' );
        $backup->delete();
    } else {
        warning( 'Something went wrong during restore of update backup. Not deleting update backup.' );
    }

    trace( 'Purging cache' );

    debugAndSuspend( 'Purge cache' );
    UBOS::Host::purgeCache( 1 );

    trace( 'Removing obsolete packages and directories' );
    my $out;
    UBOS::Utils::myexec( 'pacman -R --noconfirm ubos-networking', undef, \$out, \$out );

    unless( $ret ) {
        UBOS::Utils::deleteRecursively(
                grep { -e $_ }
                qw(
                    /etc/httpd/ubos
                    /var/lib/ubos
                    /srv/http/wellknown )
                );
    }

    if( defined( $snapNumber ) && UBOS::Host::vars()->getResolve( 'host.snapshotonupgrade', 0 )) {
        debugAndSuspend( 'Create filesystem snapshot' );
        UBOS::Host::postSnapshot( $snapNumber );
    }

    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return undef; # user is not supposed to invoke this
}

1;
