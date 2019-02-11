#!/usr/bin/perl
#
# Abstracts away everything needed to perform a backup, so clients have
# an easier time.
#
# This object collects more and more data on invocations until it carries
# everything so that backup and upload can be performed without further
# arguments.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::BackupOperation;

use fields qw( dataTransferConfiguration dataTransferProtocol
               sitesToBackup appConfigsToBackup
               sitesToSuspendResume
               stageToEncryptFile
               stageToUploadFile uploadFile
               deleteFiles );

# sitesToBackup:        hash of the sites whose site information (not appconfig)
#                       should be written into the backup
# appConfigsToBackup:   hash of the appconfigs whose information (not site)
#                       should be written into the backup
# sitesToSuspendResume: if sites are backed up, same as sitesToBackup
#                       if appconfigs are backed up, their sites
# stageToEncryptFile:   the output of the backup process before encryption
# stageToUploadFile:    the output of the encryption process before upload;
#                       same as stageToEncryptFile if no encryption
# uploadFile:           full network path of the uploaded file's final destination
# deleteFiles:          keep those File::Temp objects around so they won't get
#                       deleted prematurely

use Getopt::Long qw( GetOptionsFromArray :config pass_through );
use UBOS::BackupOperations::NoOp;
use UBOS::BackupOperations::ToDirectory;
use UBOS::BackupOperations::ToFile;
use UBOS::DataTransferConfiguration;
use UBOS::Logging;
use UBOS::Utils;

my $DEFAULT_CONFIG_FILE = '/etc/ubos/backup-config.json';

##
# Factory method
# @$argP: the remaining command-line arguments
# return the instance of BackupOperation
sub parseArgumentsPartial {
    my $argP = shift;

    my $backupToFile             = undef;
    my $backupToDirectory        = undef;
    my $backupTls                = undef;
    my $backupTorKey             = undef;
    my $encryptId                = undef;
    my $dataTransferConfigFile   = undef;
    my $ignoreDataTransferConfig = undef;

    my $parseOk = GetOptionsFromArray(
            $argP,
            'backuptofile|tofile=s',          => \$backupToFile,
            'backuptodirectory|todirectory=s' => \$backupToDirectory,
            'backuptls!'                      => \$backupTls,
            'backuptorkey!'                   => \$backupTorKey,
            'backupencryptid|encryptid=s'     => \$encryptId,
            'backupdatatransferconfigfile=s'  => \$dataTransferConfigFile,
            'nobackupdatatransferconfigfile'  => \$ignoreDataTransferConfig );

    if(     !$parseOk
        || ( $backupToFile && $backupToDirectory )
        || ( $dataTransferConfigFile && $ignoreDataTransferConfig ))
    {
        $@ = undef;
        return undef;
    }

    my $ret;
    if( $backupToFile ) {
        $ret = UBOS::BackupOperations::ToFile->new(
                $backupToFile,
                $dataTransferConfigFile,
                $ignoreDataTransferConfig,
                $argP );

    } elsif( $backupToDirectory ) {
        $ret = UBOS::BackupOperations::ToDirectory->new(
                $backupToDirectory,
                $dataTransferConfigFile,
                $ignoreDataTransferConfig,
                $argP );

    } elsif( !$dataTransferConfigFile && !$ignoreDataTransferConfig ) {
        $ret = UBOS::BackupOperations::NoOp->new();

    } else {
        $@ = undef;
        return undef;
    }

    my $authority = $ret->authority();
    if( defined( $backupTls )) {
        $self->{dataTransferConfiguration}->setValue( 'backup', $authority, 'backuptls', $backupTls );
    }
    if( defined( $backupTorKey )) {
        $self->{dataTransferConfiguration}->setValue( 'backup', $authority, 'backuptorkey', $backupTorKey );
    }
    if( defined( $encryptId )) {
        if( $encryptId ) {
            $self->{dataTransferConfiguration}->setValue( 'backup', $authority, 'encryptid', $encryptId );
        } else {
            $self->{dataTransferConfiguration}->removeValue( 'backup', $authority, 'encryptid' );
        }
    }
    return $ret;
}

