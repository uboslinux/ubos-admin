#!/usr/bin/perl
#
# Represents a Site, aka Virtual Host.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Site;

use UBOS::AppConfiguration;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;
use JSON;
use MIME::Base64;

use fields qw( json manifestFileReader appConfigs vars);

my $WILDCARDHOSTNAME = "__wildcard";

##
# Constructor.
# $json: JSON object containing Site JSON
# $fillInTemplate: usually false. If true, instead of complaining about missing siteId and
#       appConfigIds and the like, silently assign new values
# $manifestFileReader: pointer to a method that knows how to read manifest files
# return: Site object
sub new {
    my $self               = shift;
    my $json               = shift;
    my $fillInTemplate     = shift || 0;
    my $manifestFileReader = shift || \&UBOS::Host::defaultManifestFileReader;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    if( exists( $json->{ssl} )) {
        # migrate
        $json->{tls} = $json->{ssl};
        delete $json->{ssl};
    }
    $self->{json}               = $json;
    $self->{manifestFileReader} = $manifestFileReader;

    unless( $self->_checkJson( $fillInTemplate )) {
        return undef;
    }

    return $self;
}

##
# Obtain the site's id.
# return: string
sub siteId {
    my $self = shift;

    return $self->{json}->{siteid};
}

##
# Obtain the site JSON
# return: site JSON
sub siteJson {
    my $self = shift;

    return $self->{json};
}

##
# Obtain the public components of the site JSON
# return: public site JSON
sub publicSiteJson {
    my $self = shift;

    return $self->_siteJsonWithout( 1, 1 );
}

##
# Obtain the Site JSON but without TLS info
# return: JSON without TLS info
sub siteJsonWithoutTls {
    my $self = shift;

    return $self->_siteJsonWithout( 1, 0 );
}

##
# Helper method to return subsets of the Site JSON. Also, do not return
# values for customization points marked as private.
# $noTls: if 1, do not return TLS info
# $noAdminCredential: if 1, do not return site admin credential
sub _siteJsonWithout {
    my $self              = shift;
    my $noTls             = shift;
    my $noAdminCredential = shift;

    my $json = $self->{json};
    my $ret  = {};

    $ret->{siteid}   = $json->{siteid};
    $ret->{hostname} = $json->{hostname};

    $ret->{admin}->{userid}   = $json->{admin}->{userid};
    $ret->{admin}->{username} = $json->{admin}->{username};
    $ret->{admin}->{email}    = $json->{admin}->{email};

    unless( $noAdminCredential ) {
        $ret->{admin}->{credential} = $json->{admin}->{credential};
    }
    unless( $noTls ) {
        $ret->{tls} = $json->{tls}; # by reference is fine
    }

    if( exists( $json->{wellknown} )) {
        $ret->{wellknown} = $json->{wellknown}; # by reference is fine
    }
    $self->appConfigs(); # make sure cache exists
    foreach my $appConfig ( @{$self->{appConfigs}} ) {
        my $appConfigRet = {};

        $appConfigRet->{appconfigid} = $appConfig->appConfigId;
        if( exists( $appConfig->{json}->{context} )) {
            $appConfigRet->{context} = $appConfig->{json}->{context};
        }
        if( exists( $appConfig->{json}->{isdefault} )) {
            $appConfigRet->{isdefault} = $appConfig->{json}->{isdefault};
        }
        $appConfigRet->{appid} = $appConfig->{json}->{appid};
        if( exists( $appConfig->{json}->{accessoryids} )) {
            $appConfigRet->{accessoryids} = $appConfig->{json}->{accessoryids}; # by reference is fine
        }
        if( exists( $appConfig->{json}->{customizationpoints} )) {
            foreach my $custPointInstallableName ( keys %{$appConfig->{json}->{customizationpoints}} ) {
                my $custPointInstallableJson = $appConfig->{json}->{customizationpoints}->{$custPointInstallableName};
                if( defined( $custPointInstallableJson )) {
                    foreach my $custPointName ( keys %{$custPointInstallableJson} ) {
                        my $custPointDefJson = $appConfig->customizationPointDefinition( $custPointInstallableName, $custPointName );
                        unless( exists( $custPointDefJson->{private} ) && $custPointDefJson->{private} ) {
                            $appConfigRet->{customizationpoints}->{$custPointInstallableName}->{$custPointName}
                                    = $custPointInstallableJson->{$custPointName};
                        }
                    }
                }
            }
        }

        push @{$ret->{appconfigs}}, $appConfigRet;
    }

    return $ret;
}

##
# Obtain the site's host name.
# return: string
sub hostname {
    my $self = shift;

    return $self->{json}->{hostname} || "-not-assigned-yet";
}

##
# Obtain the site's host name, or, if it is *, a replacement that looks like a real hostname
# return: string
sub hostnameorwildcard {
    my $self = shift;

    my $ret = $self->hostname();
    if( $ret eq '*' ) {
        $ret = $WILDCARDHOSTNAME;
    }
    return $ret;
}

