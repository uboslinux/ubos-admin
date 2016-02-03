#!/usr/bin/perl
#
# PostgreSql database driver.
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

use strict;
use warnings;

package UBOS::Databases::PostgreSqlDriver;

use File::Basename;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;
use fields qw( dbHost dbPort );

my $running = 0;

## Note that this driver has both 'static' and 'instance' methods

## ---- STATIC METHODS ---- ##

##
# Ensure that postgresql is configured correctly and running
sub ensureRunning {
    if( $running ) {
        return 1;
    }

    debug( 'Installing postgresql' );
    
    UBOS::Host::ensurePackages( 'postgresql' );
    
    my $dataDir = '/var/lib/postgres/data';

    unless( -d $dataDir ) {
        # somehow that directory has disappeared; package postgresql puts it there
        UBOS::Utils::mkdirDashP( $dataDir, '0700', 'postgres', 'postgres' );
    }
    $running = 1; # need to set this here, so executeCmdAsAdmin can be done

    if( UBOS::Utils::isDirEmpty( $dataDir )) {
        executeCmdAsAdmin( "initdb --locale en_US.UTF-8 -E UTF8 -D \"$dataDir\"" );

        my $out;
        my $err;

        UBOS::Utils::myexec( 'systemctl is-enabled postgresql > /dev/null || systemctl enable postgresql', undef, \$out, \$err );
        UBOS::Utils::myexec( 'systemctl is-active  postgresql > /dev/null || systemctl start  postgresql', undef, \$out, \$err );

        sleep( 3 ); # Needed, otherwise might not be able to connect
    }

    1;
}

##
# Execute a command as administrator
# $cmd: command, must not contain single quotes
# $stdin: content to pipe into stdin, if any
# return: success or fail
sub executeCmdAsAdmin {
    my $cmd   = shift;
    my $stdin = shift;
    
    ensureRunning();

    debug( 'PostgreSqlDriver::executeCmdAsAdmin', $cmd, $stdin );

    my $out;
    my $err;
    my $ret = 1;
    if( UBOS::Utils::myexec( "su - postgres -c '$cmd'", $stdin, \$out, \$err )) {
        $ret = 0;
    }
    return $ret;
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

    debug( 'PostgreSqlDriver::executeCmdPipeAsAdmin', $cmd, $stdinFile, $stdoutFile );

    my $fullCommand = "su - postgres -c '$cmd'";
    if( $stdinFile ) {
        $fullCommand .= " < $stdinFile";
    }
    if( $stdoutFile ) {
        $fullCommand .= " > $stdoutFile";
    } else {
        $fullCommand .= ' > /dev/null';
    }
    my $ret = 1;
    if( UBOS::Utils::myexec( $fullCommand )) {
        $ret = 0;
    }
    return $ret;
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
# $charset: default database character set name
# $collate: default database collation name
# return: success or fail
sub provisionLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;
    my $dbUserLid           = shift;
    my $dbUserLidCredential = shift;
    my $dbUserLidCredType   = shift;
    my $privileges          = shift;
    my $charset             = shift || 'UNICODE';
    my $collate             = shift;

    debug( 'PostgreSqlDriver::provisionLocalDatabase', $dbName, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType, $privileges, $charset, $collate );

    my $ret = 1;
    if( $collate ) {
        $ret &= executeCmdAsAdmin( "createdb -E $charset --lc-collate=$collate \"$dbName\"" );
    } else {
        $ret &= executeCmdAsAdmin( "createdb -E $charset \"$dbName\"" );
    }
    $ret &= executeCmdAsAdmin( "createuser \"$dbUserLid\"" );

    # based on this: http://stackoverflow.com/questions/22684255/grant-privileges-on-future-tables-in-postgresql
    $ret &= executeCmdAsAdmin( "psql -v HISTFILE=/dev/null '$dbName'", "ALTER DEFAULT PRIVILEGES IN SCHEMA \"public\" GRANT $privileges ON TABLES TO \"$dbUserLid\"" );
    $ret &= executeCmdAsAdmin( "psql -v HISTFILE=/dev/null '$dbName'", "ALTER DEFAULT PRIVILEGES IN SCHEMA \"public\" GRANT USAGE ON SEQUENCES TO \"$dbUserLid\"" );

    return $ret;
}

