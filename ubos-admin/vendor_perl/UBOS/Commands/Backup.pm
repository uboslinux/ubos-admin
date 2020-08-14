#!/usr/bin/perl
#
# Command that backs up data on this device to various backends.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Backup;

use Getopt::Long qw( GetOptionsFromArray :config pass_through ); # for parsing by BackupOperation, DataTransferProtocol
use UBOS::AbstractDataTransferProtocol;
use UBOS::BackupOperation;
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::Terminal;
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
        colPrintError( "$@\n" );
        exit -2;
    }

    my $verbose           = 0;
    my $logConfigFile     = undef;
    my $debug             = undef;
    my $force             = 0;
    my $all               = 0;
    my @siteIds           = ();
    my @hosts             = ();
    my @appConfigIds      = ();
    my $context           = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'                        => \$verbose,
            'logConfig=s'                     => \$logConfigFile,
            'debug'                           => \$debug,
            'all'                             => \$all,
            'siteid=s'                        => \@siteIds,
            'hostname=s'                      => \@hosts,
            'appconfigid=s'                   => \@appConfigIds,
            'context=s'                       => \$context );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( @appConfigIds && ( @siteIds + @hosts ))
        || ( $all && ( @appConfigIds + @siteIds + @hosts ))
        || ( !$all && !( @appConfigIds + @siteIds + @hosts ))
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

    if( @args ) {
        # some are left over
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $backupOperation->isNoOp() ) {
        fatal( 'No backup parameters given, unclear what to do.' );
    }

    # Don't need to do any cleanup of siteIds or appConfigIds:
    # BackupOperation does that for us

    trace( 'Validating sites and appconfigs given in the command-line arguments' );

    foreach my $host ( @hosts ) {
        my $site = UBOS::Host::findSiteByHostname( $host );
        unless( $site ) {
            fatal( $@ );
        }
        if( defined( $context )) {
            my $appConfig = $site->appConfigAtContext( $context );
            unless( $appConfig ) {
                if( $context ) {
                    fatal(  'Cannot find an appconfiguration at context path', $context,
                            'for site', $site->hostname, '(' . $site->siteId . ').' );
                } else {
                    fatal( 'Cannot find an appconfiguration at the root context',
                            'of site', $site->hostname, '(' . $site->siteId . ').' );
                }
            }
            push @appConfigIds, $appConfig->appConfigId();

        } else {
            push @siteIds, $site->siteId;
        }
    }

    unless( $backupOperation->analyze( \@siteIds, \@appConfigIds )) { # none provided implies --all
        error( $@ );
        return 0;
    }

    unless( $backupOperation->constructCheckPipeline()) {
        error( $@ );
        return 0;
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Lock::preventInterruptions();

    info( 'Suspending sites' );

    my $ret = 1;
    my @sitesToSuspendResume = $backupOperation->getSitesToSuspendResume();

    my $suspendTriggers = {};
    foreach my $site ( @sitesToSuspendResume ) {
        debugAndSuspend( 'Site', $site->siteId() );
        $ret &= $site->suspend( $suspendTriggers );
    }

    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $suspendTriggers );

    unless( $backupOperation->doBackup()) {
        error( $@ );
        # do not return
    }

    info( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( @sitesToSuspendResume ) {
        debugAndSuspend( 'Site', $site->siteId() );
        $ret &= $site->resume( $resumeTriggers );
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    unless( UBOS::Lock::release() ) {
        colPrintError( "$@Continuing anyway.\n" );
    }

    UBOS::Lock::allowInterruptions();

    unless( $backupOperation->doUpload()) {
        error( $@ );
        return 0;
    }

    unless( $backupOperation->finish()) {
        error( $@ );
        return 0;
    }

    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Create a backup and save it locally or at a remote location.
SSS
        'detail' => <<DDD,
    The backup may include all or just some of the sites currently
    deployed on this device. A variety of upload protocols are supported.
    To determine which are available on this device, run the command
    'ubos-admin list-data-transfer-protocols'. Some of those may provide
    additional options to this command.

    Unless --nostoreconfig is given, the provided encryption and data transfer
    options will be stored in a config file for reuse in the future;
    this allows subsequent invocations of the same command to be simpler.
DDD
        'cmds' => {
            <<SSS => <<HHH,
    --all [ --backuptofile <backupfileurl> | --backuptodirectory <backupdirurl> ]
SSS
    Back up all sites on this device to into the named file <backupfileurl>,
    or into the directory <backupdirurl>. Either can be a local name or a URL.
HHH
            <<SSS => <<HHH,
    --siteid <siteid> [ --backuptofile <backupfileurl> | --backuptodirectory <backupdirurl> ]
SSS
    Only back up the site with site id <siteid>. This option may be repeated.
HHH
            <<SSS => <<HHH,
    --siteid <siteid> [ --backuptofile <backupfileurl> | --backuptodirectory <backupdirurl> ]
SSS
    Only back up the site with site id <siteid>. This option may be repeated.
HHH
            <<SSS => <<HHH,
    --hostname <hostname> [ --backuptofile <backupfileurl> | --backuptodirectory <backupdirurl> ]
SSS
    Only back up the site with hostnames <hostname>. This option may be
    repeated.
HHH
            <<SSS => <<HHH,
    --hostname <hostname> --context <context> [ --backuptofile <backupfileurl> | --backuptodirectory <backupdirurl> ]
SSS
    Only back up the AppConfiguration at context path <context> at the
    site with hostname <hostname>. The option --context may be repeated.
    In this mode, the option --hostname may not be repeated.
HHH
            <<SSS => <<HHH
    --appconfigid <appconfigid> [ --backuptofile <backupfileurl> | --backuptodirectory <backupdirurl> ]
SSS
    Only back up the AppConfiguration with AppConfigId <appconfigid>.
    This option may be repeated.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--[no]backuptls' => <<HHH,
    If a site uses TLS, specify whether to put the TLS key and certificate
    into the backup. Defaults to previous settings, or --nobackuptls.
HHH
            '--[no]backuptorkey' => <<HHH,
    If a site is on the Tor network, specify whether to put the Tor key into
    the backup. Defaults to previous settings, or --nobackuptorkey.
HHH
            '--backupencryptid <id>' => <<HHH,
    If given, the backup file will be gpg-encrypted, using GPG key id <id>
    in the current user's GPG keychain. Defaults to previous setting.
    Specify blank string to unset previous setting.
HHH
            '--backupdatatransferconfigfile <configfile>' => <<HHH,
    Use an alternate data transfer configuration file than the default.
HHH
            '--nobackupdatatransferconfigfile' => <<HHH,
    Do not store credentials or other configuration for future
    reuse. Do not use already-stored configuration information either.
    If this is given, do not specify --backupdatatransferconfigfile <configfile>.
HHH
        }
    };
}

1;
