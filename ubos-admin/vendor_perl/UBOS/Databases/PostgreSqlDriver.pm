#!/usr/bin/perl
#
# PostgreSql database driver.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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

    trace( 'PostgreSqlDriver::ensureRunning', $running );
    if( $running ) {
        return 1;
    }

    if( UBOS::Host::ensurePackages( 'postgresql' ) < 0 ) {
        warning( $@ );
    }

    my $dataDir = UBOS::Host::vars()->getResolve( 'postgresql.datadir' );
    unless( -d $dataDir ) {
        UBOS::Utils::mkdirDashP( $dataDir, 0700, 'postgres', 'postgres', 0755, 'root', 'root' );

    }
    UBOS::Utils::myexec( "chattr +C $dataDir" ); # nocow on btrfs

    $running = 1; # need to set this here, so executeCmdAsAdmin can be done

    if( UBOS::Utils::isDirEmpty( $dataDir )) {
        debugAndSuspend( 'Init postgres database' );

        my $initDbCmd = 'initdb';
        # let's not specify authentication here; instead, we overwrite the file
        $initDbCmd .= ' --encoding=UTF8';
        $initDbCmd .= ' --locale=en_US.UTF-8';
        $initDbCmd .= ' --pgdata="' . $dataDir . '"';
        executeCmdAsAdmin( $initDbCmd );

        # tighten down authentication
        UBOS::Utils::saveFile( "$dataDir/pg_hba.conf", <<CONTENT );
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Allow password-less login by the postgres user
local   all             postgres                                trust
host    all             postgres        127.0.0.1/32            trust
host    all             postgres        ::1/128                 trust

# All other users need passwords
local   all             all                                     scram-sha-256
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256

# local: Unix domain socket connections
# host:  IPv4 or IPv6 local connections
# No replication

CONTENT

        my $postgresConf = UBOS::Utils::slurpFile( "$dataDir/postgresql.conf" );
        $postgresConf =~ s!^\s*(#\s*)?password_encryption\s*=\s*(\S+)!password_encryption = scram-sha-256!m;
        UBOS::Utils::saveFile( "$dataDir/postgresql.conf", $postgresConf );

        my $out;
        my $err;

        debugAndSuspend( 'Check that postgresql.service is running' );
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
# $stdoutP: where to write output, if any
# return: success or fail
sub executeCmdAsAdmin {
    my $cmd     = shift;
    my $stdin   = shift;
    my $stdoutP = shift;

    ensureRunning();

    trace( 'PostgreSqlDriver::executeCmdAsAdmin', $cmd, $stdin );

    my $out;
    my $err;
    unless( $stdoutP ) {
        $stdoutP = \$out;
    }
    my $ret = 1;
    if( UBOS::Utils::myexec( "su - postgres -c '$cmd'", $stdin, $stdoutP, \$err )) {
        $ret = 0;
        $@   = $err;
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

    trace( 'PostgreSqlDriver::executeCmdPipeAsAdmin', $cmd, $stdinFile, $stdoutFile );

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

##
# Change ownership of all tables, sequences and views in a
# database to a new role. This is needed after restore from backup.
# $dbName: name of the database
# $role: name of the new owner
# return: true or false
sub changeSchemaOwnership {
    my $dbName = shift;
    my $role   = shift;

    # see https://stackoverflow.com/questions/1348126/modify-owner-on-all-tables-simultaneously-in-postgresql/13535184#13535184
    # but REASSIGN_OWNED does not work for owner postgres, and might (not tested) not work for
    # non-existing owners upon restore

    my %types = (
        'pg_tables'                    => 'tablename',
        'information_schema.sequences' => 'sequence_name',
        'information_schema.views'     => 'table_name'
    );

    my $errors = 0;
    foreach my $type ( sort keys %types ) {
        my $key = $types{$type};

        my $out;
        if( executeCmdAsAdmin( "psql -qAt -c \"select $key from $type where schemaname = \\\"public\\\";\" \"$dbName\"", undef, \$out )) {
            error( 'Failed to find', $type, 'in', $dbName );
            ++$errors;

        } else {
            $out =~ s!^\s+!!;
            $out =~ s!\s+$!!;

            my @tables = split( /\s+/, $out );
            foreach my $table ( @tables ) {
                if( executeCmdAsAdmin( "psql -c \"alter table \\\"$table\\\" owner to \\\"$role\\\"\" $dbName" )) {
                    error( 'Failed to change ownership of', $table, 'in', $dbName );
                    ++$errors;
                }
            }
        }
    }
    return $errors == 0;
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
# $description: description of the database
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
    my $description         = shift;

    trace( 'PostgreSqlDriver::provisionLocalDatabase', $dbName, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType, $privileges, $charset, $collate );

    my $ret = 1;

    # create database
    my $createDbSql = 'createdb';
    $createDbSql .= " --encoding=$charset";
    if( $collate ) {
        $createDbSql .= " --lc-collate=$collate";
    }
    $createDbSql .= " \"$dbName\"";
    $createDbSql .= " \"$description\"";

    unless( executeCmdAsAdmin( $createDbSql )) {
        error( 'Postgres createdb:', $@ );
        $ret = 0;
    }

    # create user
    unless( executeCmdAsAdmin( "createuser \"$dbUserLid\"" )) {
        error( 'Postgres createuser:', $@ );
        $ret = 0;
    }

    # set password for user
    unless( executeCmdAsAdmin( "psql -v HISTFILE=/dev/null '$dbName'", "ALTER ROLE \"$dbUserLid\" WITH PASSWORD '$dbUserLidCredential'" )) {
         # value needs ' not "
        error( 'Postgres alter role:', $@ );
        $ret = 0;
    }

    # The create table etc statements have not been executed at this point.
    # So we need to set default privileges so they apply to tables created
    # in the future.
    # based on this: http://stackoverflow.com/questions/22684255/grant-privileges-on-future-tables-in-postgresql
    unless( executeCmdAsAdmin( "psql -v HISTFILE=/dev/null '$dbName'", "ALTER DEFAULT PRIVILEGES IN SCHEMA \"public\" GRANT $privileges ON TABLES TO \"$dbUserLid\"" )) {
        error( 'Postgres alter default privileges (1):', $@ );
        $ret = 0;
    }
    unless( executeCmdAsAdmin( "psql -v HISTFILE=/dev/null '$dbName'", "ALTER DEFAULT PRIVILEGES IN SCHEMA \"public\" GRANT USAGE ON SEQUENCES TO \"$dbUserLid\"" )) {
        error( 'Postgres alter default privileges (2):', $@ );
        $ret = 0;
    }
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

    trace( 'PostgreSqlDriver::unprovisionLocalDatabase', $dbName, $dbUserLid );

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

    trace( 'PostgreSqlDriver::exportLocalDatabase', $dbName );

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

    trace( 'PostgreSqlDriver::importLocalDatabase', $dbName, $fileName, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType );

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

    trace( sub {
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

    trace( sub {
        ( 'PostgreSqlDriver::runBulkSqlAsAdmin', $dbName, $dbHost, $dbPort, 'SQL (' . length( $sql ) . ') bytes' ) } );

    # from the command-line; that way we don't have to deal with messy statement splitting
    my $cmd = "psql -v HISTFILE=/dev/null '--host=$dbHost' '--port=$dbPort'";
    $cmd .= " '$dbName'";

    my $ret = executeCmdAsAdmin( $cmd, $sql );
    return $ret;
}

1;