##
# Unprovision a local database
# $dbName: name of the database to unprovision
# $dbUserLid: identifier of the database user that is also being unprovisioned
# return: success or fail
sub unprovisionLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;
    my $dbUserLid           = shift;

    debug( 'PostgreSqlDriver::unprovisionLocalDatabase', $dbName, $dbUserLid );

    my $ret = executeCmdAsAdmin( "dropdb \"$dbName\"" );

    if( $dbUserLid ) {
        $ret &= executeCmdAsAdmin( "dropuser \"$dbUserLid\"" );
    }

    return $ret;
}

##
# Export the data at a local database
# $dbName: name of the database to unprovision
# $fileName: name of the file to create with the exported data
# return: success or fail
sub exportLocalDatabase {
    my $self     = shift;
    my $dbName   = shift;
    my $fileName = shift;

    debug( 'PostgreSqlDriver::exportLocalDatabase', $dbName );

    # --clean will drop the schema, which means we lose GRANTs on it
    my $ret = executeCmdPipeAsAdmin( "pg_dump --no-owner --no-privileges --disable-triggers \"$dbName\"", undef, $fileName );

    return $ret;
}

##
# Import data into a local database, overwriting its previous content
# $dbName: name of the database to unprovision
# $fileName: name of the file to create with the exported data
# $dbUserLid: database username to use
# $dbUserLidCredential: credential for the database user to use
# $dbUserLidCredTypeL: type of credential for the database user to use
# return: success or fail
sub importLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;
    my $fileName            = shift;
    my $dbUserLid           = shift;
    my $dbUserLidCredential = shift;
    my $dbUserLidCredType   = shift;

    debug( 'PostgreSqlDriver::importLocalDatabase', $dbName, $fileName, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType );

    my $ret = executeCmdPipeAsAdmin( "psql -v HISTFILE=/dev/null \"$dbName\"", $fileName, undef );

    return $ret;
}

##
# Run bulk SQL against a database.
# $dbName: name of the database to run against
# $dbHost: host of the database to run against
# $dbPort: port of the database to run against
# $dbUserLid: database username to use
# $dbUserLidCredential: credential for the database user to use
# $dbUserLidCredTypeL: type of credential for the database user to use
# $sql: the SQL to run
# no delimiter in Postgres, as far as I can tell
# return: success or fail
sub runBulkSql {
    my $self                = shift;
    my $dbName              = shift;
    my $dbHost              = shift;
    my $dbPort              = shift;
    my $dbUserLid           = shift;
    my $dbUserLidCredential = shift;
    my $dbUserLidCredType   = shift;
    my $sql                 = shift;

    debug( sub {
        ( 'PostgreSqlDriver::runBulkSql', $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType, 'SQL (' . length( $sql ) . ') bytes' ) } );

    # from the command-line; that way we don't have to deal with messy statement splitting
    my $cmd = "psql -v HISTFILE=/dev/null '--host=$dbHost' '--port=$dbPort'";
    $cmd .= " '--username=$dbUserLid' '--password=$dbUserLidCredential'";
    $cmd .= " '$dbName'";

    my $ret = executeCmdAsAdmin( $cmd, $sql );
    return $ret;
}

##
# Run bulk SQL against a database, as the administrator.
# $dbName: name of the database to run against
# $dbHost: host of the database to run against
# $dbPort: port of the database to run against
# $sql: the SQL to run
# $delimiter: if given, the delimiter to use with the SQL
# return: success or fail
sub runBulkSqlAsAdmin {
    my $self                = shift;
    my $dbName              = shift;
    my $dbHost              = shift;
    my $dbPort              = shift;
    my $sql                 = shift;
    my $delimiter           = shift;

    debug( sub {
        ( 'PostgreSqlDriver::runBulkSqlAsAdmin', $dbName, $dbHost, $dbPort, 'SQL (' . length( $sql ) . ') bytes' ) } );

    # from the command-line; that way we don't have to deal with messy statement splitting
    my $cmd = "psql -v HISTFILE=/dev/null '--host=$dbHost' '--port=$dbPort'";
    $cmd .= " '$dbName'";

    my $ret = executeCmdAsAdmin( $cmd, $sql );
    return $ret;
}

1;
