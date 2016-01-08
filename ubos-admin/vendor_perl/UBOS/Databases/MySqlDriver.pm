#!/usr/bin/perl
#
# MySQL/MariaDB database driver.
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

package UBOS::Databases::MySqlDriver;

use DBI;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;
use fields qw( dbHost dbPort );

my $running = 0;

my $rootConfiguration = '/etc/mysql/root-defaults.cnf';

## Note that this driver has both 'static' and 'instance' methods

## ---- STATIC METHODS ---- ##

##
# Ensure that the mysql installation on this host is present and has a root password.
sub ensureRunning {
    if( $running ) {
        return 1;
    }

    UBOS::Host::ensurePackages( [ 'mariadb', 'perl-dbd-mysql' ] );

    my $out;
    my $err;
    UBOS::Utils::myexec( 'systemctl is-enabled ubos-mysqld > /dev/null || systemctl enable ubos-mysqld', undef, \$out, \$err );
    UBOS::Utils::myexec( 'systemctl is-active  ubos-mysqld > /dev/null || systemctl start  ubos-mysqld', undef, \$out, \$err );

    unless( -e $rootConfiguration ) {

        my $dbh = DBI->connect( "DBI:mysql:host=localhost", 'root', '' );

        if( defined( $dbh )) {
            # can connect to database without a password
            my $password = UBOS::Utils::randomPassword( 16 );

            my $cnf = <<END;
[client]
host     = localhost
user     = root
password = $password
socket   = /run/mysqld/mysqld.sock
END
            UBOS::Utils::saveFile( $rootConfiguration, $cnf, 0600 );

            my $sth = $dbh->prepare( <<SQL );
UPDATE mysql.user SET Password=PASSWORD( '$password' ) WHERE User='root';
SQL
            $sth->execute();

            $sth = $dbh->prepare( <<SQL );
FLUSH PRIVILEGES;
SQL
            $sth->execute();

            $dbh->disconnect();
        }
    }
    $running = 1;
}

##
# Wrapper around database connect, for debugging purposes
# $database: name of the database
# $user: database user to use
# $pass: database password to use
# $host: database host to connect to
# $port: database port to connect to
# return: database handle
sub dbConnect {
    my $database = shift;
    my $user     = shift;
    my $pass     = shift;
    my $host     = shift || 'localhost';
    my $port     = shift || 3306;

    ensureRunning();

    my $connectString = "database=$database;" if( $database );
    $connectString .= "host=$host;";
    $connectString .= "port=$port;";

    debug( 'MySqlDriver::dbConnect as user', $user, 'with', $connectString );

    my $dbh = DBI->connect( "DBI:mysql:${connectString}",
                            $user,
                            $pass,
                            { AutoCommit => 1, PrintError => 0 } );

    if( defined( $dbh )) {
        $dbh->{HandleError} = sub { error( 'Database error:', shift ); };
    } else {
        error( 'Connecting to database failed, using connection string', $connectString, 'user', $user );
    }
    return $dbh;
}

##
# Convenience method to connect to a database as root
# $database: name of the database
# return: database handle
sub dbConnectAsRoot {
    my $database = shift;

    ensureRunning();

    my( $rootUser, $rootPass ) = findRootUserPass();
    return dbConnect( $database, $rootUser, $rootPass );
}

##
# Wrapper around SQL prepare, for debugging purposes
# $dbh: database handle
# $sql: the SQL to prepare
# return: the prepared statement
sub sqlPrepare {
    my $dbh  = shift;
    my $sql  = shift;

    debug( sub {
        ( 'Preparing SQL:', ( length( $sql ) > 400 ? ( substr( $sql, 0, 400 ) . '...(truncated)' ) : $sql ))
    } );

    my $sth = $dbh->prepare( $sql );
    return $sth;
}

##
# Wrapper around SQL execute, for debugging purposes
# $sth: prepared statement
# @args: arguments for the prepared statement
# return: prepared statement
sub sqlExecute {
    my $sth  = shift;
    my @args = @_;

    debug( 'Executing SQL with arguments: ', @args );

    $sth->execute( @args );
    return $sth;
}

##
# Execute SQL with parameters in one statement
# $dbh: database handle
# $sql: the SQL to prepare
# @args: arguments for the prepared statement
# return: prepared statement
sub sqlPrepareExecute {
    my $dbh  = shift;
    my $sql  = shift;
    my @args = @_;

    my $sth = sqlPrepare( $dbh, $sql );
    sqlExecute( $sth, @args );
    return $sth;
}

