#!/usr/bin/perl
#
# Represents a Site, aka Virtual Host.
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

package UBOS::Site;

use UBOS::AppConfiguration;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;
use JSON;
use MIME::Base64;

use fields qw{json appConfigs config};

##
# Constructor.
# $json: JSON object containing Site JSON
# return: Site object
sub new {
    my $self = shift;
    my $json = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{json} = $json;
    $self->_checkJson();

    my $siteId    = $self->siteId();
    my $adminJson = $self->{json}->{admin};
    
    $self->{config} = new UBOS::Configuration(
                "Site=$siteId",
                {
                    "site.hostname"         => $self->hostName(),
                    "site.siteid"           => $siteId,
                    "site.protocol"         => ( $self->hasSsl() ? 'https' : 'http' ),
                    "site.admin.userid"     => $adminJson->{userid},
                    "site.admin.username"   => $adminJson->{username},
                    "site.admin.credential" => $adminJson->{credential},
                    "site.admin.email"      => $adminJson->{email}
                },
            UBOS::Host::config() );

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
# Obtain the site's host name.
# return: string
sub hostName {
    my $self = shift;

    return $self->{json}->{hostname};
}

##
# Obtain the Configuration object
# return: the Configuration object
sub config {
    my $self = shift;

    return $self->{config};
}

##
# Determine whether SSL data has been given.
# return: 0 or 1
sub hasSsl {
    my $self = shift;

    my $json = $self->{json};
    return ( defined( $json->{ssl} ) && defined( $json->{ssl}->{key} ) ? 1 : 0 );
}

##
# Obtain the SSL key, if any has been provided.
# return: the SSL key
sub sslKey {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{ssl} )) {
        return $json->{ssl}->{key};
    } else {
		return undef;
	}
}

##
# Obtain the SSL certificate, if any has been provided.
# return: the SSL certificate
sub sslCert {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{ssl} )) {
        return $json->{ssl}->{crt};
    } else {
		return undef;
	}
}

##
# Obtain the SSL certificate chain, if any has been provided.
# return: the SSL certificate chain
sub sslCertChain {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{ssl} )) {
        return $json->{ssl}->{crtchain};
    } else {
		return undef;
	}
}

##
# Obtain the SSL certificate chain to be used with clients, if any has been provided.
sub sslCaCert {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{ssl} )) {
        return $json->{ssl}->{cacrt};
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
    if( defined( $json->{wellknown} )) {
        return $json->{wellknown}->{robotstxt};
    } else {
		return undef;
	}
}

