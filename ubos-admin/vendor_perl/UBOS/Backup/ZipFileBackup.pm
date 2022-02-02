#!/usr/bin/perl
#
# A Backup implemented as a ZIP file
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Backup::ZipFileBackup;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use UBOS::AppConfiguration;
use UBOS::Backup::ZipFileBackupContext;
use UBOS::Logging;
use UBOS::Site;
use UBOS::Utils qw( readJsonFromString writeJsonToString );
use JSON;

use base qw( UBOS::AbstractBackup );
use fields qw( zip file );

my $fileType                 = 'UBOS::Backup::ZipFileBackup;v1';
my $zipFileTypeEntry         = 'filetype';
my $zipFileStartTimeEntry    = 'starttime';
my $zipFileSiteEntry         = 'sites';
my $zipFileInstallablesEntry = 'installables';
my $zipFileAppConfigsEntry   = 'appconfigs';

##
# Constructor.
sub new {
    my $self = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new();

    return $self;
}

##
# Type of backup this class understands.
# return: the type of backup
sub backupType {
    return 'ubos-backup';
}

##
# Determine the form of compression used by this backup type.
# return: the form of compression
sub compression {
    return 'zip';
}

##
# Obtain the file that holds this Backup, if any
# return: file name
sub fileName {
    my $self = shift;

    return $self->{file};
}

##
# Save the specified Sites and AppConfigurations to a file, and return the
# corresponding Backup object. If a Site has N AppConfigurations, all of those
# AppConfigurations must be listed in the $appConfigs
# array to be backed up. If they are not, only Site meta-data (but none of the AppConfiguration data)
# will be saved.
# $sites: array of Site objects
# $appConfigs: array of AppConfiguration objects
# $backupTls: if 1, include TLS info otherwise strip
# $backupTorKey: if 1, include Tor private keys for Tor sites otherwise strip
# $outFile: the file to save the backup to
sub create {
    my $self         = shift;
    my $sites        = shift;
    my $appConfigs   = shift;
    my $backupTls    = shift;
    my $backupTorKey = shift;
    my $outFile      = shift;

    my $ret = 1;

    trace( 'ZipFileBackup::create', $sites, $appConfigs, $backupTls, $backupTorKey, $outFile );

    $self->{startTime}  = UBOS::Utils::time2string( time() );
    $self->{zip}        = Archive::Zip->new();
    $self->{sites}      = $sites;
    $self->{appConfigs} = $appConfigs;
    $self->{file}       = $outFile;

    my @filesToDelete = ();

    ##
    my $zip = $self->{zip}; # makes code shorter

    $ret &= ( $zip->addString( $fileType,                 $zipFileTypeEntry )      ? 1 : 0 );
    $ret &= ( $zip->addString( $self->{startTime} . "\n", $zipFileStartTimeEntry ) ? 1 : 0 );

    ##

    $ret &= ( $zip->addDirectory( "$zipFileSiteEntry/" ) ? 1 : 0 );

    foreach my $site ( @$sites ) {
        my $siteId = $site->siteId();
        my $siteJson;
        if( $backupTls ) {
            $siteJson = $site->siteJson();
        } else {
            $siteJson = $site->siteJsonWithoutTls();
        }
        if( !$backupTorKey && exists( $siteJson->{tor} ) && exists( $siteJson->{tor}->{privatekey} )) {
            delete $siteJson->{tor}->{privatekey};
            delete $siteJson->{hostname}; # create new key and hostname upon restore
        }
        $ret &= ( $zip->addString( writeJsonToString( $siteJson ), "$zipFileSiteEntry/$siteId.json" ) ? 1 : 0 );
    }

    ##

    $ret &= ( $zip->addDirectory( "$zipFileInstallablesEntry/" ) ? 1 : 0 );

    # construct table of installables
    my %installables = ();
    foreach my $appConfig ( @$appConfigs ) {
        foreach my $installable ( $appConfig->installables ) {
            $installables{$installable->packageName} = $installable;
        }
    }
    foreach my $packageName ( keys %installables ) {
        my $installable = $installables{$packageName};

        $ret &= ( $zip->addString( writeJsonToString( $installable->installableJson()), "$zipFileInstallablesEntry/$packageName.json" ) ? 1 : 0 );
    }

    ##

    $ret &= ( $zip->addDirectory( "$zipFileAppConfigsEntry/" ) ? 1 : 0 );

    my $rolesOnHost = UBOS::Host::rolesOnHost();

    foreach my $appConfig ( @$appConfigs ) {
        my $appConfigId = $appConfig->appConfigId;
        $ret &= ( $zip->addString( writeJsonToString( $appConfig->appConfigurationJson()), "$zipFileAppConfigsEntry/$appConfigId.json" ) ? 1 : 0 );
        $ret &= ( $zip->addDirectory( "$zipFileAppConfigsEntry/$appConfigId/" ) ? 1 : 0 );

        foreach my $installable ( $appConfig->installables ) {
            my $packageName = $installable->packageName;
            $ret &= ( $zip->addDirectory( "$zipFileAppConfigsEntry/$appConfigId/$packageName/" ) ? 1 : 0 );

            my $vars = $installable->obtainInstallableAtAppconfigVars( $appConfig, 1 );

            foreach my $roleName ( @{$installable->roleNames} ) {
                my $role = $rolesOnHost->{$roleName};
                if( $role ) { # don't attempt to backup anything not installed on this host
                    my $appConfigPathInZip = "$zipFileAppConfigsEntry/$appConfigId/$packageName/$roleName";
                    $ret &= ( $zip->addDirectory( "$appConfigPathInZip/" ) ? 1 : 0 );

                    my $dir = $vars->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );

                    my $appConfigItems = $installable->appConfigItemsInRole( $roleName );
                    if( $appConfigItems ) {
                        my $backupContext = UBOS::Backup::ZipFileBackupContext->new( $self, $appConfigPathInZip );

                        my $itemCount = 0;
                        foreach my $appConfigItem ( @$appConfigItems ) {
                            if( defined( $appConfigItem->{retentionpolicy} ) && $appConfigItem->{retentionpolicy} ) {
                                # for now, we don't care what value this field has as long as it is non-empty

                                my $item = $role->instantiateAppConfigurationItem( $appConfigItem, $appConfig, $installable );
                                if( $item ) {
                                    debugAndSuspend( 'Backup item', $itemCount, 'role', $roleName, 'installable', $packageName, 'appConfig', $appConfigId );
                                    $ret &= $item->backup( $dir, $vars, $backupContext, \@filesToDelete );
                                            # never specify compress here: zip will do it
                                }
                            }
                            ++$itemCount;
                        }
                    }
                }
            }
        }
    }

    $ret &= (( $zip->writeToFileNamed( $outFile ) == AZ_OK ) ? 1 : 0 );

    foreach my $current ( @filesToDelete ) {
        unless( unlink $current ) {
            error( 'Could not unlink', $current );
            $ret = 0;
        }
    }

    return $ret;
}

