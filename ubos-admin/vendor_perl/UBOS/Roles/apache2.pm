#!/usr/bin/perl
#
# apache2 role. The interface to Apache2 is in Apache2.pm
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

package UBOS::Roles::apache2;

use base qw( UBOS::Role );
use fields;

use UBOS::Logging;
use UBOS::Utils;

my $sitesDir         = '/etc/httpd/ubos/sites';
my $defaultSitesDir  = '/etc/httpd/ubos/defaultsites';
my $appConfigsDir    = '/etc/httpd/ubos/appconfigs';
my $sitesDocumentRootDir            = '/srv/http/sites';
my $sitesWellknownDir               = '/srv/http/wellknown';
my $placeholderSitesDocumentRootDir = '/srv/http/placeholders';

# $sitesDir: contains one config file per virtual host, which includes files from $appConfigsDir/$siteId
# $appConfigsDir: contains one directory per site with name $siteId. Each of those contains
#   one config file per AppConfiguration at this site, with name $appConfigId.conf
# $sitesDocumentRootDir: contains one directory per site with name $siteId, which is that Site's DocumentRoot

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
# Name of this Role
# return: name
sub name {
    my $self = shift;

    return 'apache2';
}

##
# Deploy an installable in an AppConfiguration in this Role, or just check whether
# it is deployable. Both functions share the same code, so the checks get updated
# at the same time as the actual deployment.
# $doIt: if 1, deploy; if 0, only check
# $appConfig: the AppConfiguration to deploy
# $installable: the Installable
# $config: the Configuration to use
# return: success or fail
sub deployOrCheck {
    my $self        = shift;
    my $doIt        = shift;
    my $appConfig   = shift;
    my $installable = shift;
    my $config      = shift;

    my $roleName            = $self->name();
    my $installableRoleJson = $installable->installableJson->{roles}->{$roleName};
    if( $installableRoleJson ) {
        my $apache2modules = $installableRoleJson->{apache2modules};
        my $numberActivated = 0;
        if( $appConfig->site->hasTls ) {
            push @$apache2modules, 'ssl';
        }
        if( $doIt && $apache2modules ) {
            $numberActivated += UBOS::Apache2::activateApacheModules( @$apache2modules );
        }
        my $phpModules = $installableRoleJson->{phpmodules};
        if( $doIt && $phpModules ) {
            $numberActivated += UBOS::Apache2::activatePhpModules( @$phpModules );
        }
        if( $numberActivated ) {
            UBOS::Apache2::restart(); # reload seems to be insufficient
        }
    }
    return $self->SUPER::deployOrCheck( $doIt, $appConfig, $installable, $config );
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

    my $siteDocumentDir = $site->config->getResolve( 'site.apache2.sitedocumentdir' );

    if( $doIt ) {
        UBOS::Utils::mkdir( $siteDocumentDir, 0755 );
        return $self->setupSite( $site, $triggers );
    } else {
        return 1;
    }
}

##
# Do what is necessary to set up a named placeholder Site.
# $site: the Site for which a placeholder shall be set up
# $placeholderName: name of the placeholder
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub setupPlaceholderSite {
    my $self            = shift;
    my $site            = shift;
    my $placeholderName = shift;
    my $triggers        = shift;

    my $siteId            = $site->siteId;
    my $hostname          = $site->hostname;
    my $siteFile          = ( '*' eq $hostname ) ? "$defaultSitesDir/any.conf" : "$sitesDir/$siteId.conf";
    my $siteDocumentRoot  = "$placeholderSitesDocumentRootDir/$placeholderName";
    my $serverDeclaration = ( '*' eq $hostname ) ? '# Hostname * (any)' : "    ServerName $hostname";

    debug( 'apache2::setupPlaceholderSite', $siteId );

    unless( -d $siteDocumentRoot ) {
        error( 'Placeholder site', $placeholderName, 'does not exist at', $siteDocumentRoot );
    }

    my $content .= <<CONTENT;
#
# Apache config fragment for placeholder site $siteId (placeholder $placeholderName) at host $hostname
#
# (C) 2013-2014 Indie Computing Corp.
# Generated automatically, do not modify.
#

<VirtualHost *:80>
$serverDeclaration

    DocumentRoot "$siteDocumentRoot"
    Options -Indexes

    AliasMatch ^/_common/css/([-a-z0-9]*\.css)\$ /srv/http/_common/css/\$1
    AliasMatch ^/_common/images/([-a-z0-9]*\.png)\$ /srv/http/_common/images/\$1
</VirtualHost>
CONTENT

    UBOS::Utils::saveFile( $siteFile, $content );

    $triggers->{'httpd-reload'} = 1;

    return 1;
}

