#!/usr/bin/perl
#
# Manages resources, such as databases and ports.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

# In the respective directory, resource files are named:
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

my $resourcesCache = undef; # Need to read all files, so we can find unused port
my $pinnedCache    = undef;

##
# Find an already-provisioned database of a certain type for a given id of an AppConfiguration,
# the id of an Installable at that AppConfiguration, and the symbolic database name per manifest.
# $dbType: database type
# $appConfigId: the id of the AppConfiguration for which this database has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this database has been provisioned
# $itemName: the symbolic database name per application manifest
# return: tuple of dbName, dbHost, dbPort, dbUser, dbPassword, dbCredentialType, or undef
sub findProvisionedDatabaseFor {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    trace( 'ResourceManager::findProvisionedDatabaseFor', $dbType, $appConfigId, $installableId, $itemName );

    _readCachesIfNeeded();

    my $key  = _constructKey( $dbType, $appConfigId, $installableId, $itemName );
    my $json = $resourcesCache->{$key};
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
# $jsonFragment: pointer to a JSON object that has parameters
# return: hash of dbName, dbHost, dbUser, dbPassword, or undef
sub provisionLocalDatabase {
    my $dbType        = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;
    my $jsonFragment  = shift;

    trace( 'ResourceManager::provisionLocalDatabase', $dbType, $appConfigId, $installableId, $itemName, $jsonFragment );

    my $dbDriver = UBOS::Host::obtainDbDriver( $dbType, 'localhost' );
    unless( $dbDriver ) {
        UBOS::Logging::error( 'Unknown database type', $dbType );
        return undef;
    }

    _readCachesIfNeeded();

    my $key  = _constructKey( $dbType, $appConfigId, $installableId, $itemName );
    my $json = $pinnedCache->{$key};

    unless( $json ) {
        $json = {};
    }
    $json->{key}         = $key;
    $json->{type}        = $dbType;
    $json->{appconfigid} = $appConfigId;
    $json->{installable} = $installableId;
    $json->{name}        = $itemName;

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
            $jsonFragment,
            "$appConfigId / $installableId / $itemName" );

    _updateResourcesCacheEntry( $key, $json );

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

    trace( 'ResourceManager::unprovisionLocalDatabase', $dbType, $appConfigId, $installableId, $itemName );

    _readCachesIfNeeded();

    my $key  = _constructKey( $dbType, $appConfigId, $installableId, $itemName );
    my $json = $resourcesCache->{$key};

    unless( $json ) {
        error( 'Cannot find', $key, 'in resourcesCache:', join( ", ", map { "$_ => " . $resourcesCache->{$_} } sort keys %$resourcesCache ));
        return 0;
    }

    my $dbName    = $json->{dbName};
    my $dbHost    = $json->{dbHost};
    my $dbPort    = $json->{dbPort};
    my $dbUserLid = $json->{dbUserLid};

    my $dbDriver = undef;
    if( $dbName ) {
        $dbDriver = UBOS::Host::obtainDbDriver( $dbType, $dbHost, $dbPort );
        unless( $dbDriver ) {
            error( 'Unknown database type', $dbType );
        }
    } else {
        error( 'dbName is empty:', join( ", ", map { "$_ => " . $json->{$_} } sort keys %$json ));
    }

    _deleteResourcesCacheEntry( $key );

    if( $dbName && $dbDriver ) {
        return $dbDriver->unprovisionLocalDatabase( $dbName, $dbUserLid );
    }

    return 0;
}

##
# Find an already-provisioned port of a certain type for a given id of an AppConfiguration,
# the id of an Installable at that AppConfiguration, and the symbolic port name per manifest.
# $portType: port type
# $appConfigId: the id of the AppConfiguration for which this port has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this port has been provisioned
# $name: the symbolic port name per application manifest
# return: port number or undef
sub findProvisionedPortFor {
    my $portType      = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    trace( 'ResourceManager::findProvisionedPortFor', $portType, $appConfigId, $installableId, $itemName );

    _readCachesIfNeeded();

    my $key  = _constructKey( $portType, $appConfigId, $installableId, $itemName );
    my $json = $resourcesCache->{$key};

    if( $json ) {
        return $json->{port};
    } else {
        return undef;
    }
}

##
# Provision a port.
# $portType: port type
# $appConfigId: the id of the AppConfiguration for which this port has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this port has been provisioned
# $itemName: the symbolic port name per application manifest
# return: port number, or undef
sub provisionPort {
    my $portType      = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    trace( 'ResourceManager::provisionPort', $portType, $appConfigId, $installableId, $itemName );

    _readCachesIfNeeded();

    my $key  = _constructKey( $portType, $appConfigId, $installableId, $itemName );
    my $json = $pinnedCache->{$key};

    unless( $json ) {
        $json = {};
    }
    $json->{key}         = $key;
    $json->{type}        = $portType;
    $json->{appconfigid} = $appConfigId;
    $json->{installable} = $installableId;
    $json->{name}        = $itemName;

    unless( exists( $json->{port} )) {
        $json->{port} = _findUnusedPort( $portType );
    }

    _updateResourcesCacheEntry( $key, $json );

    return $json->{port};
}