##
# Obtain the site's host name, or, if it is *, its system hostname
# return: string
sub hostnameorsystemhostname {
    my $self = shift;

    my $ret = $self->hostname();
    if( $ret eq '*' ) {
        $ret = UBOS::Host::hostname();
    }
    return $ret;
}

##
# Obtain the site's port.
# return: 80 or 443
sub port {
    my $self = shift;

    if( $self->hasTls() ) {
        return 443;
    } else {
        return 80;
    }
}

##
# Obtain the site's protocol.
# return: http or https
sub protocol {
    my $self = shift;

    if( $self->hasTls() ) {
        return 'https';
    } else {
        return 'http';
    }
}

##
# Obtain the Variables object for the Site
# return: the Variables object
sub vars {
    my $self = shift;

    unless( $self->{vars} ) {
        my $siteId    = $self->siteId();
        my $adminJson = $self->{json}->{admin};

        $self->{vars} = UBOS::Variables->new(
                    "Site=$siteId",
                    {
                        "site" => {
                            "hostname"                 => $self->hostname(),
                            "hostnameorwildcard"       => $self->hostnameorwildcard(),
                            "hostnameorsystemhostname" => $self->hostnameorsystemhostname(),
                            "port"                     => $self->port(),
                            "protocol"                 => $self->protocol(),
                            "protocolport"             => ( 'http' eq $self->protocol() ? 80 : 443 ),
                            "siteid"                   => $siteId,
                            "admin" => {
                                "userid"               => $adminJson->{userid},
                                "username"             => $adminJson->{username},
                                "credential"           => $adminJson->{credential},
                                "email"                => $adminJson->{email}
                            }
                        }
                    },
                    'UBOS::Host' );
    }
    return $self->{vars};
}

##
# Determine whether this site is protected by SSL/TLS
# return: 0 or 1
sub hasTls {
    my $self = shift;

    my $json = $self->{json};
    if( !defined( $json->{tls} )) {
        return 0;
    }
    if( defined( $json->{tls}->{key} )) {
        return 1;
    }
    if( defined( $json->{tls}->{letsencrypt} ) && $json->{tls}->{letsencrypt} ) {
        return 1;
    }
    return 0;
}

##
# Determine whether to use letsencrypt for this site
# return: 0 or 1
sub hasLetsEncryptTls {
    my $self = shift;

    my $json = $self->{json};
    if( !defined( $json->{tls} )) {
        return 0;
    }
    return defined( $json->{tls}->{letsencrypt} ) ? 1 : 0;
}

##
# Determine whether we already have a letsencrypt certificate for this site
# return: 0 or 1
sub hasLetsEncryptCert {
    my $self = shift;

    my $ret         = 0;
    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $role->hasLetsEncryptCert( $self )) {
            return 1;
        }
    }
    return 0;
}

##
# Reset the letsencrypt flag, in case obtaining the certificate failed.
sub unsetLetsEncryptTls {
    my $self = shift;

    delete $self->{json}->{tls}; # delete the whole tls subtree
}

##
# Obtain the TLS key, if any has been provided.
# return: the TLS key
sub tlsKey {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{tls} )) {
        return $json->{tls}->{key};
    } else {
        return undef;
    }
}

##
# Obtain the TLS certificate, if any has been provided.
# return: the TLS certificate
sub tlsCert {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{tls} )) {
        return $json->{tls}->{crt};
    } else {
        return undef;
    }
}

##
# Obtain the TLS certificate chain to be used with clients, if any has been provided.
sub tlsCaCert {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{tls} )) {
        return $json->{tls}->{cacrt};
    } else {
        return undef;
    }
}

##
# Delete the TLS information from this site.
sub deleteTlsInfo {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{tls} )) {
        delete $json->{tls};
    }
}

##
# Set a new key and certificate for this site
# $key the new key
# $crt the new cert
sub setTlsKeyAndCert {
    my $self = shift;
    my $key  = shift;
    my $crt  = shift;

    $self->{json}->{tls}->{key} = $key;
    $self->{json}->{tls}->{crt} = $crt;
}

##
# Determine whether this site should run under tor
# return: 1 if it should
sub isTor {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{tor} )) {
        return 1;
    } else {
        return 0;
    }
}

##
# Obtain the tor private key for this site
# return: private key, or undef
sub torPrivateKey {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{tor} ) && defined( $json->{tor}->{privatekey} )) {
        return $json->{tor}->{privatekey};
    } else {
        return undef;
    }
}

