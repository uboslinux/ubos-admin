#!/usr/bin/perl
#
# MySQL/MariaDB database driver.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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

my $rootConfiguration         = '/etc/mysql/root-defaults-ubos.cnf';
my $previousRootConfiguration = '/etc/mysql/root-defaults.cnf';

## Note that this driver has both 'static' and 'instance' methods

## ---- STATIC METHODS ---- ##

##
# Ensure that the mysql installation on this host is present and has a root password.
sub ensureRunning {

    trace( 'MySqlDriver::ensureRunning', $running );
    if( $running ) {
        return 1;
    }

    if( UBOS::Host::ensurePackages( [ 'mariadb', 'perl-dbd-mysql' ] ) < 0 ) {
        warning( $@ );
    }
    my $dataDir = UBOS::Host::vars()->getResolve( 'mysql.datadir' );
    unless( -d $dataDir ) {
        UBOS::Utils::mkdirDashP( $dataDir, 0700, 'mysql', 'mysql', 0755, 'root', 'root' );
    }
    UBOS::Utils::myexec( "chattr +C $dataDir" ); # nocow on btrfs

    my $out;
    my $err;
    debugAndSuspend( 'Check that mysqld.service is running' );
    UBOS::Utils::myexec( 'systemctl is-enabled mysqld > /dev/null || systemctl enable mysqld', undef, \$out, \$err );
    UBOS::Utils::myexec( 'systemctl is-active  mysqld > /dev/null || systemctl start  mysqld', undef, \$out, \$err );

    unless( -e $rootConfiguration ) {

        my $dbh = DBI->connect( "DBI:mysql:host=localhost", 'root', '' );

        if( defined( $dbh )) {
            # can connect to database without a password
            my $password = UBOS::Utils::randomPassword( 16 );

            debugAndSuspend( 'Save', $rootConfiguration );
            my $cnf = <<END;
[client]
host     = localhost
user     = root
password = $password
socket   = /run/mysqld/mysqld.sock
END
            UBOS::Utils::saveFile( $rootConfiguration, $cnf, 0600 );

            debugAndSuspend( 'Set root password' );
            my $sth = $dbh->prepare( <<SQL );
ALTER USER root\@localhost IDENTIFIED VIA mysql_native_password;
SQL
            $sth->execute();

            $sth = $dbh->prepare( <<SQL );
SET Password=PASSWORD( '$password' );
SQL
            $sth->execute();

            $sth = $dbh->prepare( <<SQL );
FLUSH PRIVILEGES;
SQL
            $sth->execute();

            $dbh->disconnect();

            if( -e $previousRootConfiguration ) {
                UBOS::Utils::deleteFile( $previousRootConfiguration );
            }
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

    trace( 'MySqlDriver::dbConnect as user', $user, 'with', $connectString );

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

    trace( sub {
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

    trace( 'MySqlDriver::sqlExecute ', @args );

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
    my $charset             = shift || 'utf8';
    my $collate             = shift;
    my $description         = shift; # ignored; MySQL does not know what to do with this

    trace( 'MySqlDriver::provisionLocalDatabase', $dbName, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType, $privileges, $charset, $collate );

    my $dbh = dbConnectAsRoot( undef );

    my $sth;

    if( $collate ) {
        $sth = sqlPrepareExecute( $dbh, <<SQL );
CREATE DATABASE `$dbName` CHARACTER SET = '$charset' COLLATE '$collate';
SQL
    } else {
        $sth = sqlPrepareExecute( $dbh, <<SQL );
CREATE DATABASE `$dbName` CHARACTER SET = '$charset';
SQL
    }
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

    trace( 'MySqlDriver::unprovisionLocalDatabase', $dbName, $dbUserLid );

    my $dbh = dbConnectAsRoot( undef );

    my $sth = sqlPrepareExecute( $dbh, <<SQL );
DROP DATABASE `$dbName`;
SQL
    $sth->finish();

    if( $dbUserLid ) {
        $sth = sqlPrepareExecute( $dbh, <<SQL );
DROP USER '$dbUserLid'\@'localhost';
SQL
        $sth->finish();
    }

    return 1;
}

##
# Export the data at a local database
# $dbName: name of the database to unprovision
# $compress: compression method to use, or undef
# return: name of the file that has the exported data, or undef if error
sub exportLocalDatabase {
    my $self     = shift;
    my $dbName   = shift;
    my $compress = shift;

    trace( 'MySqlDriver::exportLocalDatabase', $dbName, $compress );

    my( $rootUser, $rootPass ) = findRootUserPass();
    unless( $rootUser ) {
        error( 'Cannot find MySQL root user credentials' );
        return 0;
    }

    my $tmpDir = UBOS::Host::tmpdir();
    my $file;

    my $cmd = "mysqldump -u $rootUser -p$rootPass $dbName";
    if( $compress ) {
        if( $compress eq 'gz' ) {
            $file = File::Temp->new( UNLINK => 0, DIR => $tmpDir, SUFFIX => '.gz' );
            $cmd .= ' | gzip - ';
        } else {
            warning( 'Unknown compression method:', $compress );
            $file = File::Temp->new( UNLINK => 0, DIR => $tmpDir );
        }
    } else {
        $file = File::Temp->new( UNLINK => 0, DIR => $tmpDir );
    }
    my $fileName = $file->filename();

    $cmd .= " > '$fileName'";

    if( UBOS::Utils::myexec( $cmd )) {
        UBOS::Utils::deleteFile( $fileName );
        return undef;
    }
    return $fileName;
}

##
# Import data into a local database, overwriting its previous content
# $dbName: name of the database to unprovision
# $fileName: name of the file to read from
# $compress: compression method to use, or undef
# $dbUserLid: database username to use
# $dbUserLidCredential: credential for the database user to use
# $dbUserLidCredTypeL: type of credential for the database user to use
# return: success or fail
sub importLocalDatabase {
    my $self                = shift;
    my $dbName              = shift;
    my $fileName            = shift;
    my $compress            = shift;
    my $dbUserLid           = shift;
    my $dbUserLidCredential = shift;
    my $dbUserLidCredType   = shift;

    trace( 'MySqlDriver::importLocalDatabase', $dbName, $fileName, $compress, $dbUserLid, $dbUserLidCredential ? '<pass>' : '', $dbUserLidCredType );

    my( $rootUser, $rootPass ) = findRootUserPass();

    my $cmd;
    if( $compress ) {
        if( $compress eq 'gz' ) {
            $cmd = "zcat '$fileName' | mysql -u '$rootUser' '-p$rootPass' '$dbName'";
        } else {
            error( 'Unknown compression method:', $compress );
            return 0;
        }
    } else {
        $cmd = "mysql -u '$rootUser' '-p$rootPass' '$dbName' < '$fileName'";
    }
    if( UBOS::Utils::myexec( $cmd )) {
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

    trace( sub {
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