##
# Constructor for subclasses only.
# $dataTransferConfigFile: name of the data transfer config file provided by the user
# $ignoreDataTransferConfig: ignore data transfer config files for read and write
# @$argP: the remaining command-line arguments
# return: instance, or undef with $@ set
sub new {
    my $self                     = shift;
    my $dataTransferConfigFile   = shift;
    my $ignoreDataTransferConfig = shift;
    my $argP                     = shift;

    trace( 'BackupOperation::new', $dataTransferConfigFile, $ignoreDataTransferConfig, @$argP );

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->{dataTransferConfiguration} = UBOS::DataTransferConfiguration->new(
            $DEFAULT_CONFIG_FILE,
            $dataTransferConfigFile,
            $ignoreDataTransferConfig );
    unless( $self ) {
        return undef;
    }

    return $self;
}

##
# Is this a No op?
sub isNoOp {

    return 0;
}

##
# Analyze the provided parameters, determine what needs to be backed up
# and where to
# @siteIds: the SiteIds of the Sites to back up
# @appConfigIds: the AppConfigIds of the AppConfigs to back up
# return: true or false
sub analyze {
    my $self         = shift;
    my @siteIds      = @{shift()};
    my @appConfigIds = @{shift()};

    trace( 'BackupOperation::analyze', @siteIds, @appConfigIds );

    my $sites                = {};
    my $appConfigs           = {};
    my $sitesToSuspendResume = {};

    # first make sure there is no overlap between them
    foreach my $appConfigId ( @appConfigIds ) {
        my $appConfig = UBOS::Host::findAppConfigurationByPartialId( $appConfigId );
        unless( $appConfig ) {
            fatal( $@ );
        }
        if( exists( $appConfigs->{$appConfig->appConfigId} )) {
            fatal( 'Appconfigid specified more than once:', $appConfig->appConfigId );
        }
        $appConfigs->{$appConfig->appConfigId} = $appConfig;

        my $site = $appConfig->site();
        $sitesToSuspendResume->{$site->siteId} = $site;
    }
    foreach my $siteId ( @siteIds ) {
        my $site = UBOS::Host::findSiteByPartialId( $siteId );
        unless( $site ) {
            fatal( $@ );
        }
        if( exists( $sites->{$site->siteId} )) {
            fatal( 'Siteid specified more than once:', $site->siteId );
        }
        $sites->{$site->siteId}                = $site;
        $sitesToSuspendResume->{$site->siteId} = $site;
    }

    if( !@appConfigIds && !@siteIds ) {
        $sites                = UBOS::Host::sites();
        $sitesToSuspendResume = $sites;
    }
    foreach my $site ( values %$sites ) {
        my $appConfigsAtSite = $site->appConfigs;

        foreach my $appConfig ( @$appConfigsAtSite ) {
            if( exists( $appConfigs->{$appConfig->appConfigId} )) {
                fatal( 'Appconfigid', $appConfig->appConfigId . 'is also part of site:', $site->siteId );
            }
            $appConfigs->{$appConfig->appConfigId} = $appConfig;
        }
    }

    trace( 'Analyzed what needs backing up. Sites: ',      values %$sites );
    trace( 'Analyzed what needs backing up. AppConfigs: ', values %$appConfigs );

    $self->{sitesToBackup}        = $sites;
    $self->{appConfigsToBackup}   = $appConfigs;
    $self->{sitesToSuspendResume} = $sitesToSuspendResume;

    return 1;
}

##
# As an alternative to analyze, set the sites to backup here. This
# implies all the AppConfigurations at all those sites as well.
# %$sitesToBackup: hash of sites to back up: siteId to Site
sub setSitesToBackUp {
    my $self          = shift;
    my $sitesToBackup = shift;

    trace( 'BackupOperation::setSitesToBackUp', keys %$sitesToBackup );

    $self->{sitesToBackup}        = $sitesToBackup;
    $self->{sitesToSuspendResume} = $sitesToBackup; # same
    $self->{appConfigsToBackup}   = {};

    foreach my $site ( values %$sitesToBackup ) {
        map{ $self->{appConfigsToBackup}->{ $_->appConfigId() } = $_; } @{$site->appConfigs()};
    }
}

