#!/usr/bin/perl
#
# Represents an AppConfiguration on a Site.
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

package UBOS::AppConfiguration;

use UBOS::Accessory;
use UBOS::App;
use UBOS::Host;
use UBOS::Logging;
use JSON;
use MIME::Base64;

use fields qw{json site app accessories config};

my $APPCONFIGPARSDIR = '/var/lib/ubos/appconfigpars';

##
# Constructor.
# $json: JSON object containing one appconfig section of a Site JSON
# $site: Site object representing the site that this AppConfiguration belongs to
# return: AppConfiguration object
sub new {
    my $self = shift;
    my $json = shift;
    my $site = shift; # this may be undef when restoring from backup

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{json}   = $json;
    $self->{site}   = $site;
    $self->{config} = undef; # initialized when needed

    # No checking required, UBOS::Site::new has done that already
    return $self;
}

##
# Obtain identifier of this AppConfiguration.
# return: string
sub appConfigId {
    my $self = shift;

    return $self->{json}->{appconfigid};
}

##
# Obtain the AppConfiguration JSON
# return: AppConfiguration JSON
sub appConfigurationJson {
    my $self = shift;

    return $self->{json};
}

##
# Obtain the Site object that this AppConfiguration belongs to.
# return: Site object
sub site {
    my $self = shift;

    return $self->{site};
}

