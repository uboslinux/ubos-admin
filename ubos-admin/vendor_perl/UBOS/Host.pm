#!/usr/bin/perl
#
# Represents the local host.
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

package UBOS::Host;

use UBOS::Apache2;
use UBOS::Configuration;
use UBOS::Logging;
use UBOS::Roles::apache2;
use UBOS::Roles::mysql;
use UBOS::Roles::tomcat7;
use UBOS::Site;
use UBOS::Utils qw( readJsonFromFile myexec );
use Sys::Hostname;

my $SITES_DIR        = '/var/lib/ubos/sites';
my $HOST_CONF_FILE   = '/etc/ubos/config.json';
my $hostConf         = undef;
my $now              = time();
my $_rolesOnHostInSequence = undef; # allocated as needed
my $_rolesOnHost           = undef; # allocated as needed
my $_sites                 = undef; # allocated as needed

##
# Obtain the host Configuration object.
# return: Configuration object
sub config {
    unless( $hostConf ) {
        my $raw = readJsonFromFile( $HOST_CONF_FILE );

        $raw->{hostname}        = hostname;
        $raw->{now}->{unixtime} = $now;
        $raw->{now}->{tstamp}   = UBOS::Utils::time2string( $now );

        $hostConf = UBOS::Configuration->new( 'Host', $raw );
    }
}

##
# Determine all Sites currently installed on this host.
# return: hash of siteId to Site
sub sites {
    unless( $_sites ) {
        $_sites = {};

        if ( $< == 0 ) {
            # If we are root, we read the full files, otherwise the public files
            foreach my $f ( <"$SITES_DIR/*-full.json"> ) {
                my $siteJson = readJsonFromFile( $f );
                my $site     = UBOS::Site->new( $siteJson );
                $_sites->{$site->siteId()} = $site;
            }
        } else {
            foreach my $f ( <"$SITES_DIR/*-world.json"> ) {
                my $siteJson = readJsonFromFile( $f );
                my $site     = UBOS::Site->new( $siteJson );
                $_sites->{$site->siteId()} = $site;
            }
        }
    }
    return $_sites;
}

##
# Find a particular Site in the provided hash, or currently installed on this host.
# $siteId: the Site identifier
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site, or undef
sub findSiteById {
    my $siteId = shift;
    my $sites  = shift || sites();

    return $sites->{$siteId};
}

##
# Find a particular Site in the provided hash, or currently installed on this host,
# by a complete or partial siteid match.
# $id: the complete or partial Site identifier
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site, or undef
sub findSiteByPartialId {
	my $id    = shift;
    my $sites = shift || sites();

    my $ret;
    if( $id =~ m!^(.*)\.\.\.$! ) {
        my $partial    = $1;
        my @candidates = ();

        foreach my $siteId ( keys %$sites ) {
            my $site = $sites->{$siteId};

            if( $siteId =~ m!^$partial! ) {
                push @candidates, $site;
            }
        }
        if( @candidates == 1 ) {
            $ret = $candidates[0];

        } elsif( @candidates ) {
	        $@ = "There is more than one site whose siteid starts with $partial: "
               . join( " vs ", map { $_->siteId } @candidates )
               . '.';
            return undef;

        } else {
            $@ = "No site found whose siteid starts with $partial.";
            return undef;
        }
	
    } else {
        $ret = $sites->{$id};
        unless( $ret ) {
            $@ = "No site found with siteid $id.";
            return undef;
        }
    }
    return $ret;
}

##
# Find a particular Site in the provided hash, or currently installed on this host,
# by its hostname
# $host: hostname
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site
sub findSiteByHostname {
    my $host  = shift;
    my $sites = shift || sites();

    foreach my $siteId ( keys %$sites ) {
        my $site = $sites->{$siteId};

        if( $site->hostname eq $host ) {
            return $site;
        }
    }
    $@ = 'No Site found with hostname '. $host;
    return undef;
}

##
# Find a particular AppConfiguration in the provided hash of sites, or currently installed on this host,
# by ac omplete app config id match.
sub findAppConfigurationById {
    my $appConfigId = shift;
    my $sites       = shift || sites();

    foreach my $siteId ( keys %$sites ) {
        my $site       = $sites->{$siteId};
        my $appConfigs = $site->appConfigs;

        foreach my $appConfig ( @$appConfigs ) {
            if( $appConfig->appConfigId eq $appConfigId ) {
                return $appConfig;
            }
        }
    }
    return undef;
}