##
# Obtain the beginning of the site's robots.txt file content, if no robots.txt
# has been provided.
# return: prefix of robots.txt content
sub robotsTxtPrefix {
    my $self = shift;

    my $json = $self->{json};
    if( defined( $json->{wellknown} )) {
        return $json->{wellknown}->{robotstxtprefix};
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
    if( defined( $json->{wellknown} )) {
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
    if( defined( $json->{wellknown} )) {
        if( defined( $json->{wellknown}->{faviconicobase64} ) && $json->{wellknown}->{faviconicobase64} ) {
			return decode_base64( $self->{json}->{wellknown}->{faviconicobase64} );
		}
    }
    return undef;
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
            push @{$self->{appConfigs}}, new UBOS::AppConfiguration( $current, $self );
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
        if( $context eq $appConfig->context ) {
            return $appConfig;
        }
    }
    return undef;
}

##
# Print this site in human-readable form.
# $detail: 1: only siteid,
#          2: plus hostname, apps, accessories,
#          3: plus customizationpoints 
sub print {
    my $self   = shift;
    my $detail = shift || 2;

    if( $detail <= 1 ) {
        print $self->siteId . "\n";
        
    } else {
        print "Site";
        if( $self->hasSsl ) {
            print " (SSL)";
        }
        print ": " . $self->hostName;
        print " (" . $self->siteId . ")\n";
        if( $detail >= 2 ) {
            foreach my $isDefault ( 1, 0 ) {
                foreach my $appConfig ( @{$self->appConfigs} ) {
                    if( ( $isDefault && $appConfig->isDefault ) || ( !$isDefault && !$appConfig->isDefault )) {
                        print '    Context: ';

                        my $context = $appConfig->context;
                        if( $isDefault && $appConfig->isDefault ) {
                            print '(default) ';
                        } else {
                            print '          ';
                        }
                        if( $context ) {
                            print $context;
                        } else {
                            print '<root>';
                        }
                        print ' ('. $appConfig->appConfigId . ')';
                        if( $detail < 3 ) {
                            print ': ' . $appConfig->app->packageName;
                            foreach my $acc ( $appConfig->accessories ) {
                                print ' ' . $acc->packageName;
                            }
                            print "\n";
                        } else {
                            print "\n";
                            
                            my $custPoints = $appConfig->resolvedCustomizationPoints;
                            foreach my $installable ( $appConfig->installables ) {
                                print '          ';
                                if( $installable == $appConfig->app ) {
                                    print 'app:      ';
                                } else {
                                    print 'accessory: ';
                                }
                                print $installable->packageName . "\n";
                                my $installableCustPoints = $custPoints->{$installable->packageName};
                                if( defined( $installableCustPoints )) {
                                    while( my( $custPointName, $custPointValue ) = each %{$installableCustPoints} ) {
                                        print '                     customizationpoint ' . $custPointName . ': ' . $custPointValue . "\n";
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

    return $self->_deployOrCheck( 0 );
}

##
# Deploy this Site
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub deploy {
    my $self     = shift;
    my $triggers = shift;

    debug( 'Site', $self->siteId, '->deploy' );

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

    my $ret = 1;
    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->setupSiteOrCheck( $self, $doIt, $triggers );
        }
    }
    
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->_deployOrCheck( $doIt, $triggers );
    }

    if( $doIt ) {
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

    debug( 'Site', $self->siteId, '->undeploy' );

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

    my $ret = 1;
    foreach my $appConfig ( @{$self->appConfigs} ) {
        $ret &= $appConfig->_undeployOrCheck( $doIt, $triggers );
    }

    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
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
# Resume this Site from suspension
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub resume {
    my $self     = shift;
    my $triggers = shift;

    my $ret = 1;
    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    foreach my $role ( @rolesOnHost ) {
        if( $self->needsRole( $role )) {
            $ret &= $role->setupSite( $self, $triggers );
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
# Check validity of the Site JSON
# return: 1 or exits with fatal error
sub _checkJson {
    my $self = shift;
    my $json = $self->{json};

    unless( $json ) {
        fatal( 'No Site JSON present' );
    }
    $self->_checkJsonValidKeys( $json, [] );

    unless( $json->{siteid} ) {
        fatal( 'Site JSON: missing siteid' );
    }
    unless( ref( $json->{siteid} ) || $json->{siteid} =~ m/^s[0-9a-f]{40}$/ ) {
        fatal( 'Site JSON: invalid siteid, must be s followed by 40 hex chars' );
    }
    unless( $json->{hostname} ) {
        fatal( 'Site JSON: missing hostname' );
    }
    unless( ref( $json->{hostname} ) || $json->{hostname} =~ m/^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?)*\.?$/ ) {
        # regex from http://stackoverflow.com/a/1420225/200304
        fatal( 'Site JSON: invalid hostname' );
    }

    unless( $json->{admin} ) {
        fatal( 'Site JSON: admin section is now required' );
    }
    unless( ref( $json->{admin} ) eq 'HASH' ) {
        fatal( 'Site JSON: admin section: not a JSON object' );
    }
    unless( $json->{admin}->{userid} ) {
        fatal( 'Site JSON: admin section: missing userid' );
    }
    if( ref( $json->{admin}->{userid} ) || $json->{admin}->{userid} !~ m!^[a-z0-9]+$! ) {
        fatal( 'Site JSON: admin section: invalid userid, must be string without white space' );
    }
    unless( $json->{admin}->{username} ) {
        fatal( 'Site JSON: admin section: missing username' );
    }
    if( ref( $json->{admin}->{username} ) ) {
        fatal( 'Site JSON: admin section: invalid username, must be string' );
    }
    unless( $json->{admin}->{credential} ) {
        fatal( 'Site JSON: admin section: missing credential' );
    }
    if( ref( $json->{admin}->{credential} ) || $json->{admin}->{credential} =~ m!\s! ) {
        fatal( 'Site JSON: admin section: invalid credential, must be string without white space' );
    }
    unless( $json->{admin}->{email} ) {
        fatal( 'Site JSON: admin section: missing email' );
    }
    if( ref( $json->{admin}->{email} ) || $json->{admin}->{email} !~ m/^[A-Z0-9._%+-]+@[A-Z0-9.-]*[A-Z]$/i ) {
        fatal( 'Site JSON: admin section: invalid email' );
    }

    if( $json->{ssl} ) {
        unless( ref( $json->{ssl} ) eq 'HASH' ) {
            fatal( 'Site JSON: ssl section: not a JSON object' );
        }
        unless( $json->{ssl}->{key} || !ref( $json->{ssl}->{key} )) {
            fatal( 'Site JSON: ssl section: missing or invalid key' );
        }
        unless( $json->{ssl}->{crt} || !ref( $json->{ssl}->{crt} )) {
            fatal( 'Site JSON: ssl section: missing or invalid crt' );
        }
        unless( $json->{ssl}->{crtchain} || !ref( $json->{ssl}->{crtchain} )) {
            fatal( 'Site JSON: ssl section: missing or invalid crtchain' );
        }
        if( $json->{ssl}->{cacrt} && ref( $json->{ssl}->{cacrt} )) {
            fatal( 'Site JSON: ssl section: invalid cacrt' );
        }
    }

    if( $json->{wellknown} ) {
        unless( ref( $json->{wellknown} ) eq 'HASH' ) {
            fatal( 'Site JSON: wellknown section: not a JSON object' );
        }
        if( $json->{wellknown}->{robotstxt} && ref( $json->{wellknown}->{robotstxt} )) {
            fatal( 'Site JSON: wellknown section: invalid robotstxt' );
        }
        if(    $json->{wellknown}->{sitemapxml}
            && (    ref( $json->{wellknown}->{sitemapxml} )
                 || $json->{wellknown}->{sitemapxml} !~ m!^<\?xml! ))
        {
            fatal( 'Site JSON: wellknown section: invalid sitemapxml' );
        }
        if( $json->{wellknown}->{faviconicobase64} && ref( $json->{wellknown}->{faviconicobase64} )) {
            fatal( 'Site JSON: wellknown section: invalid faviconicobase64' );
        }
    }
    
    if( $json->{appconfigs} ) {
        unless( ref( $json->{appconfigs} ) eq 'ARRAY' ) {
            fatal( 'Site JSON: appconfigs section: not a JSON array' );
        }

        my $i=0;
        foreach my $appConfigJson ( @{$json->{appconfigs}} ) {
            unless( $appConfigJson->{appconfigid} ) {
                fatal( "Site JSON: appconfig $i: missing appconfigid" );
            }
            unless( ref( $appConfigJson->{appconfigid} ) || $appConfigJson->{appconfigid} =~ m/^a[0-9a-f]{40}$/ ) {
                fatal( "Site JSON: appconfig $i: invalid appconfigid, must be a followed by 40 hex chars" );
            }
            if(    $appConfigJson->{context}
                && (    ref( $appConfigJson->{context} ) || !UBOS::AppConfiguration::isValidContext( $appConfigJson->{context} )))
            {
                fatal( "Site JSON: appconfig $i: invalid context, must be valid context URL without trailing slash" );
            }
            if( $appConfigJson->{isdefault} && !JSON::is_bool( $appConfigJson->{isdefault} )) {
                fatal( "Site JSON: appconfig $i: invalid isdefault, must be true or false" );
            }
            unless( $appConfigJson->{appid} && !ref( $appConfigJson->{appid} )) {
                fatal( "Site JSON: appconfig $i: invalid appid" );
                # FIXME: format of this string must be better specified and checked
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
sub _checkJsonValidKeys {
    my $self    = shift;
    my $json    = shift;
    my $context = shift;
    
    if( ref( $json ) eq 'HASH' ) {
        if( @$context >= 2 && $context->[-1] eq 'customizationpoints' ) {
            # This is a package name, which has laxer rules
            while( my( $key, $value ) = each %$json ) {
                unless( $key =~ m!^[a-z][-_a-z0-9]*$! ) {
                    fatal( 'Site JSON: invalid key in JSON:', "'$key'", 'context:', join( ' / ', @$context ) || '(top)' );
                }
                $self->_checkJsonValidKeys( $value, [ @$context, $key ] );
            }
        } elsif( @$context >= 2 && $context->[-2] eq 'customizationpoints' ) {
            # This is a customization point name, which has laxer rules
            while( my( $key, $value ) = each %$json ) {
                unless( $key =~ m!^[a-z][_a-z0-9]*$! ) {
                    fatal( 'Site JSON: invalid key in JSON:', "'$key'", 'context:', join( ' / ', @$context ) || '(top)' );
                }
                $self->_checkJsonValidKeys( $value, [ @$context, $key ] );
            }
        } else {
            while( my( $key, $value ) = each %$json ) {
                unless( $key =~ m!^[a-z]+$! ) {
                    fatal( 'Site JSON: invalid key in JSON:', "'$key'", 'context:', join( ' / ', @$context ) || '(top)' );
                }
                $self->_checkJsonValidKeys( $value, [ @$context, $key ] );
            }
        }
    } elsif( ref( $json ) eq 'ARRAY' ) {
        foreach my $element ( @$json ) {
            $self->_checkJsonValidKeys( $element, $context );
        }
    }
}

1;
