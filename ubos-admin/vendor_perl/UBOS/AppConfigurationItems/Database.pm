#!/usr/bin/perl
#
# An AppConfiguration item that is any kind of database.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AppConfigurationItems::Database;

use base   qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields;

use UBOS::Host;
use UBOS::Logging;
use UBOS::ResourceManager;
use UBOS::Utils qw( saveFile slurpFile );

##
# Constructor
# $json: the JSON fragment from the manifest JSON
# $role: the Role to which this item belongs to
# $appConfig: the AppConfiguration object that this item belongs to
# $installable: the Installable to which this item belongs to
# return: the created File object
sub new {
    my $self        = shift;
    my $json        = shift;
    my $role        = shift;
    my $appConfig   = shift;
    my $installable = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $json, $role, $appConfig, $installable );

    return $self;
}

##
# Install this item, or check that it is installable.
# $doIt: if 1, install; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub deployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $name   = $self->{json}->{name};
    my $dbType = $self->{role}->name();

    trace( 'Database::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $dbType, $name );

    my( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
            = UBOS::ResourceManager::findProvisionedDatabaseFor(
                    $dbType,
                    $self->{appConfig}->appConfigId,
                    $self->{installable}->packageName,
                    $name );
    unless( $dbName ) {
        my $privileges = $self->{json}->{privileges};
        my $charset    = $self->{json}->{charset};
        my $collate    = $self->{json}->{collate};

        if( $doIt ) {
            ( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
                    = UBOS::ResourceManager::provisionLocalDatabase(
                            $dbType,
                            $self->{appConfig}->appConfigId,
                            $self->{installable}->packageName,
                            $name,
                            $privileges,
                            $charset,
                            $collate );
        } else {
            # put it some placeholder values, so the variables resolve
            ( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
                    = ( 'placeholderDbName', 'placeholderDbHost', '9999', 'placeholderUserLid', 'placeholderUserLidCredential', 'simple-password' );
        }
    }
    # now insert those values into the vars object
    $vars->put( "appconfig.$dbType.dbname.$name",           $dbName );
    $vars->put( "appconfig.$dbType.dbhost.$name",           $dbHost );
    $vars->put( "appconfig.$dbType.dbport.$name",           $dbPort );
    $vars->put( "appconfig.$dbType.dbuser.$name",           $dbUserLid );
    $vars->put( "appconfig.$dbType.dbusercredential.$name", $dbUserLidCredential );

    return $dbName ? 1 : 0;
}

##
# Uninstall this item, or check that it is uninstallable.
# $doIt: if 1, uninstall; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub undeployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $name   = $self->{json}->{name};
    my $dbType = $self->{role}->name();

    trace( 'Database::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $dbType, $name );

    if( $doIt ) {
        return UBOS::ResourceManager::unprovisionLocalDatabase(
                $dbType,
                $self->{appConfig}->appConfigId,
                $self->{installable}->packageName,
                $name );
    }
    return 1;
}

##
# Back this item up.
# $dir: the directory in which the app was installed
# $vars: the Variables object that knows about symbolic names and variables
# $backupContext: the Backup Context object
# $filesToDelete: array of filenames of temporary files that need to be deleted after backup
# $compress: compression method to use, or undef
# return: success or fail
sub backup {
    my $self          = shift;
    my $dir           = shift;
    my $vars          = shift;
    my $backupContext = shift;
    my $filesToDelete = shift;
    my $compress      = shift;

    my $bucket = $self->{json}->{retentionbucket};
    my $name   = $self->{json}->{name};

    trace( 'Database::backup', $bucket, $name );

    my $exportedFile = $self->exportLocalDatabase(
            $self->{appConfig}->appConfigId,
            $self->{installable}->packageName,
            $name,
            $compress );

    if( $exportedFile ) {
        my $ret = $backupContext->addFile( $exportedFile, $bucket );

        push @$filesToDelete, $exportedFile;

        return $ret;

    } else {
        return 0;
    }
}

##
# Restore this item from backup.
# $dir: the directory in which the app was installed
# $vars: the Variables object that knows about symbolic names and variables
# $backupContext: the Backup Context object
# return: success or fail
sub restore {
    my $self          = shift;
    my $dir           = shift;
    my $vars          = shift;
    my $backupContext = shift;

    my $bucket = $self->{json}->{retentionbucket};
    my $name   = $self->{json}->{name};

    trace( 'Database::restore', $bucket, $name );

    my $ret = 1;

    my $compress    = undef;
    my $restoreFrom = $backupContext->restore( $bucket );
    unless( $restoreFrom ) {
        # try compressed
        $restoreFrom = $backupContext->restore( "$bucket.gz" );
        if( $restoreFrom ) {
            $compress = 'gz';
        }
    }
    unless( $restoreFrom ) {
        error( 'Cannot restore database: bucket:', $bucket, 'context:', $backupContext->asString() );
        $ret = 0;
        return $ret;
    }

    my ( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
            = $self->importLocalDatabase(
                    $self->{appConfig}->appConfigId,
                    $self->{installable}->packageName,
                    $name,
                    $restoreFrom,
                    $compress );
    if( $dbName ) {
        my $dbType = $self->{role}->name();
        # now insert those values into the vars object
        $vars->put( "appconfig.$dbType.dbname.$name",           $dbName );
        $vars->put( "appconfig.$dbType.dbhost.$name",           $dbHost );
        $vars->put( "appconfig.$dbType.dbport.$name",           $dbPort );
        $vars->put( "appconfig.$dbType.dbuser.$name",           $dbUserLid );
        $vars->put( "appconfig.$dbType.dbusercredential.$name", $dbUserLidCredential );

    } else {
        $ret = 0;
    }
    return $ret;
}

##
# Export the content of a local database.
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
# $compress: compression method to use, or undef
# return: the filename written to, or undef
sub exportLocalDatabase {
    my $self          = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;
    my $compress      = shift;

    my $dbType = $self->{role}->name();

    my( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
            = UBOS::ResourceManager::findProvisionedDatabaseFor( $dbType, $appConfigId, $installableId, $itemName );

    my $dbDriver = UBOS::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
    unless( $dbDriver ) {
        error( 'Database::exportLocalDatabase: unknown database type', $dbType );
        return 0;
    }

    return $dbDriver->exportLocalDatabase( $dbName, $compress );
}

##
# Replace the content of a local database.
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
# $fileName: the file to read from
# $compress: decompression method to use, or undef
# return: ( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType ) or 0
sub importLocalDatabase {
    my $self          = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;
    my $fileName      = shift;
    my $compress      = shift;

    my $dbType = $self->{role}->name();

    my( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
            = UBOS::ResourceManager::findProvisionedDatabaseFor( $dbType, $appConfigId, $installableId, $itemName );

    my $dbDriver = UBOS::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
    unless( $dbDriver ) {
        error( 'Database::importLocalDatabase: unknown database type', $dbType );
        return 0;
    }

    if( $dbDriver->importLocalDatabase( $dbName, $fileName, $compress, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )) {
        return ( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType );
    } else {
        return 0;
    }
}

1;
