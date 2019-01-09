#!/usr/bin/perl
#
# tomcat8 role. The interface to Tomcat8 is in Tomcat8.pm
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Roles::tomcat8;

use base qw( UBOS::Role );
use fields;

use UBOS::Host;
use UBOS::Logging;
use UBOS::Tomcat8;
use UBOS::Utils;

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

    return 'tomcat8';
}

##
# Make sure the Site/virtual host is set up, or set it up
# $site: the Site to check or set up
# $doIt: if 1, setup; if 0, only check
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub setupSiteOrCheck {
    my $self     = shift;
    my $site     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    trace( 'tomcat8::setupSiteOrCheck', $self->name(), $doIt, $site->siteId );

    my $siteDocumentDir = $site->vars()->getResolve( 'site.tomcat8.sitedocumentdir' );
    my $sitesDir        = UBOS::Host::vars()->getResolve( 'tomcat8.sitesdir' );
    my $sitesAppsDir    = UBOS::Host::vars()->getResolve( 'tomcat8.sitesappsdir' );
    my $contextDir      = UBOS::Host::vars()->getResolve( 'tomcat8.contextsdir' );

    if( $doIt ) {
        UBOS::Utils::mkdirDashP( $siteDocumentDir, 0755 );

        trace( 'tomcat8::_setupSite', $self->name(), $site->siteId );

        if( UBOS::Host::ensurePackages( 'tomcat8' ) < 0 ) {
            warning( $@ );
        }

        my $siteId          = $site->siteId;
        my $hostname        = $site->hostnameorwildcard;
        my $siteContextDir  = "$contextDir/$hostname";
        my $webappsDir      = "$sitesAppsDir/$siteId";
        my $siteDocumentDir = "$sitesDir/$siteId";
        my $tomcatUser      = $site->vars()->getResolve( 'tomcat8.uname' );
        my $tomcatGroup     = $site->vars()->getResolve( 'tomcat8.gname' );

        trace( 'tomcat8::setupSite', $siteId );

        unless( -d $siteContextDir ) {
            UBOS::Utils::mkdirDashP( $siteContextDir );
        }
        unless( -d $webappsDir ) {
            UBOS::Utils::mkdirDashP( $webappsDir, 0755, $tomcatUser, $tomcatGroup, 0755, 'root', 'root' );
        }
        unless( -d $siteDocumentDir ) {
            UBOS::Utils::mkdirDashP( $siteDocumentDir );
        }

        return 1;

    } else {
        return 1;
    }
}

##
# Do what is necessary to suspend an already set-up Site
# $site: the Site
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub suspendSite {
    my $self     = shift;
    my $site     = shift;
    my $triggers = shift;

    $triggers->{'tomcat8-reload'} = 1;

    return 1;
}

##
# Do what is necessary to activate/resume an already set-up Site
# $site: the Site
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub resumeSite {
    my $self     = shift;
    my $site     = shift;
    my $triggers = shift;

    trace( 'tomcat8::resumeSite', $self->name(), $site->siteId );

    $self->sitesUpdated();

    $triggers->{'tomcat8-reload'} = 1;
}

##
# Do what is necessary to remove a Site.
# $site: the Site
# $doIt: if 1, setup; if 0, only check
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub removeSite {
    my $self     = shift;
    my $site     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    trace( 'tomcat8::removeSite', $self->name(), $doIt, $site->siteId );

    my $sitesDir        = UBOS::Host::vars()->getResolve( 'tomcat8.sitesdir' );
    my $sitesAppsDir    = UBOS::Host::vars()->getResolve( 'tomcat8.sitesappsdir' );
    my $contextDir      = UBOS::Host::vars()->getResolve( 'tomcat8.contextsdir' );

    my $siteId          = $site->siteId;
    my $hostname        = $site->hostnameorwildcard;
    my $siteContextDir  = "$contextDir/$hostname";
    my $webappsDir      = "$sitesAppsDir/$siteId";
    my $siteDocumentDir = "$sitesDir/$siteId";

    trace( 'tomcat8::removeSite', $siteId, $doIt );

    if( $doIt ) {
        UBOS::Utils::rmdir( $siteDocumentDir );
        UBOS::Utils::deleteRecursively( $webappsDir ); # Tomcat expands the JAR file into this directory
        UBOS::Utils::rmdir( $siteContextDir );

        $self->sitesUpdated();
        $triggers->{'tomcat8-reload'} = 1;
    }

    return 1;
}

##
# The list of relevant sites has been updated.
sub sitesUpdated {
    my $self = shift;

    my $sitesAppsDir    = UBOS::Host::vars()->getResolve( 'tomcat8.sitesappsdir' );

    my $sites        = UBOS::Host::sites();
    my $hostsSection = <<END;
<!-- Hosts section generated automatically by UBOS -->
END
    foreach my $site ( values %$sites ) {
        if( $site->needsRole( $self )) {
            my $siteId   = $site->siteId;
            my $hostname = $site->hostnameorwildcard;
            my $appBase  = "$sitesAppsDir/$siteId";
            my $logFile  = $siteId . '_access_log.';

            $hostsSection .= <<END;
      <Host name="$hostname" appBase="$appBase" unpackWARs="true" autoDeploy="true">

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

    debugAndSuspend( 'Update tomcat8 server.xml file' );
    UBOS::Tomcat8::updateServerXmlFile( $hostsSection );
}

# === Manifest checking routines from here ===

##
# Check the part of an app or accessory manifest that deals with this role.
# $roleName: name of this role, passed for efficiency
# $installable: the installable whose manifest is being checked
# $jsonFragment: the JSON fragment that deals with this role
# $retentionBuckets: keep track of retention buckets, so there's no overlap
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# $vars: the Variables object that knows about symbolic names and variables
sub checkInstallableManifestForRole {
    my $self                 = shift;
    my $roleName             = shift;
    my $installable          = shift;
    my $jsonFragment         = shift;
    my $retentionBuckets     = shift;
    my $skipFilesystemChecks = shift;
    my $vars                 = shift;

    my $noDatabase = {
        'directory'       => 1,
        'directorytree'   => 1,
        'file'            => 1,
        'perlscript'      => 1,
        'exec'            => 1,
        'symlink'         => 1,
        'systemd-service' => 1,
        'systemd-target'  => 1,
        'systemd-timer'   => 1,
        'tcpport'         => 1,
        'udpport'         => 1
    };
    my $perlOnly = {
        'perlscript' => 1,
        'exec'       => 1
    };

    $self->SUPER::checkManifestForRoleGenericDepends(        $roleName, $installable, $jsonFragment, $vars );
    $self->SUPER::checkManifestForRoleGenericAppConfigItems( $roleName, $installable, $jsonFragment, $noDatabase, $retentionBuckets, $skipFilesystemChecks, $vars );
    $self->SUPER::checkManifestForRoleGenericInstallersEtc(  $roleName, $installable, $jsonFragment, $perlOnly, $skipFilesystemChecks, $vars );
}

1;
