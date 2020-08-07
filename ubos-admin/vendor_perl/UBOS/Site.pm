#!/usr/bin/perl
#
# Represents a Site, aka Virtual Host.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Site;

use JSON;
use MIME::Base64;
use UBOS::AppConfiguration;
use UBOS::Host;
use UBOS::LetsEncrypt;
use UBOS::Logging;
use UBOS::TemplateProcessor;
use UBOS::Terminal;
use UBOS::Utils;
use UBOS::X509;

use fields qw( json skipFilesystemChecks manifestFileReader appConfigs vars);

my $WILDCARDHOSTNAME = "__wildcard";

##
# Constructor.
# $json: JSON object containing Site JSON
# $fillInTemplate: usually false. If true, instead of complaining about missing siteId and
#       appConfigIds and the like, silently assign new values
# $manifestFileReader: pointer to a method that knows how to read manifest files
# return: Site object
sub new {
    my $self                 = shift;
    my $json                 = shift;
    my $fillInTemplate       = shift || 0;
    my $skipFilesystemChecks = shift;
    my $manifestFileReader   = shift || \&UBOS::Host::defaultManifestFileReader;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    if( exists( $json->{ssl} )) {
        # migrate
        $json->{tls} = $json->{ssl};
        delete $json->{ssl};
    }
    if( exists( $json->{tls} ) && exists( $json->{tls}->{letsencrypt} ) && $json->{tls}->{letsencrypt} ) {
        my( $keyFile, $crtFile ) = UBOS::LetsEncrypt::getLiveKeyAndCertificateFiles( $json->{hostname} );
        if( $keyFile ) {
            $json->{tls}->{key} = UBOS::Utils::slurpFile( $keyFile );
            $json->{tls}->{crt} = UBOS::Utils::slurpFile( $crtFile );
        } # Otherwise is fine: LetsEncrypt but not provisioned yet (new site) or stashed
    } # If tls and not LetsEncrypt, the key/cert is in the Site JSON

    $self->{json}                 = $json;
    $self->{skipFilesystemChecks} = $skipFilesystemChecks;
    $self->{manifestFileReader}   = $manifestFileReader;

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

    return $self->_siteJsonWithout( 1, 1, 1, 1, 1 );
}

##
# Obtain the Site JSON but without TLS info
# return: JSON without TLS info
sub siteJsonWithoutTls {
    my $self = shift;

    return $self->_siteJsonWithout( 1, 0, 0, 0, 0 );
}

##
# Obtain the Site JSON but without the LetsEncrypt cert and key
# return: JSON without LetsEncrypt cert and key
sub siteJsonWithoutLetsEncryptCert {
    my $self = shift;

    return $self->_siteJsonWithout( 0, 1, 0, 0, 0 );
}