##
# Read the backup.
# $archive: the archive file name
# $zip: the Archive::Zip object
# return: true if successful
sub read {
    my $archive = shift;
    my $zip     = shift;

    trace( 'ZipFileBackup::read', $archive, $zip );

    my $foundFileType = $zip->contents( $zipFileTypeEntry );
    if( $foundFileType ) {
        $foundFileType =~ s!^\s+!!;
        $foundFileType =~ s!\s+$!!;

        unless( $foundFileType eq $fileType ) {
            return undef;
        }
    } else {
        return undef;
    }

    my $self = UBOS::Backup::ZipFileBackup->new();

    $self->{sites}      = {};
    $self->{appConfigs} = {};
    $self->{startTime}  = $zip->contents( $zipFileStartTimeEntry );
    $self->{file}       = $archive;
    $self->{zip}        = $zip;

    $self->{startTime} =~ s!^\s+!!;
    $self->{startTime} =~ s!\s+$!!;

    my $ret = $self;

    # Note that this creates AppConfiguration instances that are part of
    # a Site, and additional ones that aren't, even if they are part of
    # the same Site.
    foreach my $siteJsonFile ( $self->{zip}->membersMatching( "^$zipFileSiteEntry/s[0-9a-f]+\.json" )) {
        my $siteJsonContent = $self->{zip}->contents( $siteJsonFile );
        if( $siteJsonContent ) {
            my $siteJson = readJsonFromString( $siteJsonContent );
            my $site     = UBOS::Site->new( $siteJson, 0, 1, sub { return readManifestFromZip( $self->{zip}, shift ); } );

            unless( $site ) {
                fatal( $@ );
            }
            $self->{sites}->{$site->siteId()} = $site;

        } else {
            error( 'Cannot read ZIP file entry', $siteJsonFile );
            $ret = undef;
        }
    }
    foreach my $appConfigJsonFile ( $self->{zip}->membersMatching( "$zipFileAppConfigsEntry/[a-f0-9]+\\.json" )) {
        my $appConfigJsonContent = $self->{zip}->contents( $appConfigJsonFile );
        if( $appConfigJsonContent ) {
            my $appConfigJson = readJsonFromString( $appConfigJsonContent );
            my $appConfig     = UBOS::AppConfiguration->new( $appConfigJson, undef, 1, sub { return readManifestFromZip( $self->{zip}, shift ); } );

            $self->{appConfigs}->{$appConfig->appConfigId()} = $appConfig;

        } else {
            error( 'Cannot read ZIP file entry', $appConfigJsonFile );
            $ret = undef;
        }
    }

    return $ret;
}

