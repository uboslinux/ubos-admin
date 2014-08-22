#!/usr/bin/perl
#
# PostgreSql database driver.
#
# This file is part of ubos-admin.
# (C) 2012-2014 Indie Computing Corp.
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

use strict;
use warnings;

package UBOS::Databases::PostgreSqlDriver;

use File::Basename;
use UBOS::Logging;
use UBOS::Utils;
use fields qw( dbHost dbPort );

my $running = 0;
my $dataDir = '/var/lib/postgres/data';

## Note that this driver has both 'static' and 'instance' methods

## ---- STATIC METHODS ---- ##

##
# Ensure that postgresql is configured correctly and running
sub ensureRunning {
    if( $running ) {
        return 1;
    }

    debug( 'Installing postgresql' );
    
    if( UBOS::Host::installPackages( 'postgresql' )) {
        unless( -d $dataDir ) {
            # not initialized yet
            
            executeCmdAsAdmin( "initdb --locale en_US.UTF-8 -E UTF8 -D \"$dataDir\"" );

        }
        
        UBOS::Utils::myexec( 'systemctl enable postgresql' );
        UBOS::Utils::myexec( 'systemctl start  postgresql' );

        sleep( 3 ); # Needed, otherwise might not be able to connect
    }
     
    $running = 1;
    1;
}

##
# Execute a command as administrator
# $cmd: command, must not contain single quotes
# $stdin: content to pipe into stdin, if any
sub executeCmdAsAdmin {
    my $cmd   = shift;
    my $stdin = shift;
    
    ensureRunning();

    UBOS::Utils::myexec( "su - postgres -c '$cmd'", $stdin );
}

##
# Execute a command as administrator
# $cmd: command, must not contain single quotes
# $stdinFile: name of the file piped to stdin
# $stdoutFile: name of the file piped into from stdout
sub executeCmdPipeAsAdmin {
    my $cmd        = shift;
    my $stdinFile  = shift;
    my $stdoutFile = shift;
    
    ensureRunning();

    my $fullCommand = "su - postgres -c '$cmd'";
    if( $stdinFile ) {
        $fullCommand .= " < $stdinFile";
    }
    if( $stdoutFile ) {
        $fullCommand .= " > $stdoutFile";
    }
    UBOS::Utils::myexec( $fullCommand );
}


## ---- INSTANCE METHODS ---- ##

##
# Constructor
# $dbHost: the host to connect to
# $dbPort: the port to connect to
# return: instance of MySqlDriver
sub new {
    my $self   = shift;
    my $dbHost = shift;
    my $dbPort = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{dbHost} = $dbHost;
    $self->{dbPort} = $dbPort;

    return $self;
}

##
# Obtain the default port.
# return: default port
sub defaultPort {
    my $self = shift;
    
    return 5432;
}

##
# Provision a local database
# $dbName: name of the database to provision
# $dbUserLid: identifier of the database user that is allowed to access it
# $dbUserLidCredential: credential for the database user
# $dbUserLidCredType: credential type
# $privileges: string containing required database privileges, like "readWrite, dbAdmin"
sub provisionLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;
    my $dbUserLid           = shift;
    my $dbUserLidCredential = shift;
    my $dbUserLidCredType   = shift;
    my $privileges          = shift;

    executeCmdAsAdmin( "createdb -E UNICODE \"$dbName\"" );
    executeCmdAsAdmin( "createuser \"$dbUserLid\"" );
    executeCmdAsAdmin( "psql -v HISTFILE=/dev/null", "grant $privileges on database \"$dbName\" to \"$dbUserLid\"" );
}

##
# Unprovision a local database
# $dbName: name of the database to unprovision
sub unprovisionLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;

    executeCmdAsAdmin( "dropdb \"$dbName\"" );
}

##
# Export the data at a local database
# $dbName: name of the database to unprovision
# $fileName: name of the file to create with the exported data
sub exportLocalDatabase {
    my $self     = shift;
    my $dbName   = shift;
    my $fileName = shift;

    executeCmdPipeAsAdmin( "pg_dump \"$dbName\"", undef, $fileName );
}

##
# Import data into a local database, overwriting its previous content
# $dbName: name of the database to unprovision
# $fileName: name of the file to create with the exported data
sub importLocalDatabase {
    my $self     = shift;
    my $dbName   = shift;
    my $fileName = shift;

    executeCmdPipeAsAdmin( "psql -v HISTFILE=/dev/null \"$dbName\"", $fileName, undef );
}

1;