##
# Do what is necessary to set up a Site, without activating/resuming it.
# $site: the Site
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub setupSite {
    my $self     = shift;
    my $site     = shift;
    my $triggers = shift;

    my $siteId            = $site->siteId;
    my $appConfigFilesDir = "$appConfigsDir/$siteId";
    my $siteWellKnownDir  = "$sitesWellknownDir/$siteId";

    debug( 'apache2::setupSite', $siteId );

    unless( -d $siteWellKnownDir ) {
        UBOS::Utils::mkdir( $siteWellKnownDir );
    }
    unless( -d $appConfigFilesDir ) {
        UBOS::Utils::mkdir( $appConfigFilesDir );
    }

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

    my $siteId            = $site->siteId;
    my $hostname          = $site->hostname;
    my $appConfigFilesDir = "$appConfigsDir/$siteId";
    my $siteFile          = ( '*' eq $hostname ) ? "$defaultSitesDir/any.conf" : "$sitesDir/$siteId.conf";
    my $siteDocumentRoot  = "$sitesDocumentRootDir/$siteId";
    my $siteWellKnownDir  = "$sitesWellknownDir/$siteId";
    my $serverDeclaration = ( '*' eq $hostname ) ? '# Hostname * (any)' : "    ServerName $hostname";

    my $robotsTxt  = $site->robotsTxt();
    my $sitemapXml = $site->sitemapXml();
    my $faviconIco = $site->faviconIco();

    if( $robotsTxt ) {
        UBOS::Utils::saveFile( "$siteWellKnownDir/robots.txt", $robotsTxt );
    }
    if( $sitemapXml ) {
        UBOS::Utils::saveFile( "$siteWellKnownDir/sitemap.xml", $sitemapXml );
    }
    if( $faviconIco ) {
        UBOS::Utils::saveFile( "$siteWellKnownDir/favicon.ico", $faviconIco );
    }

    my $siteFileContent = <<CONTENT;
#
# Apache config fragment for site $siteId at host $hostname
#
# (C) 2013-2015 Indie Computing Corp.
# Generated automatically, do not modify.
#
CONTENT
    
    my $siteAtPort;
    my $sslDir;
    my $sslKey;
    my $sslCert;
    my $sslCertChain;
    my $sslCaCert;
    
    if( $site->hasTls ) {
        $siteAtPort = 443;
        $siteFileContent .= <<CONTENT;

<VirtualHost *:80>
$serverDeclaration

    RewriteEngine On
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
    # This also works for wildcard hostnames
</VirtualHost>
CONTENT

        $sslDir       = $site->config->getResolve( 'apache2.ssldir' );
        $sslKey       = $site->tlsKey;
        $sslCert      = $site->tlsCert;
        $sslCertChain = $site->tlsCertChain;
        $sslCaCert    = $site->tlsCaCert;

        my $group = $site->config->getResolve( 'apache2.gname' );
        
        if( $sslKey ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.key",      $sslKey,       0440, 'root', $group ); # avoid overwrite by apache
        }
        if( $sslCert ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.crt",      $sslCert,      0440, 'root', $group );
        }
        if( $sslCertChain ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.crtchain", $sslCertChain, 0440, 'root', $group );
        }
        if( $sslCaCert ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.cacrt", $sslCaCert, 0040, 'root', $group );
        }

    } else {
        # No SSL
        $siteAtPort = 80;
    }
    
    $siteFileContent .= <<CONTENT;

<VirtualHost *:$siteAtPort>
$serverDeclaration

    DocumentRoot "$siteDocumentRoot"
    Options -Indexes

    SetEnv SiteId "$siteId"

    <Directory "$siteDocumentRoot">
        AllowOverride All

        <IfModule php5_module>
            php_admin_value open_basedir $siteDocumentRoot:/tmp/:/usr/share/
        </IfModule>
    </Directory>
CONTENT

    if( $site->hasTls ) {
        $siteFileContent .= <<CONTENT;

    SSLEngine on

    # our own key
    SSLCertificateKeyFile $sslDir/$siteId.key

    # our own cert
    SSLCertificateFile $sslDir/$siteId.crt
CONTENT
        if( $sslCertChain ) {
            $siteFileContent .= <<CONTENT;
 
    # the CA certs explaining where we got our own cert from
    SSLCertificateChainFile $sslDir/$siteId.crtchain
CONTENT
        }
        if( $sslCaCert ) {
            $siteFileContent .= <<CONTENT;

    # the CA certs explaining where our clients got their certs from
    SSLCACertificateFile $sslDir/$siteId.cacrt
CONTENT
        }
    }

    my $hasDefault = 0;
    foreach my $appConfig ( @{$site->appConfigs} ) {
        my $context = $appConfig->context();
        if( $appConfig->isDefault ) {
            $hasDefault = 1;
            if( $context ) {
                $siteFileContent .= <<CONTENT;

    RedirectMatch seeother ^/\$ $context/
CONTENT
                last;
            }
        } elsif( defined( $context ) && !$context ) {
            # runs at root of site
            $hasDefault = 1;
        }
    }
    unless( $hasDefault ) {
        $siteFileContent .= <<CONTENT;

    ScriptAliasMatch ^/\$ /usr/share/ubos/cgi-bin/show-apps.pl
    ScriptAliasMatch ^/_appicons/([-a-z0-9]+)/([0-9]+x[0-9]+|license)\\.(png|txt)\$ /usr/share/ubos/cgi-bin/render-appicon.pl

    AliasMatch ^/_common/css/([-a-z0-9]*\.css)\$ /srv/http/_common/css/\$1
    AliasMatch ^/_common/images/([-a-z0-9]*\.png)\$ /srv/http/_common/images/\$1
CONTENT
    }
    $siteFileContent .= "\n";

    if( $robotsTxt ) {
        $siteFileContent .= <<CONTENT;
    AliasMatch ^/robots\.txt\$  $siteWellKnownDir/robots.txt
CONTENT
    }
    if( $sitemapXml ) {
        $siteFileContent .= <<CONTENT;
    AliasMatch ^/sitemap\.xml\$ $siteWellKnownDir/sitemap.xml
CONTENT
    }
    if( $faviconIco ) {
        $siteFileContent .= <<CONTENT;
    AliasMatch ^/favicon\.ico\$ $siteWellKnownDir/favicon.ico
CONTENT
    }

    $siteFileContent .= <<CONTENT;

    Include $appConfigFilesDir/
</VirtualHost>
CONTENT

    UBOS::Utils::saveFile( $siteFile, $siteFileContent, 0644 );
    
    $triggers->{'httpd-reload'} = 1;

    return 1;
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

    my $siteId            = $site->siteId;
    my $hostname          = $site->hostname;
    my $siteFile          = ( '*' eq $hostname ) ? "$defaultSitesDir/any.conf" : "$sitesDir/$siteId.conf";
    my $appConfigFilesDir = "$appConfigsDir/$siteId";
    my $siteDocumentDir   = "$sitesDocumentRootDir/$siteId";
    my $siteWellKnownDir  = "$sitesWellknownDir/$siteId";
    my $sslDir            = $site->config->getResolve( 'apache2.ssldir' );

    debug( 'apache2::removeSite', $siteId, $doIt );

    if( $doIt ) {
        UBOS::Utils::deleteFile( $siteFile );

        if( -d $appConfigFilesDir ) {
            UBOS::Utils::rmdir( $appConfigFilesDir );
        }
        if( -d $siteWellKnownDir ) {
            UBOS::Utils::deleteRecursively( $siteWellKnownDir );
        }

        UBOS::Utils::rmdir( $siteDocumentDir );

        my @toDelete = ();
        foreach my $ext ( qw( .key .crt .crtchain .cacrt )) {
            my $f = "$sslDir/$siteId$ext";
            if( -e $f ) {
                push @toDelete, $f;
            }
        }
        if( @toDelete ) {
            UBOS::Utils::deleteFile( @toDelete );
        }

        $triggers->{'httpd-reload'} = 1;
    }

    return 1;
}

