#!/usr/bin/perl
#
# Manages resources.
#
# This file is part of indiebox-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-admin.  If not, see <http://www.gnu.org/licenses/>.
#

#
# Table `databases`:
#   appConfigurationId:  identifier of the AppConfiguration that the database is allocated to
#   installableId:       of the one or more Installables at this AppConfiguration, identify which
#   itemName:            the symbolic name of the database as per the manifest of the Installable
#   dbType:              type of database, e.g. mysql or mongo
#   dbName:              actual provisioned database name
#   dbHost:              database host, usually 'localhost'
#   dbPort:              database port, usually 3306
#   dbUserLid:           database user created for this database
#   dbUserLidCredential: credential for the user created for this database
#   dbUserLidCredType:   type of credential, usually 'simple-password'
#

use strict;
use warnings;

package IndieBox::ResourceManager;

use IndieBox::Databases::MySqlDriver;
# Modules supporting other databases are loaded on demand
use IndieBox::Host;
use IndieBox::Logging;
use IndieBox::Utils;

my $indieBoxDbName   = 'indiebox';
my $dbNamesTableName = 'databases';

##
# Initialize this ResourceManager if needed. This involves creating the administrative tables
# if run for the first time.
sub initializeIfNeeded {
    my( $rootUser, $rootPass ) = IndieBox::Databases::MySqlDriver::findRootUserPass();

    unless( $rootUser ) {
        error( 'Cannot find MySQL root user credentials' );
        return 0;
    }

    my $dbh = IndieBox::Databases::MySqlDriver::dbConnect( undef, $rootUser, $rootPass );

    # We proceed even in case of errors
    IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
CREATE DATABASE IF NOT EXISTS `$indieBoxDbName` CHARACTER SET = 'utf8'
SQL

    IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
CREATE TABLE IF NOT EXISTS `$indieBoxDbName`.`$dbNamesTableName` (
    appConfigurationId       VARCHAR(64),
    installableId            VARCHAR(64),
    itemName                 VARCHAR(32),
    dbName                   VARCHAR(64),
    dbHost                   VARCHAR(128),
    dbPort                   SMALLINT,
    dbUserLid                VARCHAR(64),
    dbUserLidCredential      VARCHAR(41),
    dbUserLidCredType        VARCHAR(32),
    UNIQUE KEY( appConfigurationId, installableId, itemName )
);
SQL

    # For now, upgrade already deployed hosts. But eat errors if they occur
    my $oldErrorMethod = $dbh->{HandleError};
    $dbh->{HandleError} = undef;

    IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
ALTER TABLE `$indieBoxDbName`.`$dbNamesTableName`
ADD COLUMN 
    dbType                   VARCHAR(16)
AFTER
    itemName
;
SQL
    $dbh->{HandleError} = $oldErrorMethod;

    IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
UPDATE `$indieBoxDbName`.`$dbNamesTableName`
SET dbType = 'mysql' WHERE dbType = '' OR dbType IS NULL;
SQL
}

##
# Find an already-provisioned database of a certain type for a given id of an AppConfiguration,
# the id of an Installable at that AppConfiguration, and the symbolic database name per manifest.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $name: the symbolic database name per application manifest
# return: tuple of dbName, dbHost, dbPort, dbUser, dbPassword, dbCredentialType, or undef
sub getDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    trace( 'getDatabase', $dbType, $appConfigId, $installableId, $itemName );

    my $dbh = IndieBox::Databases::MySqlDriver::dbConnectAsRoot( $indieBoxDbName );
    my $sth = IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType );
SELECT dbName,
       dbHost,
       dbPort,
       dbUserLid,
       dbUserLidCredential
FROM   `$dbNamesTableName`
WHERE  appConfigurationId = ?
  AND  installableId = ?
  AND  itemName = ?
  AND  dbType = ?
SQL

    my $dbName;
    my $dbHost;
    my $dbPort;
    my $dbUserLid;
    my $dbUserLidCredential;
    my $dbUserLidCredType;

    while( my $ref = $sth->fetchrow_hashref() ) {
        if( $dbName ) {
            error( 'More than one found, not good:', $dbName );
            last;
        }
        $dbName              = $ref->{'dbName'};
        $dbHost              = $ref->{'dbHost'};
        $dbPort              = $ref->{'dbPort'};
        $dbUserLid           = $ref->{'dbUserLid'};
        $dbUserLidCredential = $ref->{'dbUserLidCredential'};
        $dbUserLidCredType   = $ref->{'dbUserLidCredType'};
    }
    $sth->finish();
    $dbh->disconnect();

    if( $dbName ) {
        return( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType );
    } else {
        return undef;
    }
}