##
# Find the root password for the database.
sub findRootUserPass {
    my $user;
    my $pass;
    my $host;

    unless( -e $rootConfiguration ) {
        fatal( 'Cannot access MySQL database. File missing:', $rootConfiguration );
    }
    unless( -r $rootConfiguration ) {
        fatal( 'Cannot read root credentials to access MySQL database in:', $rootConfiguration );
    }

    open CNF, '<', $rootConfiguration || return undef;
    foreach my $line ( <CNF> ) {
        if( $line =~ m/^\s*\[.*\]/ ) {
            if( $user && $pass && $host eq 'localhost' ) {
                last;
            }
            $user = undef;
            $pass = undef;
            $host = undef;

        } elsif( $line =~ m/\s*host\s*=\s*(\S+)/ ) {
            $host = $1;
        } elsif( $line =~ m/\s*user\s*=\s*(\S+)/ ) {
            $user = $1;
        } elsif( $line =~ m/\s*password\s*=\s*(\S+)/ ) {
            $pass = $1;
        }
    }
    close CNF;
    if( $user && $pass ) {
        return( $user, $pass );
    } else {
        fatal( 'Cannot find root credentials to access MySQL database in:', $rootConfiguration );
        return undef;
    }
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
    
    return 3306;
}

##
# Provision a local database
# $dbName: name of the database to provision
# $dbUserLid: identifier of the database user that is allowed to access it
# $dbUserLidCredential: credential for the database user
# $dbUserLidCredType: credential type
# $privileges: string containing required database privileges, like "create, insert"
# return: success or fail
sub provisionLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;
    my $dbUserLid           = shift;
    my $dbUserLidCredential = shift;
    my $dbUserLidCredType   = shift;
    my $privileges          = shift;

    debug( 'MySqlDriver::provisionLocalDatabase', $dbName, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType, $privileges );

    my $dbh = dbConnectAsRoot( undef );

    my $sth = sqlPrepareExecute( $dbh, <<SQL );
CREATE DATABASE `$dbName` CHARACTER SET = 'utf8';
SQL
    $sth->finish();

    $sth = sqlPrepareExecute( $dbh, <<SQL );
GRANT $privileges
   ON $dbName.*
   TO '$dbUserLid'\@'localhost'
   IDENTIFIED BY '$dbUserLidCredential';
SQL
    $sth->finish();

    $sth = sqlPrepareExecute( $dbh, <<SQL );
FLUSH PRIVILEGES;
SQL
    $sth->finish();
    $dbh->disconnect();

    return 1;
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

    debug( 'MySqlDriver::unprovisionLocalDatabase', $dbName, $dbUserLid );

    my $dbh = dbConnectAsRoot( undef );

    my $sth = sqlPrepareExecute( $dbh, <<SQL );
DROP DATABASE `$dbName`;
SQL
    $sth->finish();

    if( $dbUserLid ) {
        $sth = sqlPrepareExecute( $dbh, <<SQL );
DROP USER `$dbUserLid`;
SQL
        $sth->finish();
    }

    return 1;
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

    debug( 'MySqlDriver::exportLocalDatabase', $dbName );

    my( $rootUser, $rootPass ) = findRootUserPass();
    unless( $rootUser ) {
        error( 'Cannot find MySQL root user credentials' );
        return 0;
    }

    if( UBOS::Utils::myexec( "mysqldump -u $rootUser -p$rootPass $dbName > '$fileName'" )) {
        return 0;
    }
    return 1;
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
    
    debug( 'MySqlDriver::importLocalDatabase', $dbName, $fileName, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType );

    my( $rootUser, $rootPass ) = findRootUserPass();

    if( UBOS::Utils::myexec( "mysql -u $rootUser -p$rootPass $dbName < '$fileName'" )) {
        return 0;
    }
    return 1;
}

##
# Run bulk SQL against a database, as the provided user.
# $dbName: name of the database to run against
# $dbHost: host of the database to run against
# $dbPort: port of the database to run against
# $dbUserLid: database username to use
# $dbUserLidCredential: credential for the database user to use
# $dbUserLidCredTypeL: type of credential for the database user to use
# $sql: the SQL to run
# $delimiter: if given, the delimiter to use with the SQL
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
    my $delimiter           = shift;

    debug( sub {
        ( 'MySqlDriver::runBulkSql', $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType, 'SQL (' . length( $sql ) . ') bytes', $delimiter ) } );

    # from the command-line; that way we don't have to deal with messy statement splitting
    my $cmd = "mysql '--host=$dbHost' '--port=$dbPort'";
    $cmd .= " '--user=$dbUserLid' '--password=$dbUserLidCredential'";
    if( $delimiter ) {
        $cmd .= " '--delimiter=$delimiter'";
    }
    $cmd .= " '$dbName'";

    my $ret = 1;
    if( UBOS::Utils::myexec( $cmd, $sql )) {
        $ret = 0;
    }
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

    my( $rootUser, $rootPass ) = findRootUserPass();

    return $self->runBulkSql( $dbName, $dbHost, $dbPort, $rootUser, $rootPass, undef, $sql, $delimiter );
}

1;