##
# Restore a single AppConfiguration from Backup.
# $siteIdInBackup: the site id of the AppConfiguration to restore, as it is stored in the Backup
# $siteIdOnHost: the site id of the AppConfiguration to restore, on the host
# $appConfigInBackup: the AppConfiguration to restore, as it is stored in the Backup
# $appConfigOnHost: the AppConfiguration to restore to, on the host
# $migrationTable: hash of old package names to new packages names, for migrations
# return: success or fail
sub restoreAppConfiguration {
    my $self              = shift;
    my $siteIdInBackup    = shift;
    my $siteIdOnHost      = shift;
    my $appConfigInBackup = shift;
    my $appConfigOnHost   = shift;
    my $migrationTable    = shift;

    trace( 'ZipFileBackup::restoreAppConfiguration', $siteIdInBackup, $siteIdOnHost, $appConfigInBackup, $appConfigOnHost );

    my $ret                 = 1;
    my $zip                 = $self->{zip};
    my $appConfigIdInBackup = $appConfigInBackup->appConfigId;
    my $appConfigIdOnHost   = $appConfigOnHost->appConfigId;

    my $rolesOnHost = UBOS::Host::rolesOnHost();

    foreach my $installableInBackup ( $appConfigInBackup->installables ) {
        my $packageNameInBackup = $installableInBackup->packageName;
        unless( $zip->memberNamed( "$zipFileAppConfigsEntry/$appConfigIdInBackup/$packageNameInBackup/" )) {
            next;
        }
        my $packageNameOnHost = exists( $migrationTable->{$packageNameInBackup} ) ? $migrationTable->{$packageNameInBackup} : $packageNameInBackup;
        my $installableOnHost = $appConfigOnHost->installable( $packageNameOnHost );
        unless( $installableOnHost ) {
            error( 'Cannot find installable on host:', $installableInBackup, '->', $installableOnHost );
            next;
        }

        my $vars = $installableOnHost->obtainInstallableAtAppconfigVars( $appConfigOnHost, 1 );

        foreach my $roleName ( @{$installableOnHost->roleNames} ) {
            my $role = $rolesOnHost->{$roleName};
            if( $role ) { # don't attempt to restore anything not installed on this host
                my $appConfigPathInZip = "$zipFileAppConfigsEntry/$appConfigIdInBackup/$packageNameInBackup/$roleName";
                unless( $zip->memberNamed( "$appConfigPathInZip/" )) {
                    next;
                }

                my $appConfigItems = $installableOnHost->appConfigItemsInRole( $roleName );
                if( $appConfigItems ) {
                    my $dir = $vars->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );

                    my $backupContext = UBOS::Backup::ZipFileBackupContext->new( $self, $appConfigPathInZip );

                    my $itemCount = 0;
                    foreach my $appConfigItem ( @$appConfigItems ) {
                        if( defined( $appConfigItem->{retentionpolicy} ) && $appConfigItem->{retentionpolicy} ) {
                            # for now, we don't care what value this field has as long as it is non-empty

                            my $item = $role->instantiateAppConfigurationItem( $appConfigItem, $appConfigOnHost, $installableOnHost );
                            if( $item ) {
                                debugAndSuspend(
                                        'Restore item', $itemCount,
                                        'role',         $roleName,
                                        'installable',  $packageNameInBackup, '=>', $packageNameOnHost,
                                        'appConfig',    $appConfigIdInBackup, '=>', $appConfigIdOnHost );
                                $ret &= $item->restore( $dir, $vars, $backupContext );
                            }
                        }
                        ++$itemCount;
                    }
                }
            }
        }
    }
    return $ret;
}

##
# Knows how to read a manifest from a zip file instead of
# the default location in the file system. This is needed because
# the package in question may not be installed.
# $zip: the zip file to read from
# $packageIdentifier: the package identifier
# return: JSON
sub readManifestFromZip {
    my $zip               = shift;
    my $packageIdentifier = shift;

    my $file          = "installables/$packageIdentifier.json";
    my $foundManifest = $zip->contents( $file );
    unless( $foundManifest ) {
        fatal( 'Manifest for package', $packageIdentifier, 'not found in backup file.' );
    }
    my $ret = UBOS::Utils::readJsonFromString( $foundManifest );
    if( $ret ) {
        return $ret;
    } else {
        fatal( 'Failed to parse manifest file in backup file:', $file );
    }
}

1;