##
# Helper method to return subsets of the Site JSON. Also, do not return
# values for customization points marked as private.
# $noTls: if 1, do not return any TLS info; treat the site as if it did not have TLS
# $noLetsEncryptCerts: if 1 and the Site uses LetsEncrypt, don't return key and cert
# $noAdminCredential: if 1, do not return site admin credential
# $noPrivateCustomizationPoints: if 1, do not return the value of private customizationpoints
# $noInternalCustomizationPoints: if 1, do not return the value of internal customizationpoints
sub _siteJsonWithout {
    my $self                          = shift;
    my $noTls                         = shift;
    my $noLetsEncryptCerts            = shift;
    my $noAdminCredential             = shift;
    my $noPrivateCustomizationPoints  = shift;
    my $noInternalCustomizationPoints = shift;

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
    if( !$noTls && exists( $json->{tls} )) {
        if(    exists( $json->{tls}->{letsencrypt} )
            && $json->{tls}->{letsencrypt}
            && $noLetsEncryptCerts )
        {
            $ret->{tls}->{letsencrypt} = $json->{tls}->{letsencrypt}; # don't copy rest of hash
        } else {
            $ret->{tls} = $json->{tls}; # by reference is fine
        }
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
                        my $doCopy;
                        if( exists( $custPointDefJson->{private} ) && $custPointDefJson->{private} ) {
                            $doCopy = !$noPrivateCustomizationPoints;

                        } elsif( exists( $custPointDefJson->{internal} ) && $custPointDefJson->{internal} ) {
                            $doCopy = !$noInternalCustomizationPoints;

                        } else {
                            $doCopy = 1;
                        }
                        if( $doCopy ) {
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
# Obtain the site's host name, or, if it is *, the address of localhost
# return: string
sub hostnameorlocalhost {
    my $self = shift;

    my $ret = $self->hostname();
    if( $ret eq '*' ) {
        $ret = '127.0.0.1';
    }
    return $ret;
}

##
# Obtain the site's port.
# return: 80 or 443
sub port {
    my $self = shift;

    if( $self->isTls() ) {
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

    if( $self->isTls() ) {
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
                            "hostnameorlocalhost"      => $self->hostnameorlocalhost(),
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
# Determine whether this site is supposed to be protected by SSL/TLS. This
# does not indicate the type of TLS (LetsEncrypt, official or self-signed)
# or whether we actually have the key and certs to do so.
# return: 0 or 1
sub isTls {
    my $self = shift;

    my $json = $self->{json};
    return defined( $json->{tls} );
}

##
# Determine whether this site is supposed to be protected by SSL/TLS issued
# by LetsEncrypt.
# return: 0 or 1
sub isLetsEncryptTls {
    my $self = shift;

    my $json = $self->{json};
    if( !exists( $json->{tls} )) {
        return 0;
    }
    return $json->{tls}->{letsencrypt} ? 1 : 0;
}

##
# Obtain the TLS key, if any has been provided.
# return: the TLS key
sub tlsKey {
    my $self = shift;

    my $json = $self->{json};
    if( exists( $json->{tls} ) && exists( $json->{tls}->{key} )) {
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
    if( exists( $json->{tls} ) && exists( $json->{tls}->{crt} )) {
        return $json->{tls}->{crt};
    } else {
        return undef;
    }
}

##
# Reset the letsencrypt flag. This is used only in case obtaining the
# certificate from LetsEncrypt failed.
sub unsetLetsEncryptTls {
    my $self = shift;

    my $json = $self->{json};
    if( exists( $json->{tls} )) {
        delete $json->{tls}; # delete the whole subtree
    }
}

##
# Delete the TLS information from this site. This is used during restore
# if the user wants to restore the site to non-TLS.
sub deleteTlsInfo {
    my $self = shift;

    my $json = $self->{json};
    if( exists( $json->{tls} )) {
        delete $json->{tls}; # delete the whole subtree
    }
}

##
# Obtain the TLS certificate chain to be used with clients, if any has been provided.
sub tlsCaCert {
    my $self = shift;

    my $json = $self->{json};
    if( exists( $json->{tls} ) && exists( $json->{tls}->{cacrt} )) {
        return $json->{tls}->{cacrt};
    } else {
        return undef;
    }
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
# Obtain the computed well-knowns of this site.
# return: hash of name of the well-known (e.g. 'robots.txt') to either
#   * a hash that contains entry 'value' with the file content, or
#   * a hash that contains entry 'location' with the redirect location,
#     and entry 'status' with the HTTP redirect status to use
#   Also has entry 'specifier' for a human-readable label of who added the entry
sub wellknowns {
    my $self = shift;

    my $ret = {};

    # robots.txt and webfinger are different.
    $ret->{'robots.txt'} = {
        'value' => $self->_constructRobotsTxt()
    };
    my $webfingerProxyUrls = $self->_determineWebfingerProxyUrls();
    if( $webfingerProxyUrls ) {
        $ret->{webfinger} = {
            'proxies' => $webfingerProxyUrls
        };
    }

    # We start with what's provided in the Site JSON.
    # Then we walk through the AppConfigs in sequence. We add those
    # values if we don't have one already for the same key, but we do
    # all-or-nothing on a per-AppConfig basis.

    my @wellknownJsons = ();

    if( exists( $self->{json}->{wellknown} )) {
        $self->_addWellKnownIfNotPresent(
                $ret,
                $self->{json}->{wellknown},
                $self->vars(),
                undef );
    }

    foreach my $appConfig ( @{$self->appConfigs} ) {
        my $app              = $appConfig->app();
        my $appWellknownJson = $app->wellknownJson();

        if( $appWellknownJson ) {
            $self->_addWellKnownIfNotPresent(
                    $ret,
                    $appWellknownJson,
                    $appConfig->vars(),
                    'App ' . $app->packageName() . ' at ' . $self->hostname() . $appConfig->context() );
        }
    }

    return $ret;
}

##
# Helper to construct the site's robots.txt file content, if any has been provided.
# return: robots.txt content
sub _constructRobotsTxt {
    my $self = shift;

    my $json = $self->{json};
    my $robotsTxt;

    if( exists( $json->{wellknown} ) && exists( $json->{wellknown}->{'robots.txt'} )) {
        if( exists( $json->{wellknown}->{'robots.txt'}->{value} )) {
            return $json->{wellknown}->{'robots.txt'}->{value}; # Site JSON overrides
        }
        if( exists( $json->{wellknown}->{'robots.txt'}->{prefix} )) {
            $robotsTxt = $json->{wellknown}->{'robots.txt'}->{prefix} . "\n";
        }
    }
    my $thisFirst = "User-Agent: *\n";
    my $allowContent    = "";
    my $disallowContent = "";

    foreach my $appConfig ( @{$self->appConfigs} ) {
        my $app           = $appConfig->app();
        my $context       = $appConfig->context();
        my $wellknownJson = $app->wellknownJson();

        if( $wellknownJson && exists( $wellknownJson->{'robots.txt'} )) {
            if( exists( $wellknownJson->{'robots.txt'}->{allow} )) {
                foreach my $allow ( @{$wellknownJson->{'robots.txt'}->{allow}} ) {
                    $allowContent .= "Allow: $context$allow\n";
                }
            }
            if( exists( $wellknownJson->{'robots.txt'}->{disallow} )) {
                foreach my $disallow ( @{$wellknownJson->{'robots.txt'}->{disallow}} ) {
                    $disallowContent .= "Disallow: $context$disallow\n";
                }
            }
        }
    }
    if( $robotsTxt || $allowContent || $disallowContent ) {
        if( $allowContent || $disallowContent ) {
            $robotsTxt .= "User-Agent: *\n";
            $robotsTxt .= $allowContent;
            $robotsTxt .= $disallowContent;
        }
        trace( 'Constructed robots.txt for site', $self->siteId );
        return $robotsTxt;
    } else {
        return undef;
    }
}

##
# Helper to determine the URLs to access to determine the site's webfinder
# content, if any
# return: pointer to array of URL
sub _determineWebfingerProxyUrls {
    my $self = shift;

    my $json = $self->{json};
    my @ret  = ();

    foreach my $appConfig ( @{$self->appConfigs} ) {
        my $app           = $appConfig->app();
        my $wellknownJson = $app->wellknownJson();

        if( defined( $wellknownJson ) && exists( $wellknownJson->{webfinger} )) {
            my $vars = $app->obtainInstallableAtAppconfigVars( $appConfig, 1 );

            my $url = $vars->replaceVariables( $wellknownJson->{webfinger}->{proxy} );
            push @ret, $url;
        }
    }

    return \@ret;
}

##
# Helper to add entries from a Site or App's well-known definitions
# if they don't exist already
# $aggregate: the in-process return value for wellknowns() above
# $json: the well-known JSON of a Site or App
# $vars: the Variables to use to replace content
# $specifier: name of the current item, for override warning message.
#    May be undef, in which case overriding this item will remain silent.
#    Used for overrides by the site, which are presumably intentional.
sub _addWellKnownIfNotPresent {
    my $self      = shift;
    my $aggregate = shift;
    my $json      = shift;
    my $vars      = shift;
    my $specifier = shift;

    my $tmp = {};

    foreach my $wellknownKey ( keys %$json ) {
        if( 'robots.txt' eq $wellknownKey ) {
            next;
        }
        my $wellknownValue = $json->{$wellknownKey};
        if( exists( $wellknownValue->{value} )) {
            my $value = $wellknownValue->{value};
            if( exists( $wellknownValue->{encoding} )) {
                $value = decode_base64( $value );
            }

            $tmp->{$wellknownKey} = {
                'value' => $value
            };
        } elsif( exists( $wellknownValue->{template} )) {
            my $templateLang      = exists( $wellknownValue->{templatelang} ) ? $wellknownValue->{templatelang} : undef;
            my $templateProcessor = UBOS::TemplateProcessor::create( $templateLang );

            my $value = $templateProcessor->process( $wellknownValue->{template}, $vars, "template in manifest: $wellknownKey" );
            $tmp->{$wellknownKey} = {
                'value' => $value
            };

        } elsif( exists( $wellknownValue->{location} )) {
            my $status = '307';
            if( exists( $wellknownValue->{status} )) {
                $status = $wellknownValue->{status};
            }
            $tmp->{$wellknownKey} = {
                'location' => $vars->replaceVariables( $wellknownValue->{location} ),
                'status'   => $status
            };
        }
    }

    my $foundOverlap = 0;
    foreach my $key ( keys %$tmp ) {
        if( exists( $aggregate->{$key} )) {
            $foundOverlap = 1;

            if( exists( $aggregate->{$key}->{specifier} )) {
                my $previousSpecifier = $aggregate->{$key}->{specifier};
                warning( 'Not adding .well-known entries for ' . $specifier . ' as they would conflict with those given by ' . $previousSpecifier );
            }

            last;
        }
    }
    unless( $foundOverlap ) {
        foreach my $key ( keys %$tmp ) {
            $aggregate->{$key} = $tmp->{$key};
            if( $specifier ) {
                $aggregate->{$key}->{specifier} = $specifier;
            }
        }
    }
    return $tmp; # not really needed
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
            push @{$self->{appConfigs}},
                 UBOS::AppConfiguration->new( $current, $self, $self->{skipFilesystemChecks}, $self->{manifestFileReader} );
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

    return 1;
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
    if( $self->isLetsEncryptTls ) {
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


    if( $doIt && $self->isTls() && ! $self->isLetsEncryptTls() ) {
        foreach my $role ( @rolesOnHost ) {
            if( $self->needsRole( $role )) {
                $ret &= $role->saveTlsKeyAndCertificate( $self );
            }
        }
    }

    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->setupSiteOrCheck( $self, $doIt, $triggers );
        }
    }

    if( $doIt ) {
        if( $self->isLetsEncryptTls()) {
            my $success = $self->obtainLetsEncryptCertificate();
            unless( $success ) {
                $self->unsetLetsEncryptTls;
            }
            # do not pass on failure, as we will indeed set up a Site, just not with LetsEncrypt
        }
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
        if( $self->hasLetsEncryptCertificate()) {
            $ret &= UBOS::LetsEncrypt::stashCertificate( $self->hostname() );
        }

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
# Add a single AppConfiguration to this Site for the purposes of restoring
# from backup.
# $appConfig: the AppConfiguration to add
# return: success or fail
sub addAppConfigurationForRestore {
    my $self      = shift;
    my $appConfig = shift;

    trace( 'Site::addAppConfigurationForRestore', $appConfig->appConfigId, $self->siteId );

    push @{$self->appConfigs},           $appConfig;
    push @{$self->{json}->{appconfigs}}, $appConfig->appConfigurationJson;

    return 1;
}

##
# Deploy a single AppConfiguration to this Site for the purposes of restoring
# from backup.
# $appConfig: the AppConfiguration to add
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub deployAppConfigurationForRestore {
    my $self      = shift;
    my $appConfig = shift;
    my $triggers  = shift;

    trace( 'Site::deployAppConfigurationForRestore', $appConfig->appConfigId, $self->siteId );

    UBOS::Host::siteDeploying( $self );

    my $ret = $appConfig->deployOrCheck( 1, $triggers );

    UBOS::Host::siteDeployed( $self );

    return $ret;
}

##
# Run the upgrader(s), or installer(s) as appropriate for everything installed
# at this Site
# $oldSite: if this Site existed before, the old Site configuration
# return: success or fail
sub runInstallersOrUpgraders {
    my $self    = shift;
    my $oldSite = shift;

    trace( 'Site::runInstallersOrUpgraders', $self->siteId, $oldSite ? $oldSite->siteId : undef );

    my $ret = 1;
    foreach my $appConfig ( @{$self->appConfigs} ) {
        my $oldAppConfig = $oldSite ? $oldSite->appConfig( $appConfig->appConfigId() ) : undef;
        $ret &= $appConfig->runInstallersOrUpgraders( $oldAppConfig );
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
# Determine whether we already have a LetsEncrypt certificate.
# return: 0 or 1
sub hasLetsEncryptCertificate {
    my $self = shift;

    unless( $self->isLetsEncryptTls()) {
        return 0;
    }
    if( $self->tlsKey() && $self->tlsCert() ) {
        return 1;
    }
    return 0;
}

##
# If this role needs a LetsEncrypt certificate, obtain it. If we already
# have a non-active one, use that instead and attempt to renew.
# return: 1 if succeeded
sub obtainLetsEncryptCertificate {
    my $self = shift;

    my $hostname               = $self->hostname();
    my $siteId                 = $self->siteId();
    my $sitesWellknownDir      = $self->vars()->getResolve( 'apache2.siteswellknowndir' );
    my $siteWellknownParentDir = "$sitesWellknownDir/$siteId";

    # First attempt: have live cert already
    if( UBOS::LetsEncrypt::isCertificateLive( $self->hostname() )) {
        return 1;
    }

    # Next attempt: use cert in the Site JSON
    my $tlsKey  = $self->tlsKey();
    my $tlsCert = $self->tlsCert();
    if( $tlsCert ) {
        my $tlsCrtFile = File::Temp->new();
        print $tlsCrtFile $tlsCert;
        close $tlsCrtFile;

        my $crtInfo = UBOS::X509::crtInfo( $tlsCrtFile );

        if( $crtInfo =~ m!^CN\s*=\*s\Q$hostname\E$! && !UBOS::LetsEncrypt::certNeedsRenewal( $crtInfo )) {

            UBOS::LetsEncrypt::deleteStashedCertificate( $hostname ); # ok if does not exist

            if( UBOS::LetsEncrypt::importCertificate(
                    $hostname,
                    $siteWellknownParentDir,
                    $tlsKey,
                    $tlsCert,
                    $self->obtainSiteAdminHash()->{email} ))
            {
                return 1;
            }
            error( 'Importing LetsEncrypt certificate failed' );
        }
        delete $self->{json}->{tls}->{key};
        delete $self->{json}->{tls}->{crt};
    }

    # Next attempt: use stashed cert
    if( UBOS::LetsEncrypt::isCertificateStashed( $hostname )) {
        my( $tlsKeyFile, $tlsCrtFile ) = UBOS::LetsEncrypt::getStashedKeyAndCertificateFiles( $hostname );

        # Certbot will not obtain a new cert if the archive directory for the domain exists,
        # so we will renew in that case.

        my $crtInfo  = UBOS::X509::crtInfo( $tlsCrtFile );

        if( UBOS::LetsEncrypt::certNeedsRenewal( $crtInfo )) {
            UBOS::LetsEncrypt::unstashCertificate( $hostname );
            unless( UBOS::LetsEncrypt::renewCertificates()) {
                if( UBOS::Logging::isTraceActive() ) {
                    warning( $@ );
                } else {
                    warning( 'Failed to renew LetsEncrypt certificates' );
                }
                return 0;
            }
            return 1;
        } else {
            UBOS::LetsEncrypt::unstashCertificate( $hostname );
            return 1;
        }
    }

    # Get a new cert
    my $adminHash = $self->obtainSiteAdminHash;

    my $success = UBOS::LetsEncrypt::provisionCertificate(
            $hostname,
            $siteWellknownParentDir, # use as fake documentroot
            $adminHash->{email} );
    unless( $success ) {
        if( UBOS::Logging::isTraceActive() ) {
            warning( "Provisioning LetsEncrypt certificate failed for site $hostname:\n$@" );
        } else {
            warning( "Provisioning LetsEncrypt certificate failed for site $hostname.\nProceeding without certificate or TLS/SSL.\n"
                     . "Make sure you are not running this behind a firewall, and that DNS is set up properly." );
        }
    }
    return $success;
}

##
# Print this Site's SiteId
sub printSiteId {
    my $self = shift;

    colPrint( $self->siteId . "\n" );
}

##
# Print information about this Site's administrator
# $indent: should the printed text be indented
sub printAdminUser {
    my $self   = shift;
    my $indent = shift || 0;

    my $admin        = $self->obtainSiteAdminHash(); # Returns something different for root/non-root
    my $indentString = $indent ? '    ' : '';

    if( exists( $admin->{userid} )) {
        colPrint( $indentString . 'Site admin user id:       "' . $admin->{userid}     . "\"\n" );
    }
    if( exists( $admin->{username} )) {
        colPrint( $indentString . 'Site admin user name:     "' . $admin->{username}   . "\"\n" );
    }
    if( exists( $admin->{credential} )) {
        colPrint( $indentString . 'Site admin user password: "' . $admin->{credential} . "\"\n" );
    }
    if( exists( $admin->{email} )) {
        colPrint( $indentString . 'Site admin user e-mail:   "' . $admin->{email}      . "\"\n" );
    }
}

##
# Print this Site in varying levels of detail
# $detail: the level of detail
# $showPrivateCustomizationPoints: unless true, blank out the values of private customizationpoints
sub print {
    my $self                           = shift;
    my $detail                         = shift || 2;
    my $showPrivateCustomizationPoints = shift;

    colPrint( $self->hostname );
    if( $self->isTls ) {
        colPrint( ' (TLS)' );
    }
    if( $detail > 2 ) {
        colPrint( ' (' . $self->siteId . ')' );
    }
    colPrint( ' :' );
    if( $detail <= 1 ) {
        my $nAppConfigs = @{$self->appConfigs};
        if( $nAppConfigs == 1 ) {
            colPrint( ' 1 app' );
        } elsif( $nAppConfigs ) {
            colPrint( " $nAppConfigs apps" );
        } else {
            colPrint( ' no apps' );
        }
    }
    colPrint( "\n" );

    if( $detail > 1 ) {
        foreach my $isDefault ( 1, 0 ) {
            my $hasDefault = grep { $_->isDefault } @{$self->appConfigs};

            foreach my $appConfig ( sort { $a->appConfigId cmp $b->appConfigId } @{$self->appConfigs} ) {
                if( ( $isDefault && $appConfig->isDefault ) || ( !$isDefault && !$appConfig->isDefault )) {
                    colPrint( '    ' );

                    my $context = $appConfig->context;
                    if( $context ) {
                        colPrint( $context );
                    } elsif( defined( $context )) {
                        colPrint( '<root>' );
                    } else {
                        colPrint( '<none>' );
                    }
                    if( $isDefault && $appConfig->isDefault ) {
                        colPrint( ' default' );
                    }
                    if( $detail > 2 ) {
                        colPrint( ' (' . $appConfig->appConfigId . ')' );
                    }
                    if( $detail < 3 ) {
                        colPrint( ' : ' . $appConfig->app->packageName );
                        my $nAcc = $appConfig->accessories();
                        if( $nAcc == 1 ) {
                            colPrint( ' (1 accessory)' );
                        } elsif( $nAcc ) {
                            colPrint( " ($nAcc accessories)" );
                        }
                        colPrint( "\n" );
                    } else {
                        colPrint( "\n" );

                        my $custPoints = $appConfig->customizationPoints;
                        foreach my $installable ( $appConfig->installables ) {
                            colPrint( '        ' );
                            if( $installable == $appConfig->app ) {
                                colPrint( 'app:       ' );
                            } else {
                                colPrint( 'accessory: ' );
                            }
                            colPrint( $installable->packageName . "\n" );
                            if( $custPoints ) {
                                my $installableCustPoints = $custPoints->{$installable->packageName};
                                if( defined( $installableCustPoints )) {
                                    foreach my $custPointName ( sort keys %$installableCustPoints ) {
                                        my $custPointValueStruct = $installableCustPoints->{$custPointName};
                                        my $custPointDef         = $installable->customizationPoints();

                                        if( exists( $custPointDef->{$custPointName}->{internal} ) && $custPointDef->{$custPointName}->{internal} ) {
                                            next;
                                        }

                                        my $value;
                                        if(    !$showPrivateCustomizationPoints
                                            && exists( $custPointDef->{$custPointName}->{private} )
                                            && $custPointDef->{$custPointName}->{private} )
                                        {
                                            next;
                                        }

                                        $value = $custPointValueStruct->{value};

                                        colPrint( '            customizationpoint: ' . $custPointName . ': ' );

                                        if( defined( $value )) {
                                            $value =~ s!\n!\\n!g; # don't do multi-line
                                            colPrint( ( length( $value ) < 60 ) ? $value : ( substr( $value, 0, 60 ) . '...' ));
                                        } else {
                                            colPrint( "<not set>" );
                                        }
                                        colPrint( "\n" );
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

    return $self->print( 1, 0 );
}

##
# Print this Site in the detailed format
# $showPrivateCustomizationPoints: unless true, blank out the values of private customizationpoints
sub printDetail {
    my $self                           = shift;
    my $showPrivateCustomizationPoints = shift;

    return $self->print( 3, $showPrivateCustomizationPoints );
}

##
# Print this Site in HTML format
# $detail: the level of detail
# $showPrivateCustomizationPoints: unless true, blank out the values of private customizationpoints
sub printHtml {
    my $self                           = shift;
    my $detail                         = shift || 2;
    my $showPrivateCustomizationPoints = shift;

    my $protoPlusHost = $self->protocol() . "://" . $self->hostname;
    colPrint( "<div class='site'>\n" );
    colPrint( " <div class='summary'>\n" );
    colPrint( "  <a href='" . $protoPlusHost . "/'>" . $self->hostname . "</a>");
    if( $self->isTls ) {
        colPrint( ' (TLS)' );
    }
    if( $detail > 2 ) {
        colPrint( ' (' . $self->siteId . ')' );
    }
    colPrint( ' :' );
    if( $detail <= 1 ) {
        my $nAppConfigs = @{$self->appConfigs};
        if( $nAppConfigs == 1 ) {
            colPrint( ' 1 app' );
        } elsif( $nAppConfigs ) {
            colPrint( " $nAppConfigs apps" );
        } else {
            colPrint( ' no apps' );
        }
    }
    colPrint( "\n" );
    colPrint( " </div>\n" );

    if( $detail > 1 ) {
        colPrint( " <ul class='appconfigs'>\n" );
        foreach my $isDefault ( 1, 0 ) {
            my $hasDefault = grep { $_->isDefault } @{$self->appConfigs};

            foreach my $appConfig ( sort { $a->appConfigId cmp $b->appConfigId } @{$self->appConfigs} ) {
                if( ( $isDefault && $appConfig->isDefault ) || ( !$isDefault && !$appConfig->isDefault )) {
                    colPrint( "  <li class='appconfig'>\n" );
                    colPrint( "   <div class='summary'>\n" );

                    my $context = $appConfig->context;
                    if( $context ) {
                        colPrint( "    <a href='" . $protoPlusHost . $context . "/'>" . $context . "</a>");
                    } elsif( defined( $context )) {
                        colPrint( "    <a href='" . $protoPlusHost . "/'>" . '&lt;root&gt;' . "</a>");
                    } else {
                        colPrint( '&lt;none&gt;' );
                    }
                    if( $isDefault && $appConfig->isDefault ) {
                        colPrint( ' default' );
                    }
                    if( $detail > 2 ) {
                        colPrint( ' (' . $appConfig->appConfigId . ')' );
                    }
                    if( $detail < 3 ) {
                        colPrint( ' : ' . $appConfig->app->packageName );
                        my $nAcc = $appConfig->accessories();
                        if( $nAcc == 1 ) {
                            colPrint( " (1 accessory)\n" );
                        } elsif( $nAcc ) {
                            colPrint( " ($nAcc accessories)\n" );
                        }
                        colPrint( "\n" );
                        colPrint( "   </div>\n" );
                    } else {
                        colPrint( "\n" );
                        colPrint( "   </div>\n" );
                        colPrint( "   <dl class='custpoints'>\n" );

                        my $custPoints = $appConfig->customizationPoints;
                        foreach my $installable ( $appConfig->installables ) {
                            colPrint( "    <dt>" );
                            if( $installable == $appConfig->app ) {
                                colPrint( 'app: ' );
                            } else {
                                colPrint( 'accessory: ' );
                            }
                            colPrint( $installable->packageName . "</dt>\n" );
                            if( $custPoints ) {
                                my $installableCustPoints = $custPoints->{$installable->packageName};
                                if( defined( $installableCustPoints )) {
                                    colPrint( "    <dd>\n" );
                                    colPrint( "     <dl>\n" );
                                    foreach my $custPointName ( sort keys %$installableCustPoints ) {
                                        my $custPointValueStruct = $installableCustPoints->{$custPointName};
                                        my $custPointDef         = $installable->customizationPoints();

                                        if( exists( $custPointDef->{internal} ) && $custPointDef->{internal} ) {
                                            next;
                                        }

                                        my $value;
                                        if(    !$showPrivateCustomizationPoints
                                            && exists( $custPointDef->{$custPointName}->{private} )
                                            && $custPointDef->{$custPointName}->{private} )
                                        {
                                            $value = "&lt;not shown&gt;";
                                        } else {
                                            $value = $custPointValueStruct->{value};
                                        }

                                        $value =~ s!\n!\\n!g; # don't do multi-line

                                        colPrint( '      <dt>customizationpoint: ' . $custPointName . ":</dt>\n" );
                                        colPrint( "      <dd>" );
                                        colPrint( ( length( $value ) < 60 ) ? $value : ( substr( $value, 0, 60 ) . '...' ));
                                        colPrint( "</dd>\n" );
                                    }
                                    colPrint( "     </dl>\n" );
                                    colPrint( "    </dd>\n" );
                                }
                            }
                        }
                        colPrint( "   </dl>\n" );
                    }
                    colPrint( "  </li>\n" );
                }
            }
        }
        colPrint( " </ul>\n" );
    }
    colPrint( "</div>\n" );
}

##
# Print this Site in the brief format in HTML
sub printHtmlBrief {
    my $self = shift;

    return $self->printHtml( 1, 0 );
}

##
# Print this Site in the detailed format in HTML
# $showPrivateCustomizationPoints: unless true, blank out the values of private customizationpoints
sub printHtmlDetail {
    my $self                           = shift;
    my $showPrivateCustomizationPoints = shift;

    return $self->printHtml( 3, $showPrivateCustomizationPoints );
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
        if( ref( $json->{admin}->{credential} ) || $json->{admin}->{credential} !~ m!^\S[\S ]{4,30}\S$! ) {
            # Use same regex as in Createsite
            $@ = 'Site JSON: admin section: invalid credential, must be string of at least 6 characters without leading or trailing white space.';
            return 0;
        }
    }
    unless( $json->{admin}->{email} ) {
        $@ = 'Site JSON: admin section: missing email';
        return 0;
    }
    if( ref( $json->{admin}->{email} ) || $json->{admin}->{email} !~ m/^[A-Z0-9._%+-]+@[A-Z0-9-]+\.[A-Z0-9.-]*[A-Z]$/i ) {
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
            if( $fillInTemplate ) {
                if( !exists( $json->{tls}->{key} )) {
                    if( exists( $json->{tls}->{crt} )) {
                        $@ = 'Site JSON: tls section: cannot specify crt if no key is given in template mode';
                        return 0;
                    }
                } elsif( !exists( $json->{tls}->{crt} )) {
                    $@ = 'Site JSON: tls section: cannot specify key if no crt is given in template mode';
                    return 0;
                }

                my $tmpDir = UBOS::Host::vars()->getResolve( 'host.tmp', '/tmp' );
                my $dir    = File::Temp->newdir( DIR => $tmpDir );
                chmod 0700, $dir;

                my $err;
                if( UBOS::Utils::myexec( "openssl genrsa -out '$dir/key' 4096 ", undef, undef, \$err )) {
                    fatal( 'openssl genrsa failed', $err );
                }
                debugAndSuspend( 'Keys generated, CSR is next' );
                if( UBOS::Utils::myexec( "openssl req -new -key '$dir/key' -out '$dir/csr' -batch -subj '/CN=" . $json->{hostname} . "'", undef, undef, \$err )) {
                    fatal( 'openssl req failed', $err );
                }
                debugAndSuspend( 'CRT generated, CRT is next' );
                if( UBOS::Utils::myexec( "openssl x509 -req -days 3650 -in '$dir/csr' -signkey '$dir/key' -out '$dir/crt'", undef, undef, \$err )) {
                    fatal( 'openssl x509 failed', $err );
                }
                $json->{tls}->{key} = UBOS::Utils::slurpFile( "$dir/key" );
                $json->{tls}->{crt} = UBOS::Utils::slurpFile( "$dir/crt" );

                debugAndSuspend( 'CRT generated, cleaning up' );
                UBOS::Utils::deleteFile( "$dir/key", "$dir/csr", "$dir/crt" );
            }

            if( !$json->{tls}->{key} || ref( $json->{tls}->{key} )) {
                $@ = 'Site JSON: tls section: missing or invalid key';
                return 0;
            }
            if( !$json->{tls}->{crt} || ref( $json->{tls}->{crt} )) {
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
        # Compare with manifest checking in apache2.pm -- partially similar
        unless( ref( $json->{wellknown} ) eq 'HASH' ) {
            $@ = 'Site JSON: wellknown section: not a JSON object';
            return 0;
        }

        foreach my $wellknownKey ( keys %{$json->{wellknown}} ) {
            unless( $wellknownKey =~ m!^[-_.a-zA-Z0-9]+$! ) {
                $@ = 'Site JSON: wellknown section: invalid key: ' . $wellknownKey;
                return 0;
            }
            my $wellknownValue = $json->{wellknown}->{$wellknownKey};

            if( exists( $wellknownValue->{value} )) {
                if( ref( $wellknownValue->{value} )) {
                    $@ = 'Site JSON: wellknown section: value for ' . $wellknownKey . ' is not a string';
                    return 0;
                }
                if( exists( $wellknownValue->{location} )) {
                    $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' must not define both value and location';
                    return 0;
                }
                if( exists( $wellknownValue->{status} )) {
                    $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' must not define both value and status';
                    return 0;
                }
                if( exists( $wellknownValue->{prefix} )) {
                    $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' must not define both value and prefix';
                    return 0;
                }
                if( exists( $wellknownValue->{encoding} ) && $wellknownValue->{encoding} ne 'base64' ) {
                    $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' specifies invalid encoding: ' . $wellknownValue->{encoding};
                    return 0;
                }

            } elsif( exists( $wellknownValue->{location} )) {
                if( ref( $wellknownValue->{value} )) {
                    $@ = 'Site JSON: wellknown section: location for ' . $wellknownKey . ' is not a string';
                    return 0;
                }
                if( exists( $wellknownValue->{encoding} )) {
                    $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' must not define both location and encoding';
                    return 0;
                }
                if( exists( $wellknownValue->{status} )) {
                    unless( $wellknownValue->{status} =~ m!^3\d\d$! ) {
                        $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' has invalid status: ' . $wellknownValue->{status};
                        return 0;
                    }
                }
            } elsif( 'robots.txt' eq $wellknownKey ) {
                unless( exists( $wellknownValue->{prefix} )) {
                    $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' must specify either value, location or prefix';
                    return 0;
                }
                if( ref( $wellknownValue->{prefix} )) {
                    $@ = 'Site JSON: wellknown section: prefix for ' . $wellknownKey . ' is not a string';
                    return 0;
                }
                if( exists( $wellknownValue->{status} )) {
                    $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' must not define both prefix and status';
                    return 0;
                }
            } else {
                $@ = 'Site JSON: wellknown section: ' . $wellknownKey . ' specifies neither value nor location';
                return 0;
            }
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
                    if( exists( $installables{$accessoryId} )) {
                        $@ = "Site JSON: appconfig $i: accessory is listed more than once: " . $accessoryId;
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
        if( @$context >= 1 && $context->[-1] eq 'customizationpoints' ) {
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
        } elsif( @$context >= 1 && $context->[-1] eq 'wellknown' ) {
            # This is a well-known file name, which has laxer rules and we check separately
            foreach my $key ( keys %$json ) {
                my $value = $json->{$key};

                unless( $self->_checkJsonValidKeys( $value, [ @$context, $key ] )) {
                    return 0;
                }
            }
        } else {
            foreach my $key ( keys %$json ) {
                my $value = $json->{$key};

                unless( $key =~ m!^[a-z][a-z0-9]*$! ) {
                    $@ = 'Site JSON: invalid key (0) in JSON: ' . "'$key'" . ' context: ' . ( join( ' / ', @$context ) || '(top)' );
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