##
# Provision a local database.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
# $privileges: string containing required database privileges, like "create, insert"
# return: hash of dbName, dbHost, dbUser, dbPassword, or undef
sub provisionLocalDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;
    my $privileges    = shift;

    trace( 'provisionLocalDatabase', $dbType, $appConfigId, $installableId, $itemName, $privileges );

    my $dbDriver = IndieBox::Host::obtainDbDriver( $dbType, 'localhost' );
    unless( $dbDriver ) {
        IndieBox::Logging::error( 'Unknown database type', $dbType );
        return;
    }

    my $dbName              = IndieBox::Utils::randomIdentifier( 16 ); # unlikely to collide
    my $dbHost              = 'localhost';
    my $dbPort              = $dbDriver->defaultPort();
    my $dbUserLid           = IndieBox::Utils::randomPassword( 16 );
    my $dbUserLidCredential = IndieBox::Utils::randomPassword( 16 );
    my $dbUserLidCredType   = 'simple-password';

    my $dbh = IndieBox::Databases::MySqlDriver::dbConnectAsRoot( $indieBoxDbName );
    my $sth = IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType, $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType );
INSERT INTO `$dbNamesTableName`(
    appConfigurationId,
    installableId,
    itemName,
    dbType,
    dbName,
    dbHost,
    dbPort,
    dbUserLid,
    dbUserLidCredential,
    dbUserLidCredType )
VALUES (
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ?,
    ? )
SQL
    $sth->finish();
    $dbh->disconnect();

    $dbDriver->provisionLocalDatabase( $dbName, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType, $privileges );
    
    return( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType );
}

##
# Unprovision a local database.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
sub unprovisionLocalDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    trace( 'unprovisionLocalDatabase', $dbType, $appConfigId, $installableId, $itemName );

    my $dbh = IndieBox::Databases::MySqlDriver::dbConnectAsRoot( $indieBoxDbName );
    my $sth = IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType );
SELECT dbName,
       dbHost,
       dbPort
FROM   `$dbNamesTableName`
WHERE  appConfigurationId = ?
  AND  installableId = ?
  AND  itemName = ?
  AND  dbType = ?
SQL

    my $dbName;
    my $dbHost;
    my $dbPort;

    while( my $ref = $sth->fetchrow_hashref() ) {
        if( $dbName ) {
            error( 'More than one found, not good:', $dbName );
            last;
        }
        $dbName = $ref->{'dbName'};
        $dbHost = $ref->{'dbHost'};
        $dbPort = $ref->{'dbPort'};
    }
    $sth->finish();

    my $dbDriver = undef;
    if( $dbName ) {
        $dbDriver = IndieBox::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
        if( $dbDriver ) {
            $sth = IndieBox::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType );
DELETE FROM `$dbNamesTableName`
WHERE  appConfigurationId = ?
  AND  installableId = ?
  AND  itemName = ?
  AND  dbType = ?
SQL
            $sth->finish();
            
        } else {
            IndieBox::Logging::error( 'Unknown database type', $dbType );
        }
    }
    $dbh->disconnect();
    
    if( $dbName && $dbDriver ) {
        $dbDriver->unprovisionLocalDatabase( $dbName );
    }
}

##
# Export the content of a local database.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
# $fileName: the file to write to
sub exportLocalDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;
    my $fileName      = shift;

    trace( 'exportLocalDatabase', $dbType, $appConfigId, $installableId, $itemName, $fileName );

    my( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
            = getDatabase( $dbType, $appConfigId, $installableId, $itemName );

    my $dbDriver = IndieBox::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
    unless( $dbDriver ) {
        IndieBox::Logging::error( 'Unknown database type', $dbType );
        return;
    }

    $dbDriver->exportLocalDatabase( $dbName, $fileName );
}

##
# Replace the content of a local database.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
# $fileName: the file to write to
sub importLocalDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;
    my $fileName      = shift;

    trace( 'importLocalDatabase', $dbType, $appConfigId, $installableId, $itemName, $fileName );

    my( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
            = getDatabase( $dbType, $appConfigId, $installableId, $itemName );

    my $dbDriver = IndieBox::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
    unless( $dbDriver ) {
        IndieBox::Logging::error( 'Unknown database type', $dbType );
        return;
    }

    $dbDriver->importLocalDatabase( $dbName, $fileName );
}

1;