##
# Find a particular AppConfiguration in the provided hash of sites, or currently installed on this host,
# by a complete or partial app config id match.
# $id: the complete or partial app config identifier
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site, or undef
sub findAppConfigurationByPartialId {
	my $id    = shift;
    my $sites = shift || sites();

    my $ret;
    if( $id =~ m!^(.*)\.\.\.$! ) {
        my $partial    = $1;
        my @candidates = ();

        foreach my $siteId ( keys %$sites ) {
            my $site       = $sites->{$siteId};
            my $appConfigs = $site->appConfigs;

            foreach my $appConfig ( @$appConfigs ) {
                if( $appConfig->appConfigId =~ m!^$partial! ) {
                    push @candidates, [ $appConfig, $site ];
                }
            }
        }
        if( @candidates == 1 ) {
            $ret = $candidates[0][0];

        } elsif( @candidates ) {
	        $@ = "There is more than one AppConfiguration whose app config id starts with $partial: "
                 . join( " vs ", map { "$_[0] (site $_[1] )" } @candidates ) . '.';
            return undef;

        } else {
            $@ = "No AppConfiguration found whose app config id starts with $partial.";
            return undef;
        }
	
    } else {
        foreach my $siteId ( keys %$sites ) {
            my $site = $sites->{$siteId};

            $ret = $site->appConfig( $id );

            if( $ret ) {
                last;
            }
        }
        unless( $ret ) {
            $@ = "No AppConfiguration found with app config id $id.";
            return undef;
        }
    }
    return $ret;
}

##
# A site has been deployed.
# $site: the newly deployed or updated site
sub siteDeployed {
    my $site = shift;

    my $siteId         = $site->siteId;
    my $siteJson       = $site->siteJson;
    my $publicSiteJson = $site->publicSiteJson;

    debug( 'Host::siteDeployed', $siteId );

    UBOS::Utils::writeJsonToFile( "$SITES_DIR/$siteId-full.json",  $siteJson,       0600, 'root', 'root' );
    UBOS::Utils::writeJsonToFile( "$SITES_DIR/$siteId-world.json", $publicSiteJson, 0644, 'root', 'root' );

    $_sites = undef;
}

##
# A site has been undeployed.
# $site: the undeployed site
sub siteUndeployed {
    my $site = shift;

    my $siteId = $site->siteId;

    debug( 'Host::siteUndeployed', $siteId );

    UBOS::Utils::deleteFile( "$SITES_DIR/$siteId-world.json" );
    UBOS::Utils::deleteFile( "$SITES_DIR/$siteId-full.json" );

    $_sites = undef;
}

##
# Determine the roles that this host has chosen to use and support. For now, this is
# fixed.
# return: hash of role name to Role
sub rolesOnHost {
    unless( $_rolesOnHost ) {
        my @inSequence = rolesOnHostInSequence();
        $_rolesOnHost = {};
        foreach my $role ( @inSequence ) {
            $_rolesOnHost->{ $role->name } = $role;
        }
    }
    return $_rolesOnHost;
}

##
# Determine the roles that this host has chosen to use and support, in sequence
# of installation: databases before middleware before web server.
# return: the Roles, in sequence
sub rolesOnHostInSequence {
    unless( $_rolesOnHostInSequence ) {
        $_rolesOnHostInSequence = [
                UBOS::Roles::mysql->new,
                # UBOS::Roles::postgresql->new,
                # UBOS::Roles::mongo->new,
                UBOS::Roles::tomcat7->new,
                UBOS::Roles::apache2->new ];
    }
    return @$_rolesOnHostInSequence;
}

##
# Create a new siteid
# return: the siteid
sub createNewSiteId {
    return 's' . UBOS::Utils::randomHex( 40 );
}

##
# Create a new appconfigid
# return: the appconfigid
sub createNewAppConfigId {
    return 'a' . UBOS::Utils::randomHex( 40 );
}