##
# Obtain the site's robots.txt file content, if any has been provided.
# return: robots.txt content
sub robotsTxt {
    my $self = shift;

    my $json = $self->{json};
    my $robotsTxt;

    if( exists( $json->{wellknown} )) {
        if( exists( $json->{wellknown}->{robotstxt} )) {
            trace( 'Have robots.txt in site json for', $self->siteId );
            return $json->{wellknown}->{robotstxt};
        }
        if( exists( $json->{wellknown}->{robotstxtprefix} )) {
            $robotsTxt = $json->{wellknown}->{robotstxtprefix} . "\n";
        }
    }
    my $thisFirst = "User-Agent: *\n";
    foreach my $appConfig ( @{$self->appConfigs} ) {
        my $app     = $appConfig->app();
        my $context = $appConfig->context();

        foreach my $allow ( $app->robotstxtAllow() ) {
            $robotsTxt .= $thisFirst . "Allow: $context$allow\n";
            $thisFirst  = '';
        }
        foreach my $disallow ( $app->robotstxtDisallow() ) {
            $robotsTxt .= $thisFirst . "Disallow: $context$disallow\n";
            $thisFirst  = '';
        }
    }
    if( $robotsTxt ) {
        trace( 'Constructed robots.txt for site', $self->siteId );
        return $robotsTxt;
    } else {
        return undef;
    }
}

##
# Obtain the site's sitemap.xml file content, if any has been provided.
# return: robots.txt content
sub sitemapXml {
    my $self = shift;

    my $json = $self->{json};
    if( exists( $json->{wellknown} ) && exists( $json->{wellknown}->{sitemapxml} )) {
        return $self->{json}->{wellknown}->{sitemapxml};
    } else {
        return undef;
    }
}

##
# Obtain the site's favicon.ico file content, if any has been provided.
# return: binary content of favicon.ico
sub faviconIco {
    my $self = shift;

    my $json = $self->{json};
    if( exists( $json->{wellknown} ) && exists( $json->{wellknown}->{faviconicobase64} ) && $json->{wellknown}->{faviconicobase64} ) {
        return decode_base64( $self->{json}->{wellknown}->{faviconicobase64} );
    }
    return undef;
}

##
# Obtain information about the site administrator.
# return: hash from the Site JSON
sub obtainSiteAdminHash {
    my $self = shift;

    return $self->{json}->{admin};
}

##
# Obtain the AppConfigurations at this Site.
# return: array of AppConfiguration objects
sub appConfigs {
    my $self = shift;

    unless( defined( $self->{appConfigs} )) {
        my $jsonAppConfigs = $self->{json}->{appconfigs};
        $self->{appConfigs} = [];
        foreach my $current ( @$jsonAppConfigs ) {
            push @{$self->{appConfigs}}, UBOS::AppConfiguration->new( $current, $self, $self->{manifestFileReader} );
        }
    }
    return $self->{appConfigs};
}

##
# Obtain an AppConfiguation with a particular appconfigid on this Site.
# return: the AppConfiguration, or undef
sub appConfig {
    my $self        = shift;
    my $appconfigid = shift;

    foreach my $appConfig ( @{$self->appConfigs} ) {
        if( $appconfigid eq $appConfig->appConfigId ) {
            return $appConfig;
        }
    }
    return undef;
}

##
# Obtain an AppConfiguration with a particular context path on this Site, or undef.
# $context: the context path to look for
# return: the AppConfiguration, or undef
sub appConfigAtContext {
    my $self    = shift;
    my $context = shift;

    foreach my $appConfig ( @{$self->appConfigs} ) {
        unless( defined( $appConfig->context )) {
            next; # Non-web apps
        }
        if( $context eq $appConfig->context ) {
            return $appConfig;
        }
    }
    return undef;
}

##
# Print this Site's SiteId
sub printSiteId {
    my $self = shift;

    print $self->siteId . "\n";
}

