#!/usr/bin/perl
#
# This command is not directly invoked by the user, but by Update.pm
# to re-install sites with the new code, instead of the old code.
#
# This file is part of ubos-admin.
# (C) 2012-2015 Indie Computing Corp.
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
use UBOS::Host;
use UBOS::Logging;
use UBOS::UpdateBackup;
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

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $stage1exit    = 0;
    
    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'stage1exit=s' => \$stage1exit );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $verbose && $logConfigFile ) ) {
        error( 'Invalid command-line arguments, but attempting to restore anyway' );
    }

    my $ret = finishUpdate();

    unless( $ret && !$stage1exit ) {
        error( "Update failed." );
    }

    return $ret && !$stage1exit;
}

##
# Factored-out method that is invoked from UpdateStage2::run and from
# ubos-admin-init after Update has invoked a reboot, and the system
# has rebooted.
sub finishUpdate {
    my $ret = 1;

    my $backup  = UBOS::UpdateBackup->new();
    $ret       &= $backup->read();

    my $oldSites = $backup->sites();

    if( keys %$oldSites ) {
        info( 'Redeploying sites and restoring data' );

        my $deployTriggers = {};
        foreach my $site ( values %$oldSites ) {
            $ret &= $site->deploy( $deployTriggers );

            $ret &= $backup->restoreSite( $site );

            UBOS::Host::siteDeployed( $site );
        }
        UBOS::Host::executeTriggers( $deployTriggers );

        info( 'Resuming sites' );

        my $resumeTriggers = {};
        foreach my $site ( values %$oldSites ) {
            $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
        }
        UBOS::Host::executeTriggers( $resumeTriggers );

        info( 'Running upgraders' );

        foreach my $site ( values %$oldSites ) {
            foreach my $appConfig ( @{$site->appConfigs} ) {
                $ret &= $appConfig->runUpgrader();
            }
        }
    }

    debug( 'Deleting update backup' );
    $backup->delete();

    debug( 'Purging cache' );
    
    UBOS::Host::purgeCache( 1 );

    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return undef; # user is not supposed to invoke this
}

1;