##
# Determine whether this is a valid hostname
# $hostname: the hostname
# return: 1 or 0
sub isValidHostname {
    my $hostname = shift;

    if( ref( $hostname )) {
        error( 'Supposed hostname is not a string:', ref( $hostname ));
        return 0;
    }

    unless( $hostname =~ m!^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?)*\.?$|^\*$! ) {
        # regex originally from http://stackoverflow.com/a/1420225/200304
        return 0;
    }
    return 1;
}

##
# Determine whether this is a syntactically valid Site id
# $siteId: the Site id
# return: 1 or 0
sub isValidSiteId {
    my $siteId = shift;

    if( ref( $siteId )) {
        error( 'Supposed siteId is not a string:', ref( $siteId ));
        return 0;
    }
    if( $siteId =~ m/^s[0-9a-f]{40}$/ ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine whether this is a syntactically valid AppConfiguration id
# $appConfigId: the AppConfiguration id
# return: 1 or 0
sub isValidAppConfigId {
    my $appConfigId = shift;

    if( ref( $appConfigId )) {
        error( 'Supposed appConfigId is not a string:', ref( $appConfigId ));
        return 0;
    }
    if( $appConfigId =~ m/^a[0-9a-f]{40}$/ ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Execute the named triggers
# $triggers: array of trigger names
sub executeTriggers {
    my $triggers = shift;

    my @triggerList;
    if( ref( $triggers ) eq 'HASH' ) {
        @triggerList = keys %$triggers;
    } elsif( ref( $triggers ) eq 'ARRAY' ) {
        @triggerList = @$triggers;
    } else {
        fatal( 'Unexpected type:', $triggers );
    }

    debug( 'Host::executeTriggers:', @triggerList );

    foreach my $trigger ( @triggerList ) {
        if( 'httpd-reload' eq $trigger ) {
            UBOS::Apache2::reload();
        } elsif( 'httpd-restart' eq $trigger ) {
            UBOS::Apache2::restart();
        } elsif( 'tomcat7-reload' eq $trigger ) {
            UBOS::Tomcat7::reload();
        } elsif( 'tomcat7-restart' eq $trigger ) {
            UBOS::Tomcat7::restart();
        } else {
            warning( 'Unknown trigger:', $trigger );
        }
    }
}

##
# Update all the code currently installed on this host.
sub updateCode {

    my $cmd = 'pacman -Syu --noconfirm';
    unless( UBOS::Logging::isDebugActive() ) {
        $cmd .= ' > /dev/null';
    }
    myexec( $cmd );
}

##
# Clean package cache
sub purgeCache {

    my $cmd = 'pacman -Sc --noconfirm';
    unless( UBOS::Logging::isDebugActive() ) {
        $cmd .= ' > /dev/null';
    }
    myexec( $cmd );
}

##
# Make sure the named packages are installed
# $packages: List of packages
# return: number of actually installed packages
sub ensurePackages {
    my $packages = shift;

    my @packageList;
    if( ref( $packages ) eq 'HASH' ) {
        @packageList = keys %$packages;
    } elsif( ref( $packages ) eq 'ARRAY' ) {
        @packageList = @$packages;
    } elsif( ref( $packages )) {
        fatal( 'Unexpected type:', $packages );
    } else {
        @packageList = ( $packages );
    }

    # only install what isn't installed yet
    my @filteredPackageList = grep { myexec( "pacman -Q $_ > /dev/null 2>&1" ) } @packageList;

    if( @filteredPackageList ) {
        my $err;
        my $cmd = 'pacman -S --noconfirm ' . join( ' ', @filteredPackageList );
        unless( UBOS::Logging::isDebugActive() ) {
            $cmd .= ' > /dev/null';
        }

        if( myexec( $cmd, undef, undef, \$err )) {
            fatal( 'Failed to install package(s). Pacman says:', $err );
        }
    }
    return 0 + @filteredPackageList;
}

##
# Install the provided package files
# $packageFiles: List of package files
# return: number of installed packages
sub installPackageFiles {
    my $packageFiles = shift;

    my $err;
    my $cmd = 'pacman -U --noconfirm ' . join( ' ', @$packageFiles );
    unless( UBOS::Logging::isDebugActive() ) {
        $cmd .= ' > /dev/null';
    }

    if( myexec( $cmd, undef, undef, \$err )) {
        error( 'Failed to install package file(s). Pacman says:', $err );
        return 0;
    }
    return 0 + ( @$packageFiles );
}

##
# Determine the version of an installed package
# $packageName: name of the package
# return: version of the package, or undef
sub packageVersion {
    my $packageName = shift;

    my $cmd = "pacman -Q '$packageName'";
    my $out;
    my $err;
    if( myexec( $cmd, undef, \$out, \$err )) {
        return undef;
    }
    if( $out =~ m!$packageName\s+(\S+)! ) {
        return $1;
    } else {
        error( 'Cannot parse pacman -Q output:', $out );
        return undef;
    }
}

##
# Prevent interruptions of this script
sub preventInterruptions {
    $SIG{'HUP'}  = 'IGNORE';
    $SIG{'INT'}  = 'IGNORE';
    $SIG{'QUIT'} = 'IGNORE';
}

my $dbTypes           = {}; # cache
my $dbDriverInstances = {}; # cache: maps short-name to host:port to instance of driver

##
# Return which database types are available.
# return: hash of short-name to package name
sub _findDatabases {
    unless( %$dbTypes ) {
        my $full = UBOS::Utils::findPerlModuleNamesInPackage( 'UBOS::Databases' );
        foreach my $fileName ( keys %$full ) {
            my $packageName = $full->{$fileName};

            if( $packageName =~ m!::([A-Za-z0-9_]+)Driver$! ) {
                my $shortName = $1;
                $shortName =~ s!([A-Z])!lc($1)!ge;
                $dbTypes->{$shortName} = $packageName;
            }
        }
    }
    return $dbTypes;
}

##
# Return an instance of a database driver for the given short-name
# $shortName: short name of the database type, e.g. 'mysql'
# $dbHost: host on which the database runs
# $dbPort: port on which the database can be reached on that port
# return: database driver, e.g. an instance of UBOS::Databases::MySqlDriver
sub obtainDbDriver {
    my $shortName = shift;
    my $dbHost    = shift;
    my $dbPort    = shift || 'default';
    
    my $ret = $dbDriverInstances->{$shortName}->{"$dbHost:$dbPort"};
    unless( $ret ) {
        my $dbs = _findDatabases();
        my $db  = $dbs->{$shortName};
        if( $db ) {
            $ret = UBOS::Utils::invokeMethod( $db . '::new', $db, $dbHost, $dbPort );
            
            if( $dbPort eq 'default' ) {
                $dbDriverInstances->{$shortName}->{"$dbHost:default"} = $ret;
                $dbPort = $ret->defaultPort();
            }
            $dbDriverInstances->{$shortName}->{"$dbHost:$dbPort"} = $ret;
        }
    }
    return $ret;
}

##
# Ensure that pacman has been initialized. This may generate a key pair, which
# means it cannot be pre-installed; it also may take some time, depending on
# how much entropy is available.
sub ensurePacmanInit {
    # If the time is completely off, chances are we are on a Raspberry Pi or
    # such that hasn't connected to the network. In which case we set the system
    # time to the time of the last build
    if( time() < 100000000 ) { # in 1973
        my $osRelease = UBOS::Utils::slurpFile( '/etc/os-release' );
        if( $osRelease =~ m!^BUILD_ID="?(\d\d\d\d)(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)"?$!m ) {
            my( $year, $month, $day, $hour, $min, $sec ) = ( $1, $2, $3, $4, $5, $6 );

            my $ds = sprintf( '%.2d%.2d%.2d%.2d%.4d.%.2d', $month, $day, $hour, $min, $year, $sec );

            UBOS::Utils::myexec( "date $ds" );
        }
    }
    
    UBOS::Utils::myexec( "pacman-key --init" );

    # We trust the Arch people, and ourselves
    my $err;
    UBOS::Utils::myexec( "pacman -Q archlinux-keyring    > /dev/null 2>&1 && pacman-key --populate archlinux",    undef, undef, \$err );
    UBOS::Utils::myexec( "pacman -Q archlinuxarm-keyring > /dev/null 2>&1 && pacman-key --populate archlinuxarm", undef, undef, \$err );
    UBOS::Utils::myexec( "pacman-key --populate ubos" );
}

1;