# === Manifest checking routines from here ===

##
# Check the part of an app manifest that deals with this role.
# $roleName: name of this role, passed for efficiency
# $installable: the installable whose manifest is being checked
# $jsonFragment: the JSON fragment that deals with this role
# $retentionBuckets: keep track of retention buckets, so there's no overlap
# $config: the Configuration object to use
sub checkAppManifestForRole {
    my $self             = shift;
    my $roleName         = shift;
    my $installable      = shift;
    my $jsonFragment     = shift;
    my $retentionBuckets = shift;
    my $config           = shift;

    if( $installable->isa( 'UBOS::App' )) {
        if( defined( $jsonFragment->{defaultcontext} )) {
            if( defined( $jsonFragment->{fixedcontext} )) {
                $installable->myFatal( "roles section: role $roleName: must not specify both defaultcontext and fixedcontext" );
            }
            if( ref( $jsonFragment->{defaultcontext} )) {
                $installable->myFatal( "roles section: role $roleName: field 'defaultcontext' must be string" );
            }
            unless( $jsonFragment->{defaultcontext} =~ m!^(/[-a-z0-9]+)*$! ) {
                $installable->myFatal( "roles section: role $roleName: invalid defaultcontext: " . $jsonFragment->{defaultcontext} );
            }

        } elsif( defined( $jsonFragment->{fixedcontext} )) {
            if( ref( $jsonFragment->{fixedcontext} )) {
                $installable->myFatal( "roles section: role $roleName: field 'fixedcontext' must be string" );
            }
            unless( $jsonFragment->{fixedcontext} =~ m!^(/[-a-z0-9]+)*$! ) {
                $installable->myFatal( "roles section: role $roleName: invalid fixedcontext: " . $jsonFragment->{fixedcontext} );
            }
        } else {
            $installable->myFatal( "roles section: role $roleName: either defaultcontext or fixedcontext must be given" );
        }
    } elsif( defined( $jsonFragment->{defaultcontext} )) {
        $installable->myFatal( "roles section: role $roleName: only provide field 'defaultcontext' for apps" );
    } elsif( defined( $jsonFragment->{fixedcontext} )) {
        $installable->myFatal( "roles section: role $roleName: only provide field 'fixedcontext' for apps" );
    }        

    $self->checkInstallableManifestForRole( $roleName, $installable, $jsonFragment, $retentionBuckets, $config );
}

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

    if( $jsonFragment->{apache2modules} ) {
        unless( ref( $jsonFragment->{apache2modules} ) eq 'ARRAY' ) {
            $installable->myFatal( "roles section: role $roleName: apache2modules is not an array" );
        }
        my $modulesIndex = 0;
        foreach my $module ( @{$jsonFragment->{apache2modules}} ) {
            if( ref( $module )) {
                $installable->myFatal( "roles section: role $roleName: apache2modules[$modulesIndex] must be string" );
            }
            unless( $module =~ m!^[-_a-z0-9]+$! ) {
                $installable->myFatal( "roles section: role $roleName: apache2modules[$modulesIndex] invalid: $module" );
            }
            ++$modulesIndex;
        }
    }
    if( $jsonFragment->{phpmodules} ) {
        unless( ref( $jsonFragment->{phpmodules} ) eq 'ARRAY' ) {
            $installable->myFatal( "roles section: role $roleName: phpmodules is not an array" );
        }
        my $modulesIndex = 0;
        foreach my $module ( @{$jsonFragment->{phpmodules}} ) {
            if( ref( $module )) {
                $installable->myFatal( "roles section: role $roleName: phpmodules[$modulesIndex] must be string" );
            }
            unless( $module =~ m!^[-_a-z0-9]+$! ) {
                $installable->myFatal( "roles section: role $roleName: phpmodules[$modulesIndex] invalid: $module" );
            }
            ++$modulesIndex;
        }
    }

    my $noDatabase = {
        'directory'       => 1,
        'directorytree'   => 1,
        'file'            => 1,
        'perlscript'      => 1,
        'symlink'         => 1,
        'systemd-service' => 1
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
