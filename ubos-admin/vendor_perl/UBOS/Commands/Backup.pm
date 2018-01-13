#!/usr/bin/perl
#
# Command that backs up data on this device to a local file.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Backup;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::BackupUtils;
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
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

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $out           = undef;
    my $force         = 0;
    my @siteIds       = ();
    my @hosts         = ();
    my @appConfigIds  = ();
    my $noTls         = undef;
    my $noTorKey      = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'debug'         => \$debug,
            'out=s',        => \$out,
            'force',        => \$force,
            'siteid=s'      => \@siteIds,
            'hostname=s'    => \@hosts,
            'appconfigid=s' => \@appConfigIds,
            'notls'         => \$noTls,
            'notorkey'      => \$noTorKey );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || !$out || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( -e $out && !$force ) {
        fatal( 'Output file exists already. Use --force to overwrite.' );
    }

    # Don't need to do any cleanup of siteIds or appConfigIds, BackupUtils::performBackup
    # does that for us
    foreach my $host ( @hosts ) {
        my $site = UBOS::Host::findSiteByHostname( $host );
        unless( $site ) {
            fatal( 'Cannot find site with hostname:', $host );
        }
        push @siteIds, $site->siteId;
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();

    my $backup = UBOS::Backup::ZipFileBackup->new();
    my $ret = UBOS::BackupUtils::performBackup( $backup, $out, \@siteIds, \@appConfigIds, $noTls, $noTorKey );
    unless( $ret ) {
        error( $@ );
    }

    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Create a backup and save it to a local file.
SSS
        'detail' => <<DDD,
    The backup may include all or just some of the sites currently
    deployed on this device.
DDD
        'cmds' => {
            <<SSS => <<HHH,
    --out <backupfile>
SSS
    Back up all data from all sites currently deployed on this device by
    saving all data from all apps and accessories on the device into
    local file <backupfile>.
HHH
            <<SSS => <<HHH,
    --out <backupfile> --siteid <siteid> [--siteid <siteid>]...
SSS
    Back up one or more sites identified by their site ids <siteid> by
    saving all data from all apps and accessories at those sites into
    local file <backupfile>.
HHH
            <<SSS => <<HHH,
    --out <backupfile> --hostname <hostname> [--hostname <hostname>]...
SSS
    Back up one or more sites identified by their hostnames <hostname>
    by saving all data from all apps and accessories at those sites into
    local file <backupfile>.
HHH
            <<SSS => <<HHH
    --out <backupfile> --appconfigid <appconfigid> [--appconfigid <appconfigid>]...
SSS
    Back up one or more AppConfigurations identified by their
    AppConfigIds <appconfigid> by saving all data from the apps and
    accessories at these AppConfigurations into local file <backupfile>.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--force' => <<HHH,
    If the output file exists already, overwrite instead of aborting.
HHH
            '--notls' => <<HHH,
    If a site uses TLS, do not put the TLS key and certificate into the
    backup.
HHH
            '--notorkey' => <<HHH
    If a site is on the Tor network, do not put the Tor key into the
    backup.
HHH
        }
    };
}

1;