##
# Print this Site in varying levels of detail
# $detail: the level of detail
sub print {
    my $self   = shift;
    my $detail = shift || 2;

    if( $detail > 1 ) {
        print 'Site ';
    }
    print $self->hostname;
    if( $self->hasTls ) {
        print ' (TLS)';
    }
    if( $detail > 2 ) {
        print ' (' . $self->siteId . ')';
    }
    print ':';
    if( $detail <= 1 ) {
        my $nAppConfigs = @{$self->appConfigs};
        if( $nAppConfigs == 1 ) {
            print ' 1 app';
        } elsif( $nAppConfigs ) {
            print " $nAppConfigs apps";
        } else {
            print ' no apps';
        }
    }
    print "\n";

    if( $detail > 1 ) {
        foreach my $isDefault ( 1, 0 ) {
            my $hasDefault   = grep { $_->isDefault } @{$self->appConfigs};
            my $defaultSpace = $hasDefault ? '         ' : '';

            foreach my $appConfig ( sort { $a->appConfigId cmp $b->appConfigId } @{$self->appConfigs} ) {
                if( ( $isDefault && $appConfig->isDefault ) || ( !$isDefault && !$appConfig->isDefault )) {
                    print '    ';

                    my $context = $appConfig->context;
                    if( $isDefault && $appConfig->isDefault ) {
                        print '(default)';
                    } else {
                        print $defaultSpace;
                    }
                    print ' ';
                    if( $context ) {
                        print $context;
                    } elsif( defined( $context )) {
                        print '<root>';
                    } else {
                        print '<none>';
                    }
                    if( $detail > 2 ) {
                        print ' ('. $appConfig->appConfigId . ')';
                    }
                    if( $detail < 3 ) {
                        print ': ' . $appConfig->app->packageName;
                        my $nAcc = $appConfig->accessories();
                        if( $nAcc == 1 ) {
                            print ' (1 accessory)';
                        } elsif( $nAcc ) {
                            print " ($nAcc accessories)";
                        }
                        print "\n";
                    } else {
                        print "\n";

                        my $custPoints = $appConfig->customizationPoints;
                        foreach my $installable ( $appConfig->installables ) {
                            print '          ';
                            if( $installable == $appConfig->app ) {
                                print 'app:      ';
                            } else {
                                print 'accessory: ';
                            }
                            print $installable->packageName . "\n";
                            if( $custPoints ) {
                                my $installableCustPoints = $custPoints->{$installable->packageName};
                                if( defined( $installableCustPoints )) {
                                    foreach my $custPointName ( sort keys %$installableCustPoints ) {
                                        my $custPointValueStruct = $installableCustPoints->{$custPointName};
                                        my $value = $custPointValueStruct->{value};

                                        if( length( $value ) < 60 ) {
                                            print '                     customizationpoint ' . $custPointName . ': ' . $value . "\n";
                                        } else {
                                            print '                     customizationpoint ' . $custPointName . ': ' . substr( $value, 0, 60 ) . "...\n";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

##
# Print this Site in the brief format
sub printBrief {
    my $self = shift;

    return $self->print( 1 );
}

##
# Print this Site in the detailed format
sub printDetail {
    my $self = shift;

    return $self->print( 3 );
}

##
# Add names of application packages that are required to run this site.
# $packages: hash of packages
sub addInstallablesToPrerequisites {
    my $self      = shift;
    my $packages  = shift;

    # This may be invoked before the Application JSON of some of the applications is
    # available, so we cannot access $appConfig->app for example.

    my $jsonAppConfigs = $self->{json}->{appconfigs};
    foreach my $jsonAppConfig ( @$jsonAppConfigs ) {
        my $appId = $jsonAppConfig->{appid};

        $packages->{$appId} = $appId;

        if( defined( $jsonAppConfig->{accessoryids} )) {
            foreach my $accId ( @{$jsonAppConfig->{accessoryids}} ) {
                $packages->{$accId} = $accId;
            }
        }
    }

    1;
}

##
# Add names of dependent packages that are required to run this site.
# $packages: hash of packages
sub addDependenciesToPrerequisites {
    my $self      = shift;
    my $packages  = shift;

    my $rolesOnHost = UBOS::Host::rolesOnHost();
    foreach my $appConfig ( @{$self->appConfigs} ) {
        foreach my $installable ( $appConfig->installables ) {
            foreach my $roleName ( keys %$rolesOnHost ) {
                my $roleJson = $installable->{json}->{roles}->{$roleName};
                if( $roleJson ) {
                    my $depends = $roleJson->{depends};
                    if( $depends ) {
                        foreach my $depend ( @$depends ) {
                            $packages->{$depend} = $depend;
                        }
                    }
                }
            }
        }
    }
    if( $self->hasLetsEncryptTls ) {
        $packages->{'certbot-apache'} = 'certbot-apache';
    }

    1;
}

##
# Determine whether, on a host that chooses to support a particular Role,
# this Site needs that Role
# $role: the Role to check for
# return: true or false
sub needsRole {
    my $self = shift;
    my $role = shift;

    if( $role->isAlwaysNeeded() ) {
        return 1;
    }

    my $appConfigs = $self->appConfigs();
    foreach my $appConfig ( @$appConfigs ) {
        if( $appConfig->needsRole( $role )) {
            return 1;
        }
    }
    return 0;
}

##
# Before deploying, check whether this Site would be deployable
# If not, this invocation never returns
# return: success or fail
sub checkDeployable {
    my $self = shift;

    my $ret = $self->_deployOrCheck( 0 );

    $self->clearCaches(); # placeholder information may have been put in certain places, e.g. MySQL database info

    return $ret;
}

##
# Deploy this Site
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub deploy {
    my $self     = shift;
    my $triggers = shift;

    trace( 'Site', $self->siteId, '->deploy' );

    return $self->_deployOrCheck( 1, $triggers );
}

##
# Deploy this Site, or just check whether it is deployable. Both functions
# share the same code, so the checks get updated at the same time as the
# actual deployment.
# $doIt: if 1, deploy; if 0, only check
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub _deployOrCheck {
    my $self     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    trace( 'Site::_deployOrCheck', $doIt, $self->siteId );

    if( $doIt ) {
        UBOS::Host::siteDeploying( $self );
    }

    my $ret = 1;
    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->setupSiteOrCheck( $self, $doIt, $triggers );
        }
    }
    if( $doIt && $self->hasLetsEncryptTls() && !$self->hasLetsEncryptCert() ) {
        my $success = 1;
        foreach my $role ( @rolesOnHost ) {
            $success &= $role->obtainLetsEncryptCertificate( $self );
        }
        unless( $success ) {
            warning( 'Failed to obtain letsencrypt certificate for site', $self->hostname, '(', $self->siteId, '). Deploying site without TLS.' );
            $self->unsetLetsEncryptTls;
        }
        $ret &= $success;
    }
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->deployOrCheck( $doIt, $triggers );
    }
    if( $doIt ) {
        if( exists( $self->{json}->{tor} )) {
            # This is not such a great place where to restart a daemon, but we need it to
            # generate the key before continuing
            UBOS::Tor::restart();

            my $siteTorDir = $self->vars()->getResolve( 'site.apache2.sitetordir' );
            if( -e "$siteTorDir/private_key" ) {
                my $privateKey = UBOS::Utils::slurpFile( "$siteTorDir/private_key" );
                $privateKey =~ s!^\s+!!;
                $privateKey =~ s!\s+$!!;
                $self->{json}->{tor}->{privatekey} = $privateKey;
            }
            if( -e "$siteTorDir/hostname" ) {
                my $hostname = UBOS::Utils::slurpFile( "$siteTorDir/hostname" );
                $hostname =~ s!^\s+!!;
                $hostname =~ s!\s+$!!;
                $self->{json}->{hostname} = $hostname;
            }
            delete $self->{vars}; # will regenerate with correct hostname when needed
        }
        UBOS::Host::siteDeployed( $self );
    }
    return $ret;
}

##
# Prior to undeploying, check whether this Site can be undeployed
# If not, this invocation never returns
# return: success or fail
sub checkUndeployable {
    my $self = shift;

    return $self->_undeployOrCheck( 0 );
}

##
# Undeploy this Site
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub undeploy {
    my $self     = shift;
    my $triggers = shift;

    return $self->_undeployOrCheck( 1, $triggers );
}

##
# Undeploy this Site, or just check whether it is undeployable. Both functions
# share the same code, so the checks get updated at the same time as the
# actual undeployment.
# $doIt: if 1, undeploy; if 0, only check
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub _undeployOrCheck {
    my $self     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    trace( 'Site::_undeployOrCheck', $doIt, $self->siteId );

    if( $doIt ) {
        UBOS::Host::siteUndeploying( $self );
    }
    my $ret = 1;
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->undeployOrCheck( $doIt, $triggers );
    }

    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            if( $doIt ) {
                trace( '_undeployOrCheck', $self->siteId, $role->name );
            }
            $ret &= $role->removeSite( $self, $doIt, $triggers );
        }
    }

    if( $doIt ) {
        UBOS::Host::siteUndeployed( $self );
    }

    return $ret;
}

##
# Set up a placeholder for this new Site: "coming soon"
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub setupPlaceholder {
    my $self     = shift;
    my $triggers = shift;

    trace( 'Site::setupPlaceholder', $self->siteId );

    my $ret = 1;
    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->setupPlaceholderSite( $self, 'maintenance', $triggers );
        }
    }
    return $ret;
}

##
# Suspend this Site: replace Site with an "updating" placeholder or such
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub suspend {
    my $self     = shift;
    my $triggers = shift;

    trace( 'Site::suspend', $self->siteId );

    my $ret = 1;
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->suspend( $triggers );
    }

    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->suspendSite( $self, $triggers );
        }
    }
    return $ret;
}

