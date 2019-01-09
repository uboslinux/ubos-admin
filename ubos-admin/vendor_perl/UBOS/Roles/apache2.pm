#!/usr/bin/perl
#
# apache2 role. The interface to Apache2 is in Apache2.pm
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Roles::apache2;

use base qw( UBOS::Role );
use fields;

use UBOS::Host;
use UBOS::LetsEncrypt;
use UBOS::Logging;
use UBOS::Utils;

my @forErrors = ( '_errors', '_common' );

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
# Is this Role always needed, regardless of what the AppConfigurations say?
# return: true or false
sub isAlwaysNeeded {
    my $self = shift;

    return 1;
}

##
# Deploy an installable in an AppConfiguration in this Role, or just check whether
# it is deployable. Both functions share the same code, so the checks get updated
# at the same time as the actual deployment.
# $doIt: if 1, deploy; if 0, only check
# $appConfig: the AppConfiguration to deploy
# $installable: the Installable
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub deployOrCheck {
    my $self        = shift;
    my $doIt        = shift;
    my $appConfig   = shift;
    my $installable = shift;
    my $vars        = shift;

    my $roleName = $self->name();

    trace( 'apache2::deployOrCheck', $roleName, $doIt, $appConfig->appConfigId, $installable->packageName );

    my $installableRoleJson = $installable->installableJson->{roles}->{$roleName};
    if( $installableRoleJson && $doIt ) {
        my $apache2modules = $installableRoleJson->{apache2modules};
        my $numberActivated = 0;
        if( $apache2modules ) {
            $numberActivated += UBOS::Apache2::activateApacheModules( @$apache2modules );
        }
        my $phpModules = $installableRoleJson->{phpmodules};
        if( $phpModules ) {
            $numberActivated += UBOS::Apache2::activatePhpModules( @$phpModules );
        }
        if( $numberActivated ) {
            UBOS::Apache2::restart(); # reload seems to be insufficient
        }
    }
    return $self->SUPER::deployOrCheck( $doIt, $appConfig, $installable, $vars );
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

    trace( 'apache2::setupSiteOrCheck', $self->name(), $doIt, $site->siteId );

    my $siteDocumentDir      = $site->vars()->getResolve( 'site.apache2.sitedocumentdir' );
    my $siteTorDir           = $site->vars()->getResolve( 'site.apache2.sitetordir' );
    my $siteTorFragmentFile  = $site->vars()->getResolve( 'site.apache2.sitetorfragmentfile' );
    my $appConfigFragmentDir = UBOS::Host::vars()->getResolve( 'apache2.appconfigfragmentdir' );
    my $sitesWellknownDir    = UBOS::Host::vars()->getResolve( 'apache2.siteswellknowndir' );

    if( $doIt ) {
        if( $site->hasTls ) {
            my $numberActivated += UBOS::Apache2::activateApacheModules( 'ssl' );
            if( $numberActivated ) {
                UBOS::Apache2::restart(); # reload seems to be insufficient
            }
        }

        unless( -d $siteDocumentDir ) {
            UBOS::Utils::mkdirDashP( $siteDocumentDir, 0755 );

            # Allow Apache to find the error documents for this site
            foreach my $forError( @forErrors ) {
                UBOS::Utils::symlink( "/srv/http/$forError", "$siteDocumentDir/$forError" );
            }
        }

        my $siteId            = $site->siteId;
        my $appConfigFilesDir = "$appConfigFragmentDir/$siteId";
        my $siteWellKnownDir  = "$sitesWellknownDir/$siteId";

        trace( 'apache2::setupSite', $siteId );

        unless( -d $siteWellKnownDir ) {
            UBOS::Utils::mkdirDashP( $siteWellKnownDir );
        }
        unless( -d $appConfigFilesDir ) {
            UBOS::Utils::mkdirDashP( $appConfigFilesDir );
        }

        if( $site->isTor() ) {
            UBOS::Utils::mkdirDashP( $siteTorDir, 0700, 'tor', 'tor', 0755, 'root', 'root' );

            UBOS::Utils::saveFile( $siteTorFragmentFile, <<CONTENT );
HiddenServiceDir $siteTorDir/
CONTENT

            my $privateKey = $site->torPrivateKey();
            my $hostname   = $site->hostname();
            if( $privateKey ) {
                UBOS::Utils::saveFile( "$siteTorDir/private_key", "$privateKey\n", 0600, 'tor', 'tor' );
            }
            if( $hostname ) {
                UBOS::Utils::saveFile( "$siteTorDir/hostname", "$hostname\n", 0600, 'tor', 'tor' );
            }
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

    return $self->setupPlaceholderSite( $site, 'maintenance', $triggers );
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

    trace( 'apache2::setupPlaceholderSite', $self->name(), $site->siteId );

    my $siteFragmentDir                 = UBOS::Host::vars()->getResolve( 'apache2.sitefragmentdir' );
    my $defaultSiteFragmentDir          = UBOS::Host::vars()->getResolve( 'apache2.defaultsitefragmentdir' );
    my $sitesWellknownDir               = UBOS::Host::vars()->getResolve( 'apache2.siteswellknowndir' );
    my $placeholderSitesDocumentRootDir = UBOS::Host::vars()->getResolve( 'apache2.placeholdersitesdir' );

    my $siteId            = $site->siteId;
    my $hostname          = $site->hostname;
    my $port              = $site->port;
    my $siteFile          = ( '*' eq $hostname ) ? "$defaultSiteFragmentDir/any.conf" : "$siteFragmentDir/$siteId.conf";
    my $siteDocumentRoot  = "$placeholderSitesDocumentRootDir/$placeholderName";
    my $serverDeclaration = ( '*' eq $hostname ) ? '# Hostname * (any)' : "    ServerName $hostname";
    my $siteWellKnownDir  = "$sitesWellknownDir/$siteId";

    unless( -d $siteDocumentRoot ) {
        error( 'Placeholder site', $placeholderName, 'does not exist at', $siteDocumentRoot );
    }

    if( $site->hasTls ) {
        my $numberActivated += UBOS::Apache2::activateApacheModules( 'ssl' );
        if( $numberActivated ) {
            UBOS::Apache2::restart(); # reload seems to be insufficient
        }
    }

    my $siteFileContent .= <<CONTENT;
#
# Apache config fragment for placeholder site $siteId (placeholder $placeholderName) at host $hostname
#
# Generated automatically, do not modify.
#
CONTENT

    my $sslDir;
    my $sslKey;
    my $sslCert;
    my $sslCaCert;

    if( $site->hasTls ) {
        $siteFileContent .= <<CONTENT;

<VirtualHost *:80>
$serverDeclaration

    RewriteEngine On
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
    # This also works for wildcard hostnames
</VirtualHost>
CONTENT

        $sslDir       = $site->vars()->getResolve( 'apache2.ssldir' );
        $sslKey       = $site->tlsKey;
        $sslCert      = $site->tlsCert;
        $sslCaCert    = $site->tlsCaCert;

        my $group = $site->vars()->getResolve( 'apache2.gname' );

        if( $sslKey ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.key",   $sslKey,    0440, 'root', $group ); # avoid overwrite by apache
        }
        if( $sslCert ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.crt",   $sslCert,   0440, 'root', $group );
        }
        if( $sslCaCert ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.cacrt", $sslCaCert, 0040, 'root', $group );
        }

    } # else No SSL

    $siteFileContent .= <<CONTENT;

<VirtualHost *:$port>
$serverDeclaration

    DocumentRoot "$siteDocumentRoot"
    Options -Indexes

    AliasMatch ^/_common/css/([-a-z0-9]*\.css)\$ /srv/http/_common/css/\$1
    AliasMatch ^/_common/images/([-a-z0-9]*\.png)\$ /srv/http/_common/images/\$1

    Alias /\.well-known/ $siteWellKnownDir/.well-known/

    AliasMatch ^.*\$ "$siteDocumentRoot/index.html"
CONTENT

    if( $site->hasTls ) {
        $siteFileContent .= <<CONTENT;

    SSLEngine on

    SSLCertificateKeyFile $sslDir/$siteId.key
    SSLCertificateFile $sslDir/$siteId.crt
CONTENT
        if( $sslCaCert ) {
            $siteFileContent .= <<CONTENT;

    # the CA certs explaining where our clients got their certs from
    SSLCACertificateFile $sslDir/$siteId.cacrt
CONTENT
        }
    }

    $siteFileContent .= <<CONTENT;

</VirtualHost>
CONTENT

    UBOS::Utils::saveFile( $siteFile, $siteFileContent );

    $triggers->{'httpd-reload'} = 1;

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

    trace( 'apache2::resumeSite', $self->name(), $site->siteId );

    my $siteFragmentDir        = UBOS::Host::vars()->getResolve( 'apache2.sitefragmentdir' );
    my $defaultSiteFragmentDir = UBOS::Host::vars()->getResolve( 'apache2.defaultsitefragmentdir' );
    my $sitesDocumentRootDir   = UBOS::Host::vars()->getResolve( 'apache2.sitesdir' );
    my $sitesWellknownDir      = UBOS::Host::vars()->getResolve( 'apache2.siteswellknowndir' );
    my $appConfigFragmentDir   = UBOS::Host::vars()->getResolve( 'apache2.appconfigfragmentdir' );
    my $tmpDir                 = UBOS::Host::vars()->getResolve( 'host.tmpdir' );
    my $siteId                 = $site->siteId;
    my $hostname               = $site->hostname;
    my $port                   = $site->port;
    my $appConfigFilesDir      = "$appConfigFragmentDir/$siteId";
    my $siteFile               = ( '*' eq $hostname ) ? "$defaultSiteFragmentDir/any.conf" : "$siteFragmentDir/$siteId.conf";
    my $siteDocumentRoot       = "$sitesDocumentRootDir/$siteId";
    my $siteWellKnownDir       = "$sitesWellknownDir/$siteId";
    my $serverDeclaration      = ( '*' eq $hostname ) ? '# Hostname * (any)' : "    ServerName $hostname";

    my $robotsTxt  = $site->robotsTxt();
    my $sitemapXml = $site->sitemapXml();
    my $faviconIco = $site->faviconIco();

    unless( -d $siteDocumentRoot ) {
        UBOS::Utils::mkdirDashP( $siteDocumentRoot );
    }
    unless( -d $sitesWellknownDir ) {
        UBOS::Utils::mkdirDashP( $sitesWellknownDir );
    }
    unless( -d $siteFragmentDir ) {
        UBOS::Utils::mkdirDashP( $siteFragmentDir );
    }

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
# Generated automatically, do not modify.
#
CONTENT

    my $sslDir;
    my $sslKey;
    my $sslCert;
    my $sslCaCert;

    if( $site->hasTls ) {
        $siteFileContent .= <<CONTENT;

<VirtualHost *:80>
$serverDeclaration

    RewriteEngine On
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
    # This also works for wildcard hostnames
</VirtualHost>
CONTENT

        $sslDir       = $site->vars()->getResolve( 'apache2.ssldir' );
        $sslKey       = $site->tlsKey;
        $sslCert      = $site->tlsCert;
        $sslCaCert    = $site->tlsCaCert;

        my $group = $site->vars()->getResolve( 'apache2.gname' );

        if( $sslKey ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.key",   $sslKey,    0440, 'root', $group ); # avoid overwrite by apache
        }
        if( $sslCert ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.crt",   $sslCert,   0440, 'root', $group );
        }
        if( $sslCaCert ) {
            UBOS::Utils::saveFile( "$sslDir/$siteId.cacrt", $sslCaCert, 0040, 'root', $group );
        }

    } # else No SSL

    $siteFileContent .= <<CONTENT;

<VirtualHost *:$port>
$serverDeclaration

    DocumentRoot "$siteDocumentRoot"
    Options -Indexes

    SetEnv SiteId "$siteId"

    <Directory "$siteDocumentRoot">
        AllowOverride All

        <IfModule php7_module>
            php_admin_value open_basedir $siteDocumentRoot/:$tmpDir/:/ubos/share/:/srv/http/
        </IfModule>
    </Directory>
CONTENT

    if( $site->hasTls ) {
        $siteFileContent .= <<CONTENT;

    SSLEngine on

    SSLCertificateKeyFile $sslDir/$siteId.key
    SSLCertificateFile $sslDir/$siteId.crt
CONTENT
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

    RedirectMatch 307 ^/\$ $context/
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

    $siteFileContent .= <<CONTENT;
    Alias /\.well-known/ $siteWellKnownDir/.well-known/
CONTENT

    if( $robotsTxt ) {
        $siteFileContent .= <<CONTENT;
    AliasMatch ^/robots\.txt\$ $siteWellKnownDir/robots.txt
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

    trace( 'apache2::removeSite', $self->name(), $doIt, $site->siteId );

    my $siteFragmentDir        = UBOS::Host::vars()->getResolve( 'apache2.sitefragmentdir' );
    my $defaultSiteFragmentDir = UBOS::Host::vars()->getResolve( 'apache2.defaultsitefragmentdir' );
    my $appConfigFragmentDir   = UBOS::Host::vars()->getResolve( 'apache2.appconfigfragmentdir' );
    my $sitesWellknownDir      = UBOS::Host::vars()->getResolve( 'apache2.siteswellknowndir' );
    my $siteDocumentDir        = $site->vars()->getResolve( 'site.apache2.sitedocumentdir' );
    my $siteTorDir             = $site->vars()->getResolve( 'site.apache2.sitetordir' );
    my $siteTorFragmentFile    = $site->vars()->getResolve( 'site.apache2.sitetorfragmentfile' );

    my $siteId            = $site->siteId;
    my $hostname          = $site->hostname;
    my $siteFile          = ( '*' eq $hostname ) ? "$defaultSiteFragmentDir/any.conf" : "$siteFragmentDir/$siteId.conf";
    my $appConfigFilesDir = "$appConfigFragmentDir/$siteId";
    my $siteWellKnownDir  = "$sitesWellknownDir/$siteId";
    my $sslDir            = $site->vars()->getResolve( 'apache2.ssldir' );

    trace( 'apache2::removeSite', $siteId, $doIt );

    if( $doIt ) {
        UBOS::Utils::deleteFile( $siteFile );

        if( -d $appConfigFilesDir ) {
            UBOS::Utils::rmdir( $appConfigFilesDir );
        }
        if( -d $siteTorDir ) { # does not exist if not tor
            UBOS::Utils::deleteRecursively( $siteTorDir );
        }
        if( -e $siteTorFragmentFile ) {
            UBOS::Utils::deleteFile( $siteTorFragmentFile );
        }
        foreach my $forError( @forErrors ) {
            UBOS::Utils::deleteFile( "$siteDocumentDir/$forError" );
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

        if( $site->isTor() ) {
            $triggers->{'tor-reload'} = 1;
        }
        $triggers->{'httpd-reload'} = 1;
    }

    return 1;
}

##
# Determine whether we already have a letsencrypt certificate for this role for the given site
# $site: the Site
# return: 0 or 1
sub hasLetsEncryptCert {
    my $self = shift;
    my $site = shift;

    unless( $site->hasLetsEncryptTls()) {
        return 0;
    }
    if( $site->tlsKey() && $site->tlsCert() ) {
        return 1;
    }

    my $status = UBOS::LetsEncrypt::determineCertificateStatus( $site->hostname );
    if( $status ) {
        return $status->{isvalid};
    } else {
        return undef;
    }
}

##
# If this role needs a letsencrypt certificate, obtain it. If we already
# have a non-active one, use that instead and attempt to renew.
# $site: the site that needs the certificate
# return: 1 if succeeded
sub obtainLetsEncryptCertificate {
    my $self = shift;
    my $site = shift;

    my $sitesWellknownDir = UBOS::Host::vars()->getResolve( 'apache2.siteswellknowndir' );

    my $adminHash        = $site->obtainSiteAdminHash;
    my $siteId           = $site->siteId;
    my $siteWellKnownDir = "$sitesWellknownDir/$siteId";
    my $hostname         = $site->hostname;

    unless( -d $siteWellKnownDir ) {
        UBOS::Utils::mkdirDashP( $siteWellKnownDir );
    }

    if( UBOS::LetsEncrypt::makeCertificateRenew( $hostname )) {
        UBOS::LetsEncrypt::renewCertificate( $hostname );
    } else {
        UBOS::LetsEncrypt::obtainCertificate( $hostname, $siteWellKnownDir, $adminHash->{email} );
    }

    my $letsEncryptStatus = UBOS::LetsEncrypt::determineCertificateStatus( $hostname, 1 );
    if( $letsEncryptStatus && $letsEncryptStatus->{isvalid} ) {
        $site->setTlsKeyAndCert(
                UBOS::Utils::slurpFile( $letsEncryptStatus->{keypath} ),
                UBOS::Utils::slurpFile( $letsEncryptStatus->{certpath} ));
    }
    return 1;
}

##
# If this role needs (needed) a letsencrypt certificate, deactivate it.
# $site: the site that needs (needed) the certificate
sub deactivateLetsEncryptCertificate {
    my $self = shift;
    my $site = shift;

    my $hostname = $site->hostname;

    my $ret = UBOS::LetsEncrypt::makeCertificateNoRenew( $hostname );
    return $ret;
}

# === Manifest checking routines from here ===

##
# Check the part of an app manifest that deals with this role.
# $roleName: name of this role, passed for efficiency
# $installable: the installable whose manifest is being checked
# $jsonFragment: the JSON fragment that deals with this role
# $retentionBuckets: keep track of retention buckets, so there's no overlap
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# $vars: the Variables object that knows about symbolic names and variables
sub checkAppManifestForRole {
    my $self                 = shift;
    my $roleName             = shift;
    my $installable          = shift;
    my $jsonFragment         = shift;
    my $retentionBuckets     = shift;
    my $skipFilesystemChecks = shift;
    my $vars                 = shift;

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

    $self->checkInstallableManifestForRole( $roleName, $installable, $jsonFragment, $retentionBuckets, $skipFilesystemChecks, $vars );
}

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