##
# Determine whether this AppConfiguration is the default AppConfiguration at this Site.
# return: 0 or 1
sub isDefault {
    my $self = shift;

    my $isDefault = $self->{json}->{isdefault};
    if( defined( $isDefault ) && JSON::is_bool( $isDefault ) && $isDefault ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Obtain the relative URL without trailing slash.
# return: relative URL
sub context {
    my $self = shift;

    $self->_initialize();

    my $ret = $self->{app}->fixedContext();
    unless( defined( $ret )) {
        $ret = $self->{json}->{context};
    }
    unless( defined( $ret )) {
        $ret = $self->{app}->defaultContext();
    }
    return $ret;
}

##
# Obtain the relative URL without trailing slash, except return / if root of site.
# This makes some Apache configurations simpler.
# return: relative URL
sub contextOrSlash {
    my $self = shift;

    my $ret = $self->context;
    unless( $ret ) {
        $ret = '/';
    }
    return $ret;
}

##
# Obtain the relative URL without leading or trailing slash, except return
# ROOT if root of site. This implements the Tomcat convention.
# return: relative URL
sub contextNoSlashOrRoot {
    my $self = shift;

    my $ret = $self->context;
    if( $ret ) {
        $ret =~ s!^/!!;
    } else {
        $ret = 'ROOT';
    }
    return $ret;
}

##
# Obtain the app at this AppConfiguration.
# return: the App
sub app {
    my $self = shift;

    $self->_initialize();

    return $self->{app};
}

##
# Obtain the accessories at this AppConfiguration, if there are any.
# return: list of Accessory
sub accessories {
    my $self = shift;

    $self->_initialize();

    return @{$self->{accessories}};
}
    
##
# Obtain the installables at this AppConfiguration.
# return: list of Installable
sub installables {
    my $self = shift;

    $self->_initialize();

    return ( $self->{app}, @{$self->{accessories}} );
}

##
# Obtain the instantiated customization points for this AppConfiguration
# return: customization points hierarchy as given in the site JSON
sub customizationPoints {
    my $self = shift;

    return $self->{json}->{customizationpoints};
}

##
# Obtain the resolved customization points for this AppConfiguration.
# These are the provided values in the site JSON, plus, when none are
# given, the defaults from the Installable's manifest.
# return: customization points hierarchy as given in the site JSON, but with
#         default values filled in
sub resolvedCustomizationPoints {
    my $self = shift;

    my $ret                 = {};
    my $appConfigCustPoints = $self->customizationPoints();

    foreach my $installable ( $self->installables ) {
        my $packageName           = $installable->packageName;
        my $installableCustPoints = $installable->customizationPoints;
        
        if( $installableCustPoints ) {
            foreach my $custPointName ( keys %$installableCustPoints ) {
                my $custPointDef = $installableCustPoints->{$custPointName};

                # check data type
                my $value = $appConfigCustPoints->{$packageName}->{$custPointName}->{value};
                if( defined( $value )) {
                    $ret->{$packageName}->{$custPointName}->{value} = $value;
                } else {
                    $ret->{$packageName}->{$custPointName}->{value} = $custPointDef->{default}->{value};
                }
            }
        }
    }

    return $ret;
}

##
# Obtain the Configuration object
# return: the Configuration object
sub config {
    my $self = shift;

    unless( $self->{config} ) {
        my $site        = $self->site();
        my $appConfigId = $self->appConfigId();
        $self->{config} = new UBOS::Configuration(
                    "AppConfiguration=$appConfigId",
                    {
                        "appconfig.appconfigid"          => $appConfigId,
                        "appconfig.context"              => $self->context(),
                        "appconfig.contextorslash"       => $self->contextOrSlash(),
                        "appconfig.contextnoslashorroot" => $self->contextNoSlashOrRoot()
                    },
                    defined( $site ) ? $site->config : undef );
    }

    return $self->{config};
}

##
# Determine whether this AppConfiguration needs a particular role
# $role: the role to check for
# return: true or false
sub needsRole {
    my $self = shift;
    my $role = shift;

    my @installables = $self->installables();
    foreach my $installable ( @installables ) {
        if( $installable->needsRole( $role )) {
            return 1;
        }
    }
    return 0;
}

##
# Before deploying, check whether this AppConfiguration would be deployable
# If not, this invocation never returns
sub checkDeployable {
    my $self = shift;

    $self->_deployOrCheck( 0 );
}

##
# Deploy this AppConfiguration.
sub deploy {
    my $self = shift;

    $self->_deployOrCheck( 1 );
}

##
# Deploy this AppConfiguration, or just check whether it is deployable. Both functions
# share the same code, so the checks get updated at the same time as the
# actual deployment.
# $doIt: if 1, deploy; if 0, only check
# return: success or fail
sub _deployOrCheck {
    my $self = shift;
    my $doIt = shift;

    $self->_initialize();

    unless( $self->{site} ) {
        fatal( 'Cannot deploy AppConfiguration without site' );
    }
    my $ret             = 1;
    my $siteDocumentDir = $self->config->getResolve( 'site.apache2.sitedocumentdir', undef, 1 );

    my @rolesOnHost = UBOS::Host::rolesOnHostInSequence();
    if( $doIt && $siteDocumentDir ) {
        foreach my $role ( @rolesOnHost ) {
            if( $self->needsRole( $role )) {
                my $roleName = $role->name();
                my $dir      = $self->config->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );
                if( $dir && $dir ne $siteDocumentDir ) {
                    UBOS::Utils::mkdir( $dir, 0755 );
                }
            }
        }
    }

    my $appConfigId = $self->appConfigId;
    if( $doIt ) {
        UBOS::Utils::mkdir( "$APPCONFIGPARSDIR/$appConfigId" );
    }

    my @installables = $self->installables();
    foreach my $installable ( @installables ) {
        my $packageName = $installable->packageName;

        my $config = new UBOS::Configuration(
                "Installable=$packageName,AppConfiguration=$appConfigId",
                {},
                $installable->config,
                $self->config );

        # Customization points for this Installable at this AppConfiguration

        if( $doIt ) {
            UBOS::Utils::mkdir( "$APPCONFIGPARSDIR/$appConfigId/$packageName" );
        }

        $self->_addCustomizationPointValuesToConfig( $config, $installable, $doIt );

        # Now for all the roles
        foreach my $role ( @rolesOnHost ) {
            if( $installable->needsRole( $role )) {
                $ret &= $role->deployOrCheck( $doIt, $self, $installable, $config );
            }
        }
    }
    return $ret;
}

##
# Undeploy this AppConfiguration, or just check whether it is undeployable. Both functions
# share the same code, so the checks get updated at the same time as the
# actual deployment.
# $doIt: if 1, undeploy; if 0, only check
sub _undeployOrCheck {
    my $self = shift;
    my $doIt = shift;

    $self->_initialize();

    unless( $self->{site} ) {
        fatal( 'Cannot undeploy AppConfiguration without site' );
    }

    my $ret                = 1;
    my @reverseRolesOnHost = reverse UBOS::Host::rolesOnHostInSequence();

    my $appConfigId = $self->appConfigId;

    # faster to do a simple recursive delete, instead of going point by point
    if( $doIt ) {
        UBOS::Utils::deleteRecursively( "$APPCONFIGPARSDIR/$appConfigId" );
    }

    my @installables = $self->installables();

    foreach my $installable ( reverse @installables ) {
        my $packageName = $installable->packageName;

        my $config = new UBOS::Configuration(
                "Installable=$packageName,AppConfiguration=$appConfigId",
                {},
                $installable->config,
                $self->config );

        $self->_addCustomizationPointValuesToConfig( $config, $installable );

        # Now for all the roles
        foreach my $role ( @reverseRolesOnHost ) {
            if( $installable->needsRole( $role )) {
                $ret &= $role->undeployOrCheck( $doIt, $self, $installable, $config );
            }
        }
    }

    my $siteDocumentDir = $self->config->getResolve( 'site.apache2.sitedocumentdir', undef, 1 );
    if( $doIt && $siteDocumentDir ) {
        foreach my $role ( @reverseRolesOnHost ) {
            if( $self->needsRole( $role )) {
                my $roleName = $role->name;
                my $dir      = $self->config->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );

                if( $dir && $dir ne $siteDocumentDir ) {
                    UBOS::Utils::rmdir( $dir );
                }
            }
        }
    }
    return $ret;
}