##
# Resume this Site from suspension
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub resume {
    my $self     = shift;
    my $triggers = shift;

    trace( 'Site::resume', $self->siteId );

    my $ret = 1;
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->resume( $triggers );
    }

    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->resumeSite( $self, $triggers );
        }
    }
    return $ret;
}

##
# Permanently disable this Site
# $triggers: triggers to be executed may be added to this hash
sub disable {
    my $self     = shift;
    my $triggers = shift;

    trace( 'Site::disable', $self->siteId );

    my $ret = 1;
    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->setupPlaceholderSite( $self, 'nosuchsite', $triggers );
        }
    }
    return $ret;
}

##
# Incrementally deploy a single AppConfiguration to this Site.
# $appConfig: the AppConfiguration to add
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub addDeployAppConfiguration {
    my $self      = shift;
    my $appConfig = shift;
    my $triggers  = shift;

    trace( 'Site::addDeployAppConfiguration', $appConfig->appConfigId, $self->siteId );

    UBOS::Host::siteDeploying( $self );

    push @{$self->appConfigs},           $appConfig;
    push @{$self->{json}->{appconfigs}}, $appConfig->appConfigurationJson;

    my $ret = $appConfig->deployOrCheck( 1, $triggers );

    UBOS::Host::siteDeployed( $self );

    return $ret;
}

##
# Run the installer(s) for everything installed at this Site
# return: success or fail
sub runInstallers {
    my $self = shift;

    my $ret = 1;
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->runInstallers();
    }
    return $ret;
}

##
# Run the upgrader(s) for everything installed at this Site
# return: success or fail
sub runUpgraders {
    my $self = shift;

    my $ret = 1;
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->runUpgraders();
    }
    return $ret;
}

