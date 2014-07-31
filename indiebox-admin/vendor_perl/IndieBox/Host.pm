#!/usr/bin/perl
#
# Represents the local host.
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

package IndieBox::Host;

use IndieBox::Apache2;
use IndieBox::Configuration;
use IndieBox::Logging;
use IndieBox::Roles::apache2;
use IndieBox::Roles::mysql;
use IndieBox::Roles::tomcat7;
use IndieBox::Site;
use IndieBox::Utils qw( readJsonFromFile myexec );
use Sys::Hostname;

my $SITES_DIR        = '/var/lib/indiebox/sites';
my $HOST_CONF_FILE   = '/etc/indiebox/config.json';
my $hostConf         = undef;
my $now              = time();
my @_rolesOnHostInSequence = (); # allocated as needed
my %_rolesOnHost           = (); # allocated as needed

my @essentialServices = qw( cronie ntpd );

##
# Ensure that pacman is configured correctly.
sub ensurePacmanConfig {
    trace( 'Host::ensurePacmanConfig' );

    # packages that must not be automatically upgraded
    # per https://wiki.archlinux.org/index.php/PostgreSQL
    my %ignorePkg = ( 'postgresql' => 1, 'postgresql-libs' => 1 );
    
    my $confFile    = '/etc/pacman.conf';
    my $confContent = IndieBox::Utils::slurpFile( $confFile );

    if( $confContent =~ m!^(\s*IgnorePkg\s*=(.*))$!gm ) {
        # We have a line that's not commented out
        my $lineAlready      = $1;
        my $ignorePkgAlready = $2;
        my $to               = pos( $confContent ); # http://www.perlmonks.org/?node_id=642690
        my $from             = $to - length( $lineAlready );

        $ignorePkgAlready =~ s!^\s+!!;
        $ignorePkgAlready =~ s!\s+$!!;
        foreach my $found ( split /\s+/, $ignorePkgAlready ) {
            $ignorePkg{$found} += 1;
        }
        my $confLine = 'IgnorePkg = ' . join( ' ', sort keys %ignorePkg );

        $confContent = substr( $confContent, 0, $from ) . $confLine . substr( $confContent, $to );

    } elsif( $confContent =~ m!^(\s*#\s*IgnorePkg.*)$!gm ) {
        # We only have a line that's commented out
        my $lineAlready = $1;
        my $to          = pos( $confContent ); # http://www.perlmonks.org/?node_id=642690
        my $from        = $to - length( $lineAlready );
        
        my $confLine = 'IgnorePkg = ' . join( ' ', sort keys %ignorePkg );

        $confContent = substr( $confContent, 0, $from ) . $confLine . substr( $confContent, $to );

    } elsif( $confContent =~ m!^\[options\].*$!gm ) {
        # No line, but found the options section
        my $lineAlready = $1;
        my $to          = pos( $confContent ); # http://www.perlmonks.org/?node_id=642690
        
        my $confLine = 'IgnorePkg = ' . join( ' ', sort keys %ignorePkg );

        $confContent = substr( $confContent, 0, $to ) . "\n" . $confLine . substr( $confContent, $to );
        
    } else {
        # Did not even find the options section

        IndieBox::Logging::fatal( 'Cannot find [options] section in', $confFile );
    }
    
    IndieBox::Utils::saveFile( $confFile, $confContent, 0644 );
    
    1;
}

##
# Ensure that all essential services run on this Host.
sub ensureEssentialServicesRunning {
    trace( 'Host::ensureEssentialServicesRunning' );

    if( @essentialServices ) {
        IndieBox::Utils::myexec( 'systemctl enable'  . join( '', map { " '$_'" } @essentialServices ) );
        IndieBox::Utils::myexec( 'systemctl restart' . join( '', map { " '$_'" } @essentialServices ) . ' &' );
                # may be executed during systemd init, so background execution
    }
    1;
}

##
# Obtain the host Configuration object.
# return: Configuration object
sub config {
    unless( $hostConf ) {
        my $raw = readJsonFromFile( $HOST_CONF_FILE );

        $raw->{hostname}        = hostname;
        $raw->{now}->{unixtime} = $now;
        $raw->{now}->{tstamp}   = IndieBox::Utils::time2string( $now );

        $hostConf = new IndieBox::Configuration( 'Host', $raw );
    }
}

##
# Determine all Sites currently installed on this host.
# return: hash of siteId to Site
sub sites {
    my %ret = ();
    foreach my $f ( <"$SITES_DIR/*.json"> ) {
        my $siteJson = readJsonFromFile( $f );
        my $site     = new IndieBox::Site( $siteJson );
        $ret{$site->siteId()} = $site;
    }
    return \%ret;
}

##
# Find a particular Site currently installed on this host.
# $siteId: the Site identifier
# return: the Site
sub findSiteById {
    my $siteId = shift;

    my $jsonFile = "$SITES_DIR/$siteId.json";
    if( -r $jsonFile ) {
        my $siteJson = readJsonFromFile( $jsonFile );
        my $site     = new IndieBox::Site( $siteJson );

        return $site;
    }
    return undef;
}

##
# Find a particular Site currently installed on this host by a partial identifier.
# $partial: the partial Site identifier
# return: the Site
sub findSiteByPartialId {
	my $partial = shift;
	
    my @candidates = <"$SITES_DIR/$partial*.json">;
    if( @candidates == 1 ) {
        my $siteJson = readJsonFromFile( $candidates[0] );
        my $site     = new IndieBox::Site( $siteJson );

        return $site;

    } elsif( @candidates == 0 ) {
		error( "No site found with partial siteid", $partial );
		return undef;

	} else {
		error( "Partial siteid", $partial, "ambiguous:", join( " vs ", map { m!/(s[0-9a-fA-F]{40})\.json! } @candidates ));
		return undef;
	}
}

##
# A site has been deployed.
# $site: the newly deployed or updated site
sub siteDeployed {
    my $site = shift;

    my $siteId   = $site->siteId;
    my $siteJson = $site->siteJson;

    trace( 'Host::siteDeployed', $siteId );

    IndieBox::Utils::writeJsonToFile( "$SITES_DIR/$siteId.json", $siteJson );
}

##
# A site has been undeployed.
# $site: the undeployed site
sub siteUndeployed {
    my $site = shift;

    my $siteId   = $site->siteId;

    trace( 'Host::siteUndeployed', $siteId );

    IndieBox::Utils::deleteFile( "$SITES_DIR/$siteId.json" );
}

##
# Determine the roles that this host has chosen to use and support. For now, this is
# fixed.
# return: hash of role name to Role
sub rolesOnHost {
    unless( %_rolesOnHost ) {
        my @inSequence = rolesOnHostInSequence();
        foreach my $role ( @inSequence ) {
            $_rolesOnHost{ $role->name } = $role;
        }
    }
    return \%_rolesOnHost;
}

##
# Determine the roles that this host has chosen to use and support, in sequence
# of installation: databases before middleware before web server.
# return: the Roles, in sequence

sub rolesOnHostInSequence {
    unless( @_rolesOnHostInSequence ) {
        @_rolesOnHostInSequence = (
                new IndieBox::Roles::mysql,
                # new IndieBox::Roles::postgresql,
                # new IndieBox::Roles::mongo,
                new IndieBox::Roles::tomcat7,
                new IndieBox::Roles::apache2 );
    }
    return @_rolesOnHostInSequence;
}

##
# Execute the named triggers
# $triggers: array of trigger names
sub executeTriggers {
    my $triggers = shift;

    trace( 'Host::executeTriggers' );

    my @triggerList;
    if( ref( $triggers ) eq 'HASH' ) {
        @triggerList = keys %$triggers;
    } elsif( ref( $triggers ) eq 'ARRAY' ) {
        @triggerList = @$triggers;
    } else {
        fatal( 'Unexpected type:', $triggers );
    }
    foreach my $trigger ( @triggerList ) {
        if( 'httpd-reload' eq $trigger ) {
            IndieBox::Apache2::reload();
        } elsif( 'httpd-restart' eq $trigger ) {
            IndieBox::Apache2::restart();
        } elsif( 'tomcat7-reload' eq $trigger ) {
            IndieBox::Tomcat7::reload();
        } elsif( 'tomcat7-restart' eq $trigger ) {
            IndieBox::Tomcat7::restart();
        } else {
            IndieBox::Logging::warn( 'Unknown trigger:', $trigger );
        }
    }
}

##
# Update all the code currently installed on this host.
sub updateCode {
    my $quiet = shift;

    trace( 'Host::updateCode' );

    my $cmd = 'pacman -Syu --noconfirm';
    if( $quiet ) {
        $cmd .= ' > /dev/null';
    }
    myexec( $cmd );
}

##
# Clean package cache
sub purgeCache {
    my $quiet = shift;

    trace( 'Host::purgeCache' );

    my $cmd = 'pacman -Sc --noconfirm';
    if( $quiet ) {
        $cmd .= ' > /dev/null';
    }
    myexec( $cmd );
}

##
# Install the named packages.
# $packages: List of packages
# return: number of actually installed packages
sub installPackages {
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

    trace( 'Host::installPackages', @filteredPackageList );

    if( @filteredPackageList ) {
        my $err;
        if( myexec( 'sudo pacman -S --noconfirm ' . join( ' ', @filteredPackageList ), undef, undef, \$err )) {
            fatal( 'Failed to install package(s). Pacman says:', $err );
        }
    }
    return 0 + @filteredPackageList;
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
        my $full = IndieBox::Utils::findPerlModuleNamesInPackage( 'IndieBox::Databases' );
        while( my( $fileName, $packageName ) = each %$full ) {
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
# return: database driver, e.g. an instance of IndieBox::Databases::MySqlDriver
sub obtainDbDriver {
    my $shortName = shift;
    my $dbHost    = shift;
    my $dbPort    = shift || 'default';
    
    my $ret = $dbDriverInstances->{$shortName}->{"$dbHost:$dbPort"};
    unless( $ret ) {
        my $dbs = _findDatabases();
        my $db  = $dbs->{$shortName};
        if( $db ) {
            $ret = IndieBox::Utils::invokeMethod( $db . '::new', $db, $dbHost, $dbPort );
            
            if( $dbPort eq 'default' ) {
                $dbDriverInstances->{$shortName}->{"$dbHost:default"} = $ret;
                $dbPort = $ret->defaultPort();
            }
            $dbDriverInstances->{$shortName}->{"$dbHost:$dbPort"} = $ret;
        }
    }
    return $ret;
}

1;
