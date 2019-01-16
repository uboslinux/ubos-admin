#!/usr/bin/perl
#
# Command that backs up data on this device to various backends.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Backup;

use Getopt::Long qw( GetOptionsFromArray :config pass_through );
use UBOS::AbstractDataTransferProtocol;
use UBOS::BackupUtils;
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $DEFAULT_CONFIG_FILE = '/etc/ubos/backup-config.json';

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
    my $configFile    = undef;
    my $toFile        = undef;
    my $toDirectory   = undef;
    my $force         = 0;
    my @siteIds       = ();
    my @hosts         = ();
    my @appConfigIds  = ();
    my $context       = undef;
    my $noTls         = undef;
    my $noTorKey      = undef;
    my $noStoreConfig = undef;
    my $encryptId     = undef;

    my $parseOk = GetOptionsFromArray( # no $parseOk -- we may not be done with parsing
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'debug'         => \$debug,
            'config=s',     => \$configFile,
            'tofile=s',     => \$toFile,
            'todirectory=s' => \$toDirectory,
            'siteid=s'      => \@siteIds,
            'hostname=s'    => \@hosts,
            'appconfigid=s' => \@appConfigIds,
            'context=s'     => \$context,
            'notls'         => \$noTls,
            'notorkey'      => \$noTorKey,
            'nostoreconfig' => \$noStoreConfig,
            'encryptid=s'   => \$encryptId );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( !$toFile && !$toDirectory )
        || ( $toFile && $toDirectory )
        || ( $configFile && $noStoreConfig )
        || ( @appConfigIds && ( @siteIds + @hosts ))
        || ( $verbose && $logConfigFile ) )
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $config;
    my $configChanged = 0;
    my $firstTime     = 1;
    if( $configFile ) {
        unless( -e $configFile ) {
            fatal( 'Specified config file does not exist:', $configFile );
        }
    } else {
        $configFile = $DEFAULT_CONFIG_FILE;
    }
    if( !$noStoreConfig && -e $configFile ) {
        $config = UBOS::Utils::readJsonFromFile( $configFile );
        unless( $config ) {
            fatal( 'Failed to parse config file:', $configFile );
        }
        $firstTime = 0;
    } else {
        $config = {}; # by default we have nothing
    }

    $configChanged |= UBOS::AbstractDataTransferProtocol::overrideConfigValue( $config, 'backup', 'encryptid', $encryptId );
    $configChanged |= UBOS::AbstractDataTransferProtocol::overrideConfigValue( $config, 'backup', 'notls', $noTls );
    $configChanged |= UBOS::AbstractDataTransferProtocol::overrideConfigValue( $config, 'backup', 'notorkey', $noTorKey );

    # Don't need to do any cleanup of siteIds or appConfigIds, BackupUtils::performBackup
    # does that for us

    trace( 'Validating sites and appconfigs given in the command-line arguments' );

    foreach my $host ( @hosts ) {
        my $site = UBOS::Host::findSiteByHostname( $host );
        unless( $site ) {
            fatal( 'Cannot find site with hostname:', $host );
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

    my $transferProtocol = UBOS::AbstractDataTransferProtocol->parseLocation(
            $toFile || $toDirectory,
            \@args,
            $config,
            \$configChanged );
    unless( $transferProtocol ) {
        fatal( 'Cannot determine the data transfer protocol from the arguments', $toFile || '-', $toDirectory || '-' );
    }
    if( @args ) {
         # some are left over
        fatal( 'Invalid options for data transfer protocol:', @args );
    }
    trace( 'Found transfer protocol:', $transferProtocol );

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();

    my( $sitesP, $appConfigsP ) = UBOS::BackupUtils::analyzeBackup( \@siteIds, \@appConfigIds );
    unless( $sitesP ) {
        error( $@ );
        return 0;
    }

    trace( 'Analyzed what needs backing up. Sites: ', @$sitesP );
    trace( 'Analyzed what needs backing up. AppConfigs: ', @$appConfigsP );

    if( $toDirectory ) {
        # i.e. $out is undef
        $toFile = $toDirectory;
        unless( $toFile =~ m!/$! ) {
            $toFile .= '/';
        }

        # generate local name
        my $name;
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime( time() );
        my $now = sprintf( "%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec );

        if( @$sitesP == 1 ) {
            $name = sprintf( "site-%s-%s.ubos-backup", $sitesP->[0]->siteId(), $now );

        } elsif( @$sitesP ) {
            my $hostId = lc( UBOS::Host::hostId());
            $name = sprintf( "site-multi-%s-%s.ubos-backup", $hostId, $now );

        } elsif( @$appConfigsP == 1 ) {
            $name = sprintf( "appconfig-%s-%s.ubos-backup", $appConfigsP->[0]->appConfigId(), $now );

        } else {
            my $hostId = lc( UBOS::Host::hostId());
            $name = sprintf( "appconfig-multi-%s-%s.ubos-backup", $hostId, $now );
        }
        $toFile .= $name;
        if( $encryptId ) {
            $toFile .= '.gpg';
        }

        trace( 'Generated new file name in directory:', $toDirectory, $toFile );
    }

    unless( $transferProtocol->isValidToFile( $toFile )) {
        fatal( $@ );
    }

    my $localStagingFile;
    if( $transferProtocol->isLocal()) {
        $localStagingFile = $toFile;
    } else {
        $localStagingFile = File::Temp->new( UNLINK => 1, DIR => UBOS::Host::tmpdir() )->filename;
    }

    trace( 'Performing backup to:', $localStagingFile );

    my $backup = UBOS::Backup::ZipFileBackup->new();
    my $ret = UBOS::BackupUtils::performBackup( $backup, $localStagingFile, $sitesP, $appConfigsP, $noTls, $noTorKey );
    unless( $ret ) {
        error( 'performBackup:', $@ );
    }

    my $encryptedStagingFile;
    if( $encryptId ) {
        trace( 'Encrypting:', $encryptId, $localStagingFile );

        $encryptedStagingFile = File::Temp->new( UNLINK => 1, DIR => UBOS::Host::tmpdir() )->filename;

        my $err;
        if( UBOS::Utils::myexec( "gpg --encrypt -r '$encryptId' < '$localStagingFile' > '$encryptedStagingFile'", undef, undef, \$err )) {
            fatal( 'Encryption failed:', $err );
        }
        UBOS::Utils::deleteFile( $localStagingFile ); # free up space asap
    }

    if( $configChanged && !$noStoreConfig ) {
        unless( $firstTime ) {
            info( 'Configuration changed. Defaults were updated.' );
        }

        UBOS::Utils::writeJsonToFile( $configFile, $config, 0600 );
    }

    debugAndSuspend( 'Sending data' );

    $ret &= $transferProtocol->send( $encryptedStagingFile || $localStagingFile, $toFile, $config );

    if( $ret ) {
        info( 'Backup saved to:', $toFile );
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
    --tofile <backupfileurl>
SSS
    Back up to into the named file <backupfileurl>, which can be a local file
    name or a URL.
HHH
            <<SSS => <<HHH
    --todirectory <backupdirurl>
SSS
    Back up to a file with an auto-generated name, which will be located in
    the directory <backupdirurl>, which can be a local directory name or a URL
    referring to a directory.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--notls' => <<HHH,
    If a site uses TLS, do not put the TLS key and certificate into the
    backup.
HHH
            '--notorkey' => <<HHH,
    If a site is on the Tor network, do not put the Tor key into the
    backup.
HHH
            '--encryptid <id>' => <<HHH,
    If given, the backup file will be gpg-encrypted,
    using GPG key id <id> in the current user's GPG keychain.
HHH
            '--config <configfile>' => <<HHH,
    Use an alternate configuration file. Default location of the
    configuration file is at $DEFAULT_CONFIG_FILE.
HHH
            '--nostoreconfig' => <<HHH,
    Do not store credentials or other configuration for future
    reuse. Do not use already-stored configuration information either.
    If this is given, do not specify --config <configfile>.
HHH
            '--siteid <siteid>' => <<HHH,
    Only back up the site with site id <siteid>. This option may be
    repeated.
HHH
            '--hostname <hostname>' => <<HHH,
    Only back up the site with hostnames <hostname>. This option may be
    repeated. If using this option, --appconfigid cannot be used at the
    same time.
HHH
            '--hostname <hostname> --context <context>' => <<HHH,
    Only back up the AppConfiguration at context path <context> at the
    site with hostname <hostname>. The option --context may be repeated.
    In this mode, the option --hostname may not be repeated.
HHH
            '--appconfigid <appconfigid>' => <<HHH,
    Only back up the AppConfiguration with AppConfigId <appconfigid>.
    This option may be repeated. If using this option, --hostname or
    --siteid cannot be used at the same time.
HHH
        }
    };
}

1;