##
# Clear cached information.
sub clearCaches {
    my $self = shift;

    $self->{appConfigs} = undef;
    $self->{vars}       = undef;

    return $self;
}

##
# Check whether an AppConfiguration with this context path could be added
# to this site without conflicting with an existing AppConfiguration.
# This assumes that the context path itself is valid
# $context: the context path
# return: undef (yes) or error message (no)
sub mayContextBeAdded {
    my $self    = shift;
    my $context = shift;

    foreach my $appConfig ( @{$self->appConfigs} ) {
        my $appConfigContext = $appConfig->context;
        unless( defined( $appConfigContext )) {
            next;
        }
        unless( $appConfigContext ) {
            # something is a root of site, so no
            return 'App ' . $appConfig->app->packageName . ' runs at the root of the site.';
        }
        if( $appConfigContext eq $context ) {
            return 'App ' . $appConfig->app->packageName . ' already runs at context ' . $context;
        }
    }
    return 0;
}

##
# Remove the letsencrypt certificate for this site
# return: 1 for success
sub removeLetsEncryptCertificate {
    my $self = shift;

    my $ret = 1;
    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( reverse @rolesOnHost ) {
        $ret &= $role->removeLetsEncryptCertificate( $self );
    }

    return $ret;
}

##
# Check validity of the Site JSON
# $fillInTemplate: usually false. If true, instead of complaining about missing siteId and
#       appConfigIds and the like, silently assign new values
# return: 1 if ok
sub _checkJson {
    my $self           = shift;
    my $fillInTemplate = shift;

    my $json = $self->{json};
    unless( $json ) {
        $@ = 'No Site JSON present';
        return 0;
    }
    unless( $self->_checkJsonValidKeys( $json, [] )) {
        return 0;
    }

    unless( $json->{siteid} ) {
        if( $fillInTemplate ) {
            $json->{siteid} = UBOS::Host::createNewSiteId();
        } else {
            $@ = 'Site JSON: missing siteid';
            return 0;
        }
    }
    unless( UBOS::Host::isValidSiteId( $json->{siteid} )) {
        $@ = 'Site JSON: invalid siteid, must be s followed by 40 hex chars, is: ' . $json->{siteid};
        return 0;
    }
    unless( exists( $json->{tor} )) {
        unless( $json->{hostname} ) {
            $@ = 'Site JSON: missing hostname';
            return 0;
        }
        unless( UBOS::Host::isValidHostname( $json->{hostname} )) {
            $@ = 'Site JSON: invalid hostname, is: ' . $json->{hostname};
            return 0;
        }
    }

    unless( $json->{admin} ) {
        $@ = 'Site JSON: admin section is now required';
        return 0;
    }
    unless( ref( $json->{admin} ) eq 'HASH' ) {
        $@ = 'Site JSON: admin section: not a JSON object';
        return 0;
    }
    unless( $json->{admin}->{userid} ) {
        $@ = 'Site JSON: admin section: missing userid';
        return 0;
    }
    if( ref( $json->{admin}->{userid} ) || $json->{admin}->{userid} !~ m!^[a-z0-9]+$! ) {
        $@ = 'Site JSON: admin section: invalid userid, must be string without white space, is: ' . $json->{admin}->{userid};
        return 0;
    }
    unless( $json->{admin}->{username} ) {
        $@ = 'Site JSON: admin section: missing username';
        return 0;
    }
    if( ref( $json->{admin}->{username} ) ) {
        $@ = 'Site JSON: admin section: invalid username, must be string';
        return 0;
    }
    if ( $< == 0 ) {
        # only root has access to this
        unless( $json->{admin}->{credential} ) {
            if( $fillInTemplate ) {
                $json->{admin}->{credential} = UBOS::Utils::randomPassword();
            } else {
                $@ = 'Site JSON: admin section: missing credential';
                return 0;
            }
        }
        if( ref( $json->{admin}->{credential} ) || $json->{admin}->{credential} =~ m!^\s! || $json->{admin}->{credential} =~ m!\s$! ) {
            $@ = 'Site JSON: admin section: invalid credential, must be string without leading or trailing white space';
            return 0;
        }
    }
    unless( $json->{admin}->{email} ) {
        $@ = 'Site JSON: admin section: missing email';
        return 0;
    }
    if( ref( $json->{admin}->{email} ) || $json->{admin}->{email} !~ m/^[A-Z0-9._%+-]+@[A-Z0-9.-]*[A-Z]$/i ) {
        $@ = 'Site JSON: admin section: invalid email, is: ' . $json->{admin}->{email};
        return 0;
    }

    if( exists( $json->{tls} )) {
        unless( ref( $json->{tls} ) eq 'HASH' ) {
            $@ = 'Site JSON: tls section: not a JSON object';
            return 0;
        }
        if( exists( $json->{tls}->{letsencrypt} )) {
            unless( $json->{tls}->{letsencrypt} == JSON::true ) {
                $@ = 'Site JSON: tls section: letsencrypt, if given, must be true';
                return 0;
            }
        } else {
            unless( $json->{tls}->{key} || !ref( $json->{tls}->{key} )) {
                $@ = 'Site JSON: tls section: missing or invalid key';
                return 0;
            }
            unless( $json->{tls}->{crt} || !ref( $json->{tls}->{crt} )) {
                $@ = 'Site JSON: tls section: missing or invalid crt';
                return 0;
            }
            if( $json->{tls}->{crtchain} ) {
                # migrate
                if( ref( $json->{tls}->{crtchain} )) {
                    $@ = 'Site JSON: tls section: missing or invalid crtchain';
                    return 0;
                }
                $json->{tls}->{crt} .= "\n" . $json->{tls}->{crtchain};
                delete $json->{tls}->{crtchain};
            }
            if( $json->{tls}->{cacrt} && ref( $json->{tls}->{cacrt} )) {
                $@ = 'Site JSON: tls section: invalid cacrt';
                return 0;
            }
        }
    }

    if( exists( $json->{wellknown} )) {
        unless( ref( $json->{wellknown} ) eq 'HASH' ) {
            $@ = 'Site JSON: wellknown section: not a JSON object';
            return 0;
        }
        if( exists( $json->{wellknown}->{robotstxt} )) {
            if( ref( $json->{wellknown}->{robotstxt} )) {
                $@ = 'Site JSON: wellknown section: invalid robotstxt';
                return 0;
            }
            if( exists( $json->{wellknown}->{robotstxtprefix} )) {
                $@ = 'Site JSON: wellknown section: specifiy robotstxt or robotstxtprefix, not both';
                return 0;
            }
        }
        if( exists( $json->{wellknown}->{robotstxtprefix} )) {
            if( ref( $json->{wellknown}->{robotstxtprefix} )) {
                $@ = 'Site JSON: wellknown section: invalid robotstxtprefix';
                return 0;
            }
        }
        if(    exists( $json->{wellknown}->{sitemapxml} )
            && (    ref( $json->{wellknown}->{sitemapxml} )
                 || $json->{wellknown}->{sitemapxml} !~ m!^<\?xml! ))
        {
            $@ = 'Site JSON: wellknown section: invalid sitemapxml';
            return 0;
        }
        if( exists( $json->{wellknown}->{faviconicobase64} ) && ref( $json->{wellknown}->{faviconicobase64} )) {
            $@ = 'Site JSON: wellknown section: invalid faviconicobase64';
            return 0;
        }
    }

    if( exists( $json->{tor} )) {
        unless( ref( $json->{tor} ) eq 'HASH' ) {
            $@ = 'Site JSON: tor section: not a JSON hash';
            return 0;
        }
        if( keys %{$json->{tor}} > 0 ) {
            # allowed to be empty
            unless( exists( $json->{tor}->{privatekey} )) {
                $@ = 'Site JSON: tor section: missing privatekey';
                return 0;
            }
            if( ref( $json->{tor}->{privatekey} ) || $json->{tor}->{privatekey} !~ m!\S+! ) {
                $@ = 'Site JSON: tor section: privatekey must be a string';
                return 0;
            }
        }
    }

    if( exists( $json->{appconfigs} )) {
        unless( ref( $json->{appconfigs} ) eq 'ARRAY' ) {
            $@ = 'Site JSON: appconfigs section: not a JSON array';
            return 0;
        }

        my $i=0;
        foreach my $appConfigJson ( @{$json->{appconfigs}} ) {
            unless( $appConfigJson->{appconfigid} ) {
                if( $fillInTemplate ) {
                    $appConfigJson->{appconfigid} = UBOS::Host::createNewAppConfigId();
                } else {
                    $@ = "Site JSON: appconfig $i: missing appconfigid";
                    return 0;
                }
            }
            unless( UBOS::Host::isValidAppConfigId( $appConfigJson->{appconfigid} )) {
                $@ = "Site JSON: appconfig $i: invalid appconfigid, must be a followed by 40 hex chars, is: " . $appConfigJson->{appconfigid};
                return 0;
            }
            if(    $appConfigJson->{context}
                && ( ref( $appConfigJson->{context} ) || !UBOS::AppConfiguration::isValidContext( $appConfigJson->{context} )))
            {
                $@ = "Site JSON: appconfig $i: invalid context, must be valid context URL without trailing slash, is: " . $appConfigJson->{context};
                return 0;
            }
            if( defined( $appConfigJson->{isdefault} ) && !JSON::is_bool( $appConfigJson->{isdefault} )) {
                $@ = "Site JSON: appconfig $i: invalid isdefault, must be true or false";
                return 0;
            }
            unless( UBOS::Installable::isValidPackageName( $appConfigJson->{appid} )) {
                $@ = "Site JSON: appconfig $i: invalid appid, is: " . $appConfigJson->{appid};
                return 0;
            }
            my %installables = ();
            $installables{$appConfigJson->{appid}} = 1;

            if( exists( $appConfigJson->{accessoryids} )) {
                unless( ref( $appConfigJson->{accessoryids} ) eq 'ARRAY' ) {
                    $@ = "Site JSON: appconfig $i, accessoryids: not a JSON array, is: " . $appConfigJson->{accessoryids};
                    return 0;
                }
                foreach my $accessoryId ( @{$appConfigJson->{accessoryids}} ) {
                    unless( UBOS::Installable::isValidPackageName( $accessoryId )) {
                        $@ = "Site JSON: appconfig $i: invalid accessoryid, is: " . $accessoryId;
                        return 0;
                    }
                    $installables{$accessoryId} = 1;
                }
            }
            if( exists( $appConfigJson->{customizationpoints} )) {
                if( ref( $appConfigJson->{customizationpoints} ) ne 'HASH' ) {
                    $@ = 'Site JSON: customizationpoints section: not a JSON HASH';
                    return 0;
                }

                my @packageNames = keys %{$appConfigJson->{customizationpoints}};
                foreach my $packageName ( @packageNames ) {
                    unless( $installables{$packageName} ) {
                        $@ = 'Site JSON: customizationpoint specified for non-installed installable ' . $packageName . ', installed: ' . join( ' ', keys %installables );
                        return 0;
                    }
                    my $custPointsForPackage = $appConfigJson->{customizationpoints}->{$packageName};
                    if( !$custPointsForPackage || ref( $custPointsForPackage ) ne 'HASH' ) {
                        $@ = 'Site JSON: customizationpoints for package ' . $packageName . ' must be a JSON hash';
                        return 0;
                    }
                    if( keys %$custPointsForPackage ) {
                        foreach my $pointName ( keys %$custPointsForPackage ) {
                            unless( $pointName =~ m!^[a-z][a-z0-9_]*$! ) {
                                $@ = 'Site JSON: invalid name for customizationpoint, is: ' . $pointName;
                                return 0;
                            }
                            my $pointValue = $custPointsForPackage->{$pointName};
                            if( !$pointValue || ref( $pointValue ) ne 'HASH' ) {
                                $@ = 'Site JSON: customizationpoint values for package ' . $packageName . ', point ' . $pointName . ' must be a JSON hash';
                                return 0;
                            }
                            my $valueEncoding = $pointValue->{encoding};
                            if( $valueEncoding && $valueEncoding ne 'base64' ) {
                               $@ = 'Site JSON: customizationpoint value for package ' . $packageName . ', point ' . $pointName . ' invalid encoding';
                               return 0;
                            }
                        }
                    } else {
                        delete $appConfigJson->{customizationpoints}->{$packageName}; # clean up empty sections
                    }
                }
            }
            ++$i;
        }
    }

    return 1;
}

