#!/usr/bin/perl
#
# Manages resources. This now works without depending on MySQL.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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

# In directory /var/lib/ubos/resources, resource files are named:
# <appconfigid>_<installableId>_<type>_<itemName>.json
# e.g.
#   a1234.._wordpress_mysql_maindb.json
# The content of the JSON file depends on the type of item.
# For a database:
#   {
#       "dbName" : "<databasename>",
#       "dbHost" : "localhost",
#       "dbPort" : "3306",
#       "dbName" : "<databasename>",
#       "dbUserLid"           : <databaseuser>",
#       "dbUserLidCredential" : "<databasepassword>"
#       "dbUserLidCredType"   : "simple-password"
#   }

use strict;
use warnings;

package UBOS::ResourceManager;

use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $RESOURCES_DIR = '/var/lib/ubos/resources';
my $PINNED_DIR    = '/var/lib/ubos/pinned';

##
# Find an already-provisioned database of a certain type for a given id of an AppConfiguration,
# the id of an Installable at that AppConfiguration, and the symbolic database name per manifest.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $name: the symbolic database name per application manifest
# return: tuple of dbName, dbHost, dbPort, dbUser, dbPassword, dbCredentialType, or undef
sub findProvisionedDatabaseFor {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    debug( 'ResourceManager::findProvisionedDatabaseFor', $dbType, $appConfigId, $installableId, $itemName );

    my $file = $RESOURCES_DIR . '/' . $appConfigId . '_' . $installableId . '_' . $dbType . '_' . $itemName . '.json';
    unless( -e $file  ) {
        return undef;
    }
    my $json = UBOS::Utils::readJsonFromFile( $file );

    if( $json ) {
        return( $json->{dbName}, $json->{dbHost}, $json->{dbPort},
                $json->{dbUserLid}, $json->{dbUserLidCredential}, $json->{dbUserLidCredType} );
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
# $charset: default database character set name
# $collate: default database collation name
# return: hash of dbName, dbHost, dbUser, dbPassword, or undef
sub provisionLocalDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;
    my $privileges    = shift;
    my $charset       = shift;
    my $collate       = shift;

    debug( 'ResourceManager::provisionLocalDatabase', $dbType, $appConfigId, $installableId, $itemName, $privileges, $charset, $collate );

    my $dbDriver = UBOS::Host::obtainDbDriver( $dbType, 'localhost' );
    unless( $dbDriver ) {
        UBOS::Logging::error( 'Unknown database type', $dbType );
        return;
    }

    my $json = findPinnedLocalDatabaseData( $dbType, $appConfigId, $installableId, $itemName );

    unless( $json ) {
        $json = {};
    }
    unless( exists( $json->{dbName} )) {
        $json->{dbName} = UBOS::Utils::randomIdentifier( 16 ), # unlikely to collide
    }
    unless( exists( $json->{dbHost} )) {
        $json->{dbHost} = 'localhost';
    }
    unless( exists( $json->{dbPort} )) {
        $json->{dbPort} = $dbDriver->defaultPort();
    }
    unless( exists( $json->{dbUserLid} )) {
        $json->{dbUserLid} = UBOS::Utils::randomPassword( 16 );
    }
    unless( exists( $json->{dbUserLidCredential} )) {
        $json->{dbUserLidCredential} = UBOS::Utils::randomPassword( 16 );
    }
    unless( exists( $json->{dbUserLidCredType} )) {
        $json->{dbUserLidCredType} = 'simple-password';
    }

    $dbDriver->provisionLocalDatabase(
            $json->{dbName},
            $json->{dbUserLid},
            $json->{dbUserLidCredential},
            $json->{dbUserLidCredType},
            $privileges,
            $charset,
            $collate );

    my $file = $RESOURCES_DIR . '/' . $appConfigId . '_' . $installableId . '_' . $dbType . '_' . $itemName . '.json';
    UBOS::Utils::writeJsonToFile( $file, $json, 0600 );

    return(
            $json->{dbName},
            $json->{dbHost},
            $json->{dbPort},
            $json->{dbUserLid},
            $json->{dbUserLidCredential},
            $json->{dbUserLidCredType} );
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

    my $file = $RESOURCES_DIR . '/' . $appConfigId . '_' . $installableId . '_' . $dbType . '_' . $itemName . '.json';
    unless( -e $file  ) {
        return 0;
    }
    my $json = UBOS::Utils::readJsonFromFile( $file );

    my $dbName    = $json->{dbName};
    my $dbHost    = $json->{dbHost};
    my $dbPort    = $json->{dbPort};
    my $dbUserLid = $json->{dbUserLid};

    my $dbDriver = undef;
    if( $dbName ) {
        $dbDriver = UBOS::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
        if( $dbDriver ) {
            UBOS::Utils::deleteFile( $file );
            
        } else {
            error( 'Unknown database type', $dbType );
        }
    }
    
    if( $dbName && $dbDriver ) {
        return $dbDriver->unprovisionLocalDatabase( $dbName, $dbUserLid );
    }
    return 0;
}

##
# If a database name has been pinned, find it.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
# return: hash of dbName, dbHost, dbUser, dbPassword, or undef
sub findPinnedLocalDatabaseData {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    my $file = $PINNED_DIR . '/' . $appConfigId . '_' . $installableId . '_' . $dbType . '_' . $itemName . '.json';
    unless( -e $file  ) {
        return undef;
    }
    my $json = UBOS::Utils::readJsonFromFile( $file );
    return $json;
}

1;