##
# Unprovision a port.
# $portType: port type
# $appConfigId: the id of the AppConfiguration for which this port has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this port has been provisioned
# $itemName: the symbolic port name per application manifest
# return: success or fail
sub unprovisionPort {
    my $portType      = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    trace( 'ResourceManager::unprovisionPort', $portType, $appConfigId, $installableId, $itemName );

    _readCachesIfNeeded();

    my $key  = _constructKey( $portType, $appConfigId, $installableId, $itemName );

    _deleteResourcesCacheEntry( $key );

    return 1;
}

##
# Construct the key for a particular configuration.
# $itemType: type of item
# $appConfigId: the id of the AppConfiguration for which this item has been provisioned
# $installableId: the id of the Installable at the AppConfiguration for which this item has been provisioned
# $itemName: the symbolic item name per application manifest
# return the key
sub _constructKey {
    my $itemType      = shift;
    my $appConfigId   = shift;
    my $installableId = shift;
    my $itemName      = shift;

    my $ret = $appConfigId . '_' . $installableId . '_' . $itemType . '_' . $itemName;
    # Note: for historical reasons, this is a different sequence than the sequence of arguments.

    return $ret;
}

##
# Helper method to populate the caches.
# return: 1 if the cache was actually read, 0 if the cache was in memory already
sub _readCachesIfNeeded {
    if( defined( $resourcesCache )) {
        return 0;
    }

    trace( 'ResourceManager::_readCachesIfNeeded' );

    my $resourcesDir = UBOS::Host::vars()->getResolve( 'host.resourcesdir' );
    my $pinnedDir    = UBOS::Host::vars()->getResolve( 'host.pinnedresourcesdir' );

    $resourcesCache = {};
    $pinnedCache    = {};

    if( -d $resourcesDir ) {
        if( opendir( DIR, $resourcesDir )) {
            while( my $entry = readdir DIR ) {
                if( $entry ne '.' && $entry ne '..' ) {
                    my $json = UBOS::Utils::readJsonFromFile( "$resourcesDir/$entry" );
                    if( $json ) {
                        my $entryBase = $entry;
                        $entryBase =~ s!\.json$!!;
                        $resourcesCache->{$entryBase} = $json;
                    }
                }
            }
            closedir DIR;
        } else {
            error( 'Cannot read directory:', $resourcesDir );
        }
    }

    if( -d $pinnedDir ) {
        if( opendir( DIR, $pinnedDir )) {
            while( my $entry = readdir DIR ) {
                if( $entry ne '.' && $entry ne '..' ) {
                    my $json = UBOS::Utils::readJsonFromFile( "$pinnedDir/$entry" );
                    if( $json ) {
                        my $entryBase = $entry;
                        $entryBase =~ s!\.json$!!;
                        $pinnedCache->{$entryBase} = $json;
                    }
                }
            }
            closedir DIR;
        } else {
            error( 'Cannot read directory:', $pinnedDir );
        }
    }

    return 1;
}

##
# Helper method to write the value of an entry in the resources cache
# to disk.
# $key: the key into the cache whose values has been updated
# $json: the new value
sub _updateResourcesCacheEntry {
    my $key  = shift;
    my $json = shift;

    trace( 'ResourceManager::_updateResourcesCacheEntry', $key );

    my $resourcesDir = UBOS::Host::vars()->getResolve( 'host.resourcesdir' );

    unless( -d $resourcesDir ) {
        UBOS::Utils::mkdirDashP( $resourcesDir, 0700, undef, undef, 0755 );
    }
    my $file = $resourcesDir . '/' . $key . '.json';
    UBOS::Utils::writeJsonToFile( $file, $json, 0600 );

    $resourcesCache->{$key} = $json;
}

##
# Helper method to delete an entry in the resources cache from disk.
# $key: the key into the cache whose values has been updated
sub _deleteResourcesCacheEntry {
    my $key = shift;

    trace( 'ResourceManager::_deleteResourcesCacheEntry', $key );

    my $resourcesDir = UBOS::Host::vars()->getResolve( 'host.resourcesdir' );

    my $file = $resourcesDir . '/' . $key . '.json';
    UBOS::Utils::deleteFile( $file );

    delete $resourcesCache->{$key};
}

##
# Find a port that is not used yet.
# $portType: 'tcp' or 'udp'
# return: port number
sub _findUnusedPort {
    my $portType = shift;

    trace( 'ResourceManager::_findUnusedPort', $portType );

    my $ret = 5001;

    while( 1 ) {
        my $conflict = 0;
        foreach my $json ( values %$resourcesCache ) {
            if( $portType eq $json->{type} ) {
                if( $ret == $json->{port} ) {
                    $conflict = 1;
                    last;
                }
            }
        }
        foreach my $json ( values %$pinnedCache ) {
            if( $portType eq $json->{type} ) {
                if( $ret == $json->{port} ) {
                    $conflict = 1;
                    last;
                }
            }
        }
        unless( $conflict ) {
            last; # found one
        }
        ++$ret;
    }
    return $ret;
}

1;