##
# Recursive check that Site JSON only has valid keys. This catches typos.
# $json: the JSON, or JSON sub-tree
# $context: the name of the current section, if any
# return: 1 if ok
sub _checkJsonValidKeys {
    my $self    = shift;
    my $json    = shift;
    my $context = shift;

    if( ref( $json ) eq 'HASH' ) {
        if( @$context >= 2 && $context->[-1] eq 'customizationpoints' ) {
            # This is a package name, which has laxer rules
            foreach my $key ( keys %$json ) {
                my $value = $json->{$key};

                unless( $key =~ m!^[a-z][-_a-z0-9]*$! ) {
                    $@ = 'Site JSON: invalid key (1) in JSON: ' . "'$key'" . ' context: ' . ( join( ' / ', @$context ) || '(top)' );
                    return 0;
                }
                unless( $self->_checkJsonValidKeys( $value, [ @$context, $key ] )) {
                    return 0;
                }
            }
        } elsif( @$context >= 2 && $context->[-2] eq 'customizationpoints' ) {
            # This is a customization point name, which has laxer rules
            foreach my $key ( keys %$json ) {
                my $value = $json->{$key};

                unless( $key =~ m!^[a-z][_a-z0-9]*$! ) {
                    $@ = 'Site JSON: invalid key (2) in JSON: ' . "'$key'" . ' context: ' . ( join( ' / ', @$context ) || '(top)' );
                    return 0;
                }
                unless( $self->_checkJsonValidKeys( $value, [ @$context, $key ] )) {
                    return 0;
                }
            }
        } else {
            foreach my $key ( keys %$json ) {
                my $value = $json->{$key};

                unless( $key =~ m!^[a-z][a-z0-9]*$! ) {
                    $@ = 'Site JSON: invalid key (3) in JSON: ' . "'$key'" . ' context: ' . ( join( ' / ', @$context ) || '(top)' );
                    return 0;
                }
                unless( $self->_checkJsonValidKeys( $value, [ @$context, $key ] )) {
                    return 0;
                }
            }
        }
    } elsif( ref( $json ) eq 'ARRAY' ) {
        foreach my $element ( @$json ) {
            unless( $self->_checkJsonValidKeys( $element, $context )) {
                return 0;
            }
        }
    }
    return 1;
}

1;