##
# Run the installer(s) for the app at this AppConfiguration
# return: success or fail
sub runInstaller {
    my $self = shift;

    return $self->_runPostDeploy( 'installers', 'install' );
}

##
# Run the upgrader(s) for the app at this AppConfiguration
# return: success or fail
sub runUpgrader {
    my $self = shift;

    return $self->_runPostDeploy( 'upgraders', 'upgrade' );
}

##
# Common code for running installers, uninstallers and upgraders
# $jsonSection: name of the JSON section that holds the script(s)
# $methodName: name of the method on AppConfigurationItem to invoke
# return: success or fail
sub _runPostDeploy {
    my $self        = shift;
    my $jsonSection = shift;
    my $methodName  = shift;

    debug( 'AppConfiguration', $self->{json}->{appconfigid}, '->_runPostDeploy', $methodName );

    unless( $self->{site} ) {
        fatal( 'Cannot _runPostDeploy AppConfiguration without site' );
    }

    my $ret          = 1;
    my @rolesOnHost  = UBOS::Host::rolesOnHostInSequence();
    my $appConfigId  = $self->appConfigId;
    my @installables = $self->installables();

    foreach my $installable ( @installables ) {
        my $packageName = $installable->packageName;

        my $config = new UBOS::Configuration(
                "Installable=$packageName,AppConfiguration=$appConfigId",
                {},
                $installable->config,
                $self->config );

        $self->_addCustomizationPointValuesToConfig( $config, $installable );

        foreach my $role ( @rolesOnHost ) {
            if( $self->needsRole( $role )) {
                my $roleName  = $role->name();
                my $itemsJson = $installable->installableJson->{roles}->{$roleName}->{$jsonSection};

                unless( $itemsJson ) {
                    next;
                }

                my $codeDir = $config->getResolve( 'package.codedir' );
                my $dir     = $self->config->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );

                foreach my $itemJson ( @$itemsJson ) {
                    my $item = $role->instantiateAppConfigurationItem( $itemJson, $self, $installable );

                    if( $item ) {
                        $ret &= $item->runPostDeployScript( $methodName, $codeDir, $dir, $config );
                    }
                }
            }
        }
    }
    return $ret;
}

##
# Internal helper to initialize the on-demand app field
# return: the App
sub _initialize {
    my $self = shift;

    if( defined( $self->{app} )) {
        return 1;
    }

    $self->{app} = new UBOS::App( $self->{json}->{appid} );

    if( $self->{json}->{accessoryids} ) {
        my @acc = map { new UBOS::Accessory( $_ ) } @{$self->{json}->{accessoryids}};
        $self->{accessories} = \@acc;
        
    } else {
        $self->{accessories} = [];
    }

    return 1;
}

##
# Internal helper to add the applicable customization point values to the $config object.
# This is factored out because it is used in several places.
# $config: the Configuration object
# $installable: the installable whose customization points values are to be added
# $save: if true, save the value to the file as well
sub _addCustomizationPointValuesToConfig {
    my $self        = shift;
    my $config      = shift;
    my $installable = shift;
    my $save        = shift || 0;
    
    my $installableCustPoints = $installable->customizationPoints;
    if( $installableCustPoints ) {
        my $packageName         = $installable->packageName;
        my $appConfigId         = $self->appConfigId;
        my $appConfigCustPoints = $self->customizationPoints();

        foreach my $custPointName ( keys %$installableCustPoints ) {
            my $custPointDef = $installableCustPoints->{$custPointName};

            my $value = $appConfigCustPoints->{$packageName}->{$custPointName};

            unless( defined( $value ) && defined( $value->{value} )) {
                # use default instead
                $value = $custPointDef->{default};
            }
            if( defined( $value )) {
                my $data = $value->{value};
                if( defined( $data )) { # value might be null
                    if( defined( $value->{encoding} ) && $value->{encoding} eq 'base64' ) {
                        $data = decode_base64( $data );
                    }
                    my $filename = "$APPCONFIGPARSDIR/$appConfigId/$packageName/$custPointName";
                    if( $save ) {
                        UBOS::Utils::saveFile( $filename, $data );
                    }

                    $config->put( 'installable.customizationpoints.' . $custPointName . '.filename', $filename );
                    $config->put( 'installable.customizationpoints.' . $custPointName . '.value', $data );
                }
            }
        }
    }
}

##
# Static method to check whether a context path is syntactically valid.
# $context: context path
sub isValidContext {
    my $context = shift;

    if( $context =~ m!^(/[-_\.a-zA-Z0-9]+)?$! ) {
        return 1;
    } else {
        return 0;
    }
}

1;