##
# Determine the sites that need to be suspended and resumed for this backup.
# return: array of Site
sub getSitesToSuspendResume {
    my $self = shift;

    return values %{$self->{sitesToBackup}};
}

##
# Define which files will be created, and check that they can be created.
# return: true or false
sub constructCheckPipeline {
    my $self = shift;

    trace( 'BackupOperation::constructCheckPipeline' );

    if( $self->{dataTransferProtocol}->isLocal()) {
        $self->{stageToUploadFile} = $self->{uploadFile};
    } else {
        $self->{stageToUploadFile} = $self->mkTempFile();
    }

    if( $self->{dataTransferConfiguration}->getValue( 'backup', $self->{dataTransferProtocol}->authority(), 'encryptid' )) {
        $self->{stageToEncryptFile} = $self->mkTempFile();
    } else {
        $self->{stageToEncryptFile} = $self->{stageToUploadFile};
    }

    my $ret = $self->{dataTransferProtocol}->isValidToFile( $self->{uploadFile} );
    return $ret;
}

##
# Perform the actual backup.
# return: true or false
sub doBackup {
    my $self = shift;

    trace( 'BackupOperation::doBackup' );

    my $backup = UBOS::Backup::ZipFileBackup->new();
    my $ret    = $backup->create(
            [ values %{$self->{sitesToBackup}} ],
            [ values %{$self->{appConfigsToBackup}} ],
            $self->{dataTransferConfiguration}->getValue( 'backup', $self->{dataTransferProtocol}->authority(), 'backuptls',    0 ),
            $self->{dataTransferConfiguration}->getValue( 'backup', $self->{dataTransferProtocol}->authority(), 'backuptorkey', 0 ),
            $self->{stageToEncryptFile} );

    return $ret;
}

##
# Deposit the backup where it is supposed to end up. This will also
# perform encryption if needed.
# return: true or false
sub doUpload {
    my $self = shift;

    trace( 'BackupOperation::doUpload' );

    my $encryptId = $self->{dataTransferConfiguration}->getValue( 'backup', $self->{dataTransferProtocol}->authority(), 'encryptid' );
    if( $encryptId ) {
        my $stageToEncryptFile = $self->{stageToEncryptFile};
        my $stageToUploadFile  = $self->{stageToUploadFile};

        trace( 'Encrypting:', $stageToEncryptFile, $stageToUploadFile );

        my $err;
        if( UBOS::Utils::myexec( "gpg --encrypt -r '$encryptId' < '$stageToEncryptFile' > '$stageToUploadFile'", undef, undef, \$err )) {
            fatal( 'Encryption failed:', $err );
        }
        UBOS::Utils::deleteFile( $stageToEncryptFile ); # free up space asap
    }

    debugAndSuspend( 'Sending backup data' );

    my $ret = $self->{dataTransferProtocol}->send(
            $self->{stageToUploadFile},
            $self->{uploadFile},
            $self->{dataTransferConfiguration} );

    if( $ret ) {
        info( 'Backup sent to:', $self->{uploadFile} );
    }
    return $ret;
}

##
# Clean up
# return: true or false
sub finish {
    my $self = shift;

    trace( 'BackupOperation::finish' );

    $self->{dataTransferConfiguration}->saveIfNeeded();

    return 1;
}

##
# Helper method to make a tmp file which is deleted only
# at the end
# return: filename of the tmp file
sub mkTempFile {
    my $self = shift;

    my $tmp = File::Temp->new( UNLINK => 1, DIR => UBOS::Host::tmpdir() );
    push @{$self->{deleteFiles}}, $tmp;

    return $tmp->filename;
}

1;
