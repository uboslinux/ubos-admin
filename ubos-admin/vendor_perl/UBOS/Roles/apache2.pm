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
        if( $site->isTls ) {
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
        my $siteWellKnownDir  = "$sitesWellknownDir/$siteId/.well-known";

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
    my $siteWellKnownDir  = "$sitesWellknownDir/$siteId/.well-known";
    my $sslDir            = $site->vars()->getResolve( 'apache2.ssldir' );

    unless( -d $siteDocumentRoot ) {
        error( 'Placeholder site', $placeholderName, 'does not exist at', $siteDocumentRoot );
    }

    if( $site->isTls ) {
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


    # Determine where TLS key and cert are
    my( $keyFile, $crtFile );

    my $tlsNow = $site->isTls();
    if( $tlsNow ) {
        if( $site->isLetsEncryptTls() ) {
            # Site.pm has unstashed the cert if it needed to be unstashed
            if( UBOS::LetsEncrypt::isCertificateLive( $hostname )) {
                ( $keyFile, $crtFile ) = UBOS::LetsEncrypt::getLiveKeyAndCertificateFiles( $hostname );

            } else {
                $tlsNow = 0; # we don't have LetsEncrypt certs yet, so we set it up as http
            }

        } else {
            $keyFile = "$sslDir/$siteId.key";
            $crtFile = "$sslDir/$siteId.crt";
        }
    }

    if( $tlsNow ) {
        $siteFileContent .= <<CONTENT;

<VirtualHost *:80>
$serverDeclaration

    RewriteEngine On
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
    # This also works for wildcard hostnames
</VirtualHost>
CONTENT

    } else {
        $port = 80;
    }

    $siteFileContent .= <<CONTENT;

<VirtualHost *:$port>
$serverDeclaration

    DocumentRoot "$siteDocumentRoot"
    Options -Indexes

    Alias /\.well-known/ $siteWellKnownDir/

    AliasMatch ^/_common/css/([-a-z0-9]*\.css)\$ /srv/http/_common/css/\$1
    AliasMatch ^/_common/images/([-a-z0-9]*\.png)\$ /srv/http/_common/images/\$1

    AliasMatch ^.*\$ "$siteDocumentRoot/index.html"

CONTENT

    if( $tlsNow ) {
        $siteFileContent .= <<CONTENT;

    SSLEngine on

    SSLCertificateKeyFile $keyFile
    SSLCertificateFile $crtFile
CONTENT
        if( $site->tlsCaCert ) {
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

    my $siteFragmentDir          = UBOS::Host::vars()->getResolve( 'apache2.sitefragmentdir' );
    my $defaultSiteFragmentDir   = UBOS::Host::vars()->getResolve( 'apache2.defaultsitefragmentdir' );
    my $sitesDocumentRootDir     = UBOS::Host::vars()->getResolve( 'apache2.sitesdir' );
    my $sitesWellknownDir        = UBOS::Host::vars()->getResolve( 'apache2.siteswellknowndir' );
    my $appConfigFragmentDir     = UBOS::Host::vars()->getResolve( 'apache2.appconfigfragmentdir' );
    my $tmpDir                   = UBOS::Host::tmpdir();
    my $siteId                   = $site->siteId;
    my $hostname                 = $site->hostname;
    my $port                     = $site->port;
    my $appConfigFilesDir        = "$appConfigFragmentDir/$siteId";
    my $siteFile                 = ( '*' eq $hostname ) ? "$defaultSiteFragmentDir/any.conf" : "$siteFragmentDir/$siteId.conf";
    my $siteDocumentRoot         = "$sitesDocumentRootDir/$siteId";
    my $siteWellKnownDir         = "$sitesWellknownDir/$siteId/.well-known";
    my $serverDeclaration        = ( '*' eq $hostname ) ? '# Hostname * (any)' : "    ServerName $hostname";
    my $webfingerProxiesDir      = $site->vars()->getResolve( 'apache2.webfingerproxiesdir',           "/ubos/http/webfinger-proxies" );
    my $siteWebfingerProxiesFile = $site->vars()->getResolve( 'site.apache2.sitewebfingerproxiesfile', "/ubos/http/webfinger-proxies/$siteId" );
    my $sslDir                   = $site->vars()->getResolve( 'apache2.ssldir' );

    my $wellknowns = $site->wellknowns();

    unless( -d $siteDocumentRoot ) {
        UBOS::Utils::mkdirDashP( $siteDocumentRoot );
    }
    unless( -d $sitesWellknownDir ) {
        UBOS::Utils::mkdirDashP( $sitesWellknownDir );
    }
    unless( -d $siteFragmentDir ) {
        UBOS::Utils::mkdirDashP( $siteFragmentDir );
    }

    foreach my $wellknownKey ( keys %$wellknowns ) {
        my $wellknownValue = $wellknowns->{$wellknownKey};
        if( exists( $wellknownValue->{value} ) && defined( $wellknownValue->{value} )) {
            UBOS::Utils::saveFile( "$siteWellKnownDir/$wellknownKey", $wellknownValue->{value} );
        }
    }

    # Determine where TLS key and cert are
    my( $keyFile, $crtFile );

    if( $site->isTls() ) {
        if( $site->isLetsEncryptTls() ) {
            ( $keyFile, $crtFile ) = UBOS::LetsEncrypt::getLiveKeyAndCertificateFiles( $hostname );

        } else {
            $keyFile = "$sslDir/$siteId.key";
            $crtFile = "$sslDir/$siteId.crt";
        }
    }

    my $siteFileContent = <<CONTENT;
#
# Apache config fragment for site $siteId at host $hostname
#
# Generated automatically, do not modify.
#
CONTENT

    if( $site->isTls ) {
        $siteFileContent .= <<CONTENT;

<VirtualHost *:80>
$serverDeclaration

    RewriteEngine On
    RewriteRule ^(.*)\$ https://%{HTTP_HOST}\$1 [R=301,L]
    # This also works for wildcard hostnames
</VirtualHost>
CONTENT

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
            php_admin_value open_basedir $siteDocumentRoot/:/tmp/:$tmpDir/:/ubos/share/:/srv/http/
        </IfModule>
    </Directory>
CONTENT
    # Specify both /tmp and $tmpDir, because some apps internally use /tmp

    if( $site->isTls ) {
        $siteFileContent .= <<CONTENT;

    SSLEngine on

    SSLCertificateKeyFile $keyFile
    SSLCertificateFile $crtFile
CONTENT
        if( $site->tlsCaCert ) {
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

    foreach my $wellknownKey ( keys %$wellknowns ) {
        my $wellknownValue = $wellknowns->{$wellknownKey};
        if( exists( $wellknownValue->{location} ) && defined( $wellknownValue->{location} )) {
            my $escapedKey = quotemeta( $wellknownKey );
            my $location   = $wellknownValue->{location};
            my $httpStatus = $wellknownValue->{status};

            $siteFileContent .= <<CONTENT;
    RedirectMatch $httpStatus ^/\.well-known/$escapedKey\$ $location
CONTENT
        }
    }

    # repeat those
    foreach my $toplevel ( qw( robots.txt sitemap.xml favicon.ico )) {
        if( exists( $wellknowns->{$toplevel} )) {
            my $wellknownValue = $wellknowns->{$toplevel};
            if( exists( $wellknownValue->{value} ) && defined( $wellknownValue->{value} )) {
                my $escapedToplevel = $toplevel;
                $escapedToplevel =~ s!\.!\\.!g;
                $siteFileContent .= <<CONTENT;
    AliasMatch ^/$escapedToplevel\$ $siteWellKnownDir/$toplevel
CONTENT
            }
        }
    }

    if(    exists( $wellknowns->{webfinger} )
        && exists( $wellknowns->{webfinger}->{proxies} )
        && @{$wellknowns->{webfinger}->{proxies}} )
    {
        $siteFileContent .= <<CONTENT;
    ScriptAliasMatch ^/\.well-known/webfinger /usr/share/ubos/cgi-bin/merge-webfingers.pl
CONTENT

        unless( -d $webfingerProxiesDir ) {
            UBOS::Utils::mkdirDashP( $webfingerProxiesDir );
        }
        UBOS::Utils::saveFile( $siteWebfingerProxiesFile, join( "\n", @{$wellknowns->{webfinger}->{proxies}} ));
    }

    $siteFileContent .= <<CONTENT;
    Alias /\.well-known/ $siteWellKnownDir/

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

    my $siteDocumentDir          = $site->vars()->getResolve( 'site.apache2.sitedocumentdir' );
    my $siteTorDir               = $site->vars()->getResolve( 'site.apache2.sitetordir' );
    my $siteTorFragmentFile      = $site->vars()->getResolve( 'site.apache2.sitetorfragmentfile' );
    my $siteFragmentDir          = UBOS::Host::vars()->getResolve( 'apache2.sitefragmentdir' );
    my $defaultSiteFragmentDir   = UBOS::Host::vars()->getResolve( 'apache2.defaultsitefragmentdir' );
    my $sitesWellknownDir        = UBOS::Host::vars()->getResolve( 'apache2.siteswellknowndir' );
    my $appConfigFragmentDir     = UBOS::Host::vars()->getResolve( 'apache2.appconfigfragmentdir' );
    my $siteId                   = $site->siteId;
    my $hostname                 = $site->hostname;
    my $appConfigFilesDir        = "$appConfigFragmentDir/$siteId";
    my $siteFile                 = ( '*' eq $hostname ) ? "$defaultSiteFragmentDir/any.conf" : "$siteFragmentDir/$siteId.conf";
    my $siteWellKnownParentDir   = "$sitesWellknownDir/$siteId"; # delete .well-known, its content, and parent dir
    my $siteWebfingerProxiesFile = $site->vars()->getResolve( 'site.apache2.sitewebfingerproxiesfile', "/ubos/http/webfinger-proxies/$siteId" );
    my $sslDir                   = $site->vars()->getResolve( 'apache2.ssldir' );

    trace( 'apache2::removeSite', $siteId, $doIt );

    if( $doIt ) {
        UBOS::Utils::deleteFile( $siteFile );

        if( -d $appConfigFilesDir ) {
            UBOS::Utils::rmdir( $appConfigFilesDir );
        }
        if( -d $siteWellKnownParentDir ) {
            UBOS::Utils::deleteRecursively( $siteWellKnownParentDir );
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
        if( -e $siteWebfingerProxiesFile ) {
            UBOS::Utils::deleteFile( $siteWebfingerProxiesFile );
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
# Save the TLS key and certificate in this Site to the default SSL directory
# for this Role. On this level, does nothing.
# $site: the Site
# return: success or fail
sub saveTlsKeyAndCertificate {
    my $self     = shift;
    my $site     = shift;

    my $siteId = $site->siteId;
    my $sslDir = $site->vars()->getResolve( 'apache2.ssldir' );

    my $uid = 0;  # avoid overwrite by http
    my $gid = UBOS::Utils::getGid( 'http' );

    UBOS::Utils::saveFile( "$sslDir/$siteId.key", $site->tlsKey, 0040, $uid, $gid );
    UBOS::Utils::saveFile( "$sslDir/$siteId.crt", $site->tlsCert, 0040, $uid, $gid );
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

        if( defined( $jsonFragment->{wellknown} )) {
            # Compare with Site JSON checking in Site.pm -- partially similar
            unless( ref( $jsonFragment->{wellknown} ) eq 'HASH' ) {
                $installable->myFatal( "roles section: role $roleName: field 'wellknown' is not a JSON object" );
            }

            foreach my $wellknownKey ( keys %{$jsonFragment->{wellknown}} ) {
                unless( $wellknownKey =~ m!^[-_.a-zA-Z0-9]+$! ) {
                    $installable->myFatal( "roles section: role $roleName: field 'wellknown' contains invalid key: " . $wellknownKey );
                }
                my $wellknownValue = $jsonFragment->{wellknown}->{$wellknownKey};

                if( 'robots.txt' eq $wellknownKey || 'webfinger' eq $wellknownKey ) {
                    if( exists( $wellknownValue->{value} )) {
                        $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' may not specify value" );
                    }
                    if( exists( $wellknownValue->{location} )) {
                        $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' may not specify location" );
                    }
                    if( exists( $wellknownValue->{status} )) {
                        $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' may not specify status" );
                    }

                    if( 'robots.txt' eq $wellknownKey ) {
                        if( exists( $wellknownValue->{proxy} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' may not specify proxy" );
                        }

                        foreach my $field ( qw( allow disallow )) {
                            if( exists( $wellknownValue->{$field} )) {
                                unless( ref( $wellknownValue->{$field} ) eq 'ARRAY' ) {
                                    $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey', sub-entry '$field' is not an array" );
                                }
                                if( @{$wellknownValue->{$field}} == 0) {
                                    $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey', sub-entry '$field' must have at least one entry" );
                                }
                                foreach my $allowDisallow ( @{$wellknownValue->{$field}} ) {
                                    if( ref( $allowDisallow )) {
                                        $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey', sub-entry '$field' must be an array of strings" );
                                    }
                                    unless( $allowDisallow =~ m!^/\S*$! ) {
                                        $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey', sub-entry '$field' contains invalid value: " . $allowDisallow );
                                    }
                                }
                            }
                        }
                    }
                    if( 'webfinger' eq $wellknownKey ) {
                        foreach my $field ( qw( allow disallow )) {
                            if( exists( $wellknownValue->{$field} )) {
                                $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' must not contain: " . $field );
                            }
                        }
                        unless( exists( $wellknownValue->{proxy} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' must contain proxy" );
                        }
                        if( ref( exists( $wellknownValue->{proxy} )) || $wellknownValue->{proxy} !~ m!https?://! ) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey', sub-entry 'proxy' must be an HTTP or HTTPS URL" );
                        }
                    }

                } else { # not robots.txt or webfinger
                    foreach my $field ( qw( allow disallow proxy )) {
                        if( exists( $wellknownValue->{$field} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' must not contain: " . $field );
                        }
                    }

                    if( exists( $wellknownValue->{value} )) {
                        if( ref( $wellknownValue->{value} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey', value is not a string" );
                        }
                        if( exists( $wellknownValue->{location} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' must not define both value and location" );
                        }
                        if( exists( $wellknownValue->{encoding} ) && $wellknownValue->{encoding} ne 'base64' ) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' specifies invalid encoding: " . $wellknownValue->{encoding} );
                        }
                        if( exists( $wellknownValue->{status} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' may not specify status" );
                        }

                    } elsif( exists( $wellknownValue->{location} )) {
                        if( ref( $wellknownValue->{value} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey', location is not a string" );
                        }
                        if( exists( $wellknownValue->{encoding} )) {
                            $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' must not specify both location and encoding" );
                        }
                        if( exists( $wellknownValue->{status} )) {
                            unless( $wellknownValue->{status} =~ m!^3\d\d$! ) {
                                $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' has invalid status: " . $wellknownValue->{status} );
                            }
                        }

                    } else {
                        $installable->myFatal( "roles section: role $roleName: field 'wellknown' entry '$wellknownKey' specifies neither value nor location" );
                    }
                }
            }
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
    if( $jsonFragment->{status} ) {
        my $codeDir = $vars->getResolve( 'package.codedir' );

        unless( ref( $jsonFragment->{phpmodules} ) eq 'HASH' ) {
            $installable->myFatal( "roles section: role $roleName: status is not a hash" );
        }
        unless( exists( $jsonFragment->{status}->{type} )) {
            $installable->myFatal( "roles section: role $roleName: status: field 'type' must exist" );
        }
        if( ref( $jsonFragment->{status}->{type} )) {
            $installable->myFatal( "roles section: role $roleName: status: field 'type' must be string" );
        }
        if( $jsonFragment->{status}->{type} ne 'perlscript' && $jsonFragment->{status}->{type} ne 'exec' ) {
            $installable->myFatal( "roles section: role $roleName: status has unknown or disallowed type"
                                   . ". Allowed types are: perlscript and exec." );
        }
        unless( $jsonFragment->{status}->{source} ) {
            $installable->myFatal( "roles section: role $roleName: status must specify source" );
        }
        if( ref( $jsonFragment->{status}->{source} )) {
            $installable->myFatal( "roles section: role $roleName: status must be string" );
        }
        if( !$skipFilesystemChecks && !UBOS::Installable::validFilename( $codeDir, $vars->replaceVariables( $jsonFragment->{status}->{source} ))) {
            $installable->myFatal( "roles section: role $roleName: status has invalid source: " . $jsonFragment->{status}->{source} );
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
