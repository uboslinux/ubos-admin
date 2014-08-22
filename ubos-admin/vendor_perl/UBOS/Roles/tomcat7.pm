#!/usr/bin/perl
#
# tomcat7 role. The interface to Tomcat7 is in Tomcat7.pm
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

package UBOS::Roles::tomcat7;

use base qw( UBOS::Role );
use fields;

use UBOS::Logging;
use UBOS::Tomcat7;
use UBOS::Utils;

my $sitesDir     = '/var/lib/tomcat7/sites';
my $sitesAppsDir = '/etc/tomcat7/ubos/sites-apps';
my $contextDir   = '/etc/tomcat7/Catalina';

# $sitesDir: contains one directory per site with name $siteId, each of which contains
#   one directory per AppConfiguration at this site, with name $appConfigId, which is that
#   AppConfig's "home dir"
# $sitesAppsDir: contains one directory per site with name $siteId. This is the 'webapps' directory
#   for that virtual host
# $contextDir: contains one directory per site with name $hostname. This is where we drop the
#   the context.xml files for all the AppConfigurations at this virtual host
##
# Constructor
sub new {
    my $self = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new();
    return $self;
}

##
# Name of this role
# return: name
sub name {
    my $self = shift;

    return 'tomcat7';
}

##
# Make sure the Site/virtual host is set up, or set it up
# $site: the Site to check or set up
# $doIt: if 1, setup; if 0, only check
# $triggers: triggers to be executed may be added to this hash
sub setupSiteOrCheck {
    my $self     = shift;
    my $site     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    my $siteDocumentDir = $site->config->getResolve( 'site.tomcat7.sitedocumentdir' );

    if( $doIt ) {
        UBOS::Utils::mkdir( $siteDocumentDir, 0755 );
        $self->setupSite( $site, $triggers );
    }
}

##
# Do what is necessary to set up a Site.
# $site: the Site
# $triggers: triggers to be executed may be added to this hash
sub setupSite {
    my $self     = shift;
    my $site     = shift;
    my $triggers = shift;

    trace( 'tomcat7::setupSite' );

    my $siteId          = $site->siteId;
    my $hostname        = $site->hostName;
    my $siteContextDir  = "$contextDir/$hostname";
    my $webappsDir      = "$sitesAppsDir/$siteId";
    my $siteDocumentDir = "$sitesDir/$siteId";

    unless( -d $siteContextDir ) {
        UBOS::Utils::mkdir( $siteContextDir );
    }
    unless( -d $webappsDir ) {
        UBOS::Utils::mkdir( $webappsDir );
    }
    unless( -d $siteDocumentDir ) {
        UBOS::Utils::mkdir( $siteDocumentDir );
    }

    $self->sitesUpdated();
    $triggers->{'tomcat7-reload'} = 1;

    UBOS::Tomcat7::ensureRunning();

    1;
}

##
# Do what is necessary to remove a Site.
# $site: the Site
# $doIt: if 1, setup; if 0, only check
# $triggers: triggers to be executed may be added to this hash
sub removeSite {
    my $self     = shift;
    my $site     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    trace( 'tomcat7::removeSite' );

    my $siteId          = $site->siteId;
    my $hostname        = $site->hostName;
    my $siteContextDir  = "$contextDir/$hostname";
    my $webappsDir      = "$sitesAppsDir/$siteId";
    my $siteDocumentDir = "$sitesDir/$siteId";

    if( $doIt ) {
        UBOS::Utils::rmdir( $siteDocumentDir );
        UBOS::Utils::rmdir( $webappsDir );
        UBOS::Utils::rmdir( $siteContextDir );
    }

    $self->sitesUpdated();
    $triggers->{'tomcat7-reload'} = 1;

    1;
}

##
# The list of relevant sites has been updated.
sub sitesUpdated {
    my $self = shift;

    my $sites        = UBOS::Host::sites();
    my $hostsSection = <<END;
<!-- Hosts section generated automatically by UBOS -->
END
    foreach my $site ( values %$sites ) {
        if( $site->needsRole( $self )) {
            my $siteId   = $site->siteId;
            my $hostName = $site->hostName;
            my $appBase  = "$sitesAppsDir/$siteId";
            my $logFile  = $siteId . '_access_log.';
            
            $hostsSection .= <<END;
      <Host name="$hostName" appBase="$appBase" unpackWARs="true" autoDeploy="true">

        <!-- SingleSignOn valve, share authentication between web applications
             Documentation at: /docs/config/valve.html -->
        <!--
        <Valve className="org.apache.catalina.authenticator.SingleSignOn" />
        -->

        <!-- Access log processes all example.
             Documentation at: /docs/config/valve.html
             Note: The pattern used is equivalent to using pattern="common" -->
        <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="$logFile" suffix=".log"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />

      </Host>
END
        }
    }
    $hostsSection .= <<END;
<!-- End hosts section -->
END
    
    UBOS::Tomcat7::updateServerXmlFile( $hostsSection );
}

# === Manifest checking routines from here ===

##
# Check the part of an app or accessory manifest that deals with this role.
# $roleName: name of this role, passed for efficiency
# $installable: the installable whose manifest is being checked
# $jsonFragment: the JSON fragment that deals with this role
# $retentionBuckets: keep track of retention buckets, so there's no overlap
# $config: the Configuration object to use
sub checkInstallableManifestForRole {
    my $self             = shift;
    my $roleName         = shift;
    my $installable      = shift;
    my $jsonFragment     = shift;
    my $retentionBuckets = shift;
    my $config           = shift;

    my $noDatabase = {
        'directory'     => 1,
        'directorytree' => 1,
        'file'          => 1,
        'perlscript'    => 1,
        'symlink'       => 1
    };
    my $perlOnly = {
        'perlscript' => 1
    };

    $self->SUPER::checkManifestForRoleGenericDepends(          $roleName, $installable, $jsonFragment, $config );
    $self->SUPER::checkManifestForRoleGenericAppConfigItems(   $roleName, $installable, $jsonFragment, $noDatabase, $retentionBuckets, $config );
    $self->SUPER::checkManifestForRoleGenericTriggersActivate( $roleName, $installable, $jsonFragment, $config );
    $self->SUPER::checkManifestForRoleGenericInstallersEtc(    $roleName, $installable, $jsonFragment, $perlOnly, $config );
}

1;
