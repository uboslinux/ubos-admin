#!/usr/bin/perl
#
# Manages resources. This now works without depending on MySQL.
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

package UBOS::ResourceManager;

use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $ubosDbName       = 'ubos';
my $dbNamesTableName = 'databases';

##
# Initialize this ResourceManager if needed. This involves creating the administrative tables
# if run for the first time.
sub initializeIfNeeded {
    my( $rootUser, $rootPass ) = UBOS::Databases::MySqlDriver::findRootUserPass();

    unless( $rootUser ) {
        error( 'Cannot find MySQL root user credentials' );
        return 0;
    }

    my $dbh = UBOS::Databases::MySqlDriver::dbConnect( undef, $rootUser, $rootPass );

    # We proceed even in case of errors
    UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
CREATE DATABASE IF NOT EXISTS `$ubosDbName` CHARACTER SET = 'utf8'
SQL

    UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
CREATE TABLE IF NOT EXISTS `$ubosDbName`.`$dbNamesTableName` (
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

    UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
ALTER TABLE `$ubosDbName`.`$dbNamesTableName`
ADD COLUMN 
    dbType                   VARCHAR(16)
AFTER
    itemName
;
SQL
    $dbh->{HandleError} = $oldErrorMethod;

    UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL );
UPDATE `$ubosDbName`.`$dbNamesTableName`
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

    debug( 'ResourceManager::getDatabase', $dbType, $appConfigId, $installableId, $itemName );

    my $dbh = UBOS::Databases::MySqlDriver::dbConnectAsRoot( $ubosDbName );
    my $sth = UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType );
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
            error( 'More than one database found, not good:', $dbName );
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

    debug( 'ResourceManager::provisionLocalDatabase', $dbType, $appConfigId, $installableId, $itemName, $privileges );

    my $dbDriver = UBOS::Host::obtainDbDriver( $dbType, 'localhost' );
    unless( $dbDriver ) {
        UBOS::Logging::error( 'Unknown database type', $dbType );
        return;
    }

    my $dbName              = UBOS::Utils::randomIdentifier( 16 ); # unlikely to collide
    my $dbHost              = 'localhost';
    my $dbPort              = $dbDriver->defaultPort();
    my $dbUserLid           = UBOS::Utils::randomPassword( 16 );
    my $dbUserLidCredential = UBOS::Utils::randomPassword( 16 );
    my $dbUserLidCredType   = 'simple-password';

    my $dbh = UBOS::Databases::MySqlDriver::dbConnectAsRoot( $ubosDbName );
    my $sth = UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType, $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType );
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
# return: success or fail
sub unprovisionLocalDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    debug( 'ResourceManager::unprovisionLocalDatabase', $dbType, $appConfigId, $installableId, $itemName );

    my $dbh = UBOS::Databases::MySqlDriver::dbConnectAsRoot( $ubosDbName );
    my $sth = UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType );
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
        $dbDriver = UBOS::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
        if( $dbDriver ) {
            $sth = UBOS::Databases::MySqlDriver::sqlPrepareExecute( $dbh, <<SQL, $appConfigId, $installableId, $itemName, $dbType );
DELETE FROM `$dbNamesTableName`
WHERE  appConfigurationId = ?
  AND  installableId = ?
  AND  itemName = ?
  AND  dbType = ?
SQL
            $sth->finish();
            
        } else {
            error( 'Unknown database type', $dbType );
        }
    }
    $dbh->disconnect();
    
    if( $dbName && $dbDriver ) {
        return $dbDriver->unprovisionLocalDatabase( $dbName );
    }
    return 0;
}

1;
