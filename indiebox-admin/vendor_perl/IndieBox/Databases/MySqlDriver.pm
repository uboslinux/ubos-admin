#!/usr/bin/perl
#
# MySQL/MariaDB database driver.
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

use strict;
use warnings;

package IndieBox::Databases::MySqlDriver;

use DBI;
use IndieBox::Logging;
use IndieBox::Utils;
use fields qw( dbHost dbPort );

my $rootConfiguration = '/etc/mysql/root-defaults.cnf';

## Note that this driver has both 'static' and 'instance' methods

## ---- STATIC METHODS ---- ##

##
# Ensure that the mysql installation on this host has a root password.
sub ensureRootPassword {
    unless( -r $rootConfiguration ) {
        my $dbh = DBI->connect( "DBI:mysql:host=localhost", 'root', '' );

        if( defined( $dbh )) {
            # can connect to database without a password
            my $password = IndieBox::Utils::randomPassword( 16 );

            my $cnf = <<END;
[client]
host     = localhost
user     = root
password = $password
socket   = /run/mysqld/mysqld.sock
END
            IndieBox::Utils::saveFile( $rootConfiguration, $cnf, 0600 );

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

    my $connectString = "database=$database;" if( $database );
    $connectString .= "host=$host;";
    $connectString .= "port=$port;";

    trace( 'MySqlDriver::dbConnect as user', $user, 'with', $connectString );

    my $dbh = DBI->connect( "DBI:mysql:${connectString}",
                            $user,
                            $pass,
                            { AutoCommit => 1, PrintError => 0 } );

    if( defined( $dbh )) {
        $dbh->{HandleError} = sub { error( 'Database error:', shift ); };
    } else {
        debug( 'Connecting to database failed, using connection string', $connectString, 'user', $user );
    }
    return $dbh;
}

##
# Convenience method to connect to a database as root
# $database: name of the database
# return: database handle
sub dbConnectAsRoot {
    my $database = shift;

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

    trace( 'Preparing SQL:', ( length( $sql ) > 400 ? ( substr( $sql, 0, 400 ) . '...(truncated)' ) : $sql ));

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

    if( @args ) {
        trace( 'Executing SQL with arguments', join( ', ', @args ));
    } else {
        trace( 'Executing SQL without arguments' );
    }
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
        error( 'Cannot find root credentials to access MySQL database. Perhaps you need to run as root?' );
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
sub provisionLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;
    my $dbUserLid           = shift;
    my $dbUserLidCredential = shift;
    my $dbUserLidCredType   = shift;
    my $privileges          = shift;

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
}

##
# Unprovision a local database
# $dbName: name of the database to unprovision
sub unprovisionLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;

    my $dbh = dbConnectAsRoot( undef );

    my $sth = sqlPrepareExecute( $dbh, <<SQL );
DROP DATABASE `$dbName`;
SQL
    $sth->finish();
}

##
# Export the data at a local database
# $dbName: name of the database to unprovision
# $fileName: name of the file to create with the exported data
sub exportLocalDatabase {
    my $self     = shift;
    my $dbName   = shift;
    my $fileName = shift;

    my( $rootUser, $rootPass ) = findRootUserPass();
    unless( $rootUser ) {
        error( 'Cannot find MySQL root user credentials' );
        return 0;
    }

    IndieBox::Utils::myexec( "mysqldump -u $rootUser -p$rootPass $dbName > '$fileName'" );
}

##
# Import data into a local database, overwriting its previous content
# $dbName: name of the database to unprovision
# $fileName: name of the file to create with the exported data
sub importLocalDatabase {
    my $self     = shift;
    my $dbName   = shift;
    my $fileName = shift;
    
    my( $rootUser, $rootPass ) = findRootUserPass();

    IndieBox::Utils::myexec( "mysql -u $rootUser -p$rootPass $dbName < '$fileName'" );
}

1;
