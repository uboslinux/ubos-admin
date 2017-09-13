#!/usr/bin/perl
#
# Represents an AppConfiguration on a Site.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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
use UBOS::Configuration;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Subconfiguration;
use JSON;
use MIME::Base64;

use fields qw{json skipFilesystemChecks manifestFileReader site app accessories config subconfigs};

my $APPCONFIGPARSDIR = '/var/lib/ubos/appconfigpars';

##
# Constructor.
# $json: JSON object containing one appconfig section of a Site JSON
# $site: Site object representing the site that this AppConfiguration belongs to
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# $manifestFileReader: pointer to a method that knows how to read manifest files
# return: AppConfiguration object
sub new {
    my $self                 = shift;
    my $json                 = shift;
    my $site                 = shift; # this may be undef when restoring from backup
    my $skipFilesystemChecks = shift;
    my $manifestFileReader   = shift || \&UBOS::Host::defaultManifestFileReader;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{json}                 = $json;
    $self->{skipFilesystemChecks} = $skipFilesystemChecks;
    $self->{manifestFileReader}   = $manifestFileReader;
    $self->{site}                 = $site;
    $self->{config}               = undef; # initialized when needed
    $self->{subconfigs}           = {};

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
# Obtain the installable at this AppCOnfiguration with the provided name
# $package: name of the package
# return: installable, or undef
sub installable {
    my $self    = shift;
    my $package = shift;

    my @installables = $self->installables();
    for my $installable ( @installables ) {
        if( $installable->packageName() eq $package ) {
            return $installable;
        }
    }
    return undef;
}

##
# Obtain the package names of the installables at this AppConfiguration.
# return: list of package names
sub installablesPackages {
    my $self = shift;

    # avoid going through instantiating App and Accessory, so we can
    # determine the answer without having the packages installed

    my @ret = ( $self->{json}->{appid} );

    if( $self->{json}->{accessoryids} ) {
        push @ret, @{$self->{json}->{accessoryids}};
    }
    return @ret;
}

##
# Obtain the instantiated customization points for this AppConfiguration
# return: customization points hierarchy as given in the site JSON
sub customizationPoints {
    my $self = shift;

    if( exists( $self->{json}->{customizationpoints} )) {
        return $self->{json}->{customizationpoints};
    } else {
        return undef;
    }
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
                my $value = undef;
                if(    exists( $appConfigCustPoints->{$packageName} )
                    && exists( $appConfigCustPoints->{$packageName}->{$custPointName} )
                    && exists( $appConfigCustPoints->{$packageName}->{$custPointName}->{value} ))
                {
                    $value = $appConfigCustPoints->{$packageName}->{$custPointName}->{value};
                }
                if( defined( $value )) {
                    $ret->{$packageName}->{$custPointName}->{value} = $value;
                } elsif( defined( $custPointDef->{default}->{value} )) {
                    $ret->{$packageName}->{$custPointName}->{value} = $custPointDef->{default}->{value};
                } else {
                    $ret->{$packageName}->{$custPointName}->{value} = $self->config->replaceVariables( $custPointDef->{default}->{expression} );
                }
            }
        }
    }

    return $ret;
}

##
# Obtain the definition of the customization point
# $packageName: name of the package that defines the customization point
# $customizationPointName: name of the customization point
# return: JSON fragment from the installable's JSON
sub customizationPointDefinition {
    my $self                   = shift;
    my $packageName            = shift;
    my $customizationPointName = shift;

    foreach my $installable ( $self->installables ) {
        if( $installable->packageName eq $packageName ) {
            my $custPoints = $installable->customizationPoints;
            if( defined( $custPoints ) && exists( $custPoints->{$customizationPointName} )) {
                return $custPoints->{$customizationPointName};
            }
        }
    }
    warning( 'Cannot find customization point', $customizationPointName, 'in package', $packageName );
    return undef;
}

##
# Obtain the Configuration object
# return: the Configuration object
sub config {
    my $self = shift;

    unless( $self->{config} ) {
        my $site        = $self->site();
        my $appConfigId = $self->appConfigId();

        my $appId        = $self->{json}->{appid};
        my $accessoryIds = $self->{json}->{accessoryids};

        $self->{config} = UBOS::Configuration->new(
                    "AppConfiguration=$appConfigId",
                    {
                        "appconfig.appid"                => $appId,
                        "appconfig.accessoryids"         => defined( $accessoryIds ) ? join( ',', @$accessoryIds ) : '',
                        "appconfig.appconfigid"          => $appConfigId,
                        "appconfig.context"              => $self->context(),
                        "appconfig.contextorslash"       => $self->contextOrSlash(),
                        "appconfig.contextnoslashorroot" => $self->contextNoSlashOrRoot()
                    },
                    $site );
    }
    return $self->{config};
}

##
# Smart factory to always return the same sub-Configuration objects.
# $name: name of the sub-configuration; must be consistent as it is used as the key
# @delegates: more objects that have config() methods that may be used to resolve unknown variables
# return: new or reused Configuration object
sub obtainSubconfig {
    my $self      = shift;
    my $name      = shift;
    my @delegates = @_;

    my $ret;
    if( exists( $self->{subconfigs}->{$name} )) {
        $ret = $self->{subconfigs}->{$name};
    } else {
        $ret = UBOS::Subconfiguration->new(
                "$name,AppConfiguration=" . $self->appConfigId,
                $self,
                @delegates );
        $self->{subconfigs}->{$name} = $ret;
    }
    return $ret;
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
# $triggers: triggers to be executed may be added to this hash
# return: success or fail
sub deployOrCheck {
    my $self     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    trace( 'AppConfiguration::deployOrCheck', $doIt, $self->appConfigId );

    $self->_initialize();

    my $ret = 1;

    my $appConfigId = $self->appConfigId;
    if( $doIt ) {
        UBOS::Utils::mkdir( "$APPCONFIGPARSDIR/$appConfigId" );
    }

    # make sure we don't deploy to an invalid context
    my $app = $self->app();

    if(    defined( $app->fixedContext() )
        && defined( $self->{json}->{context} )
        && $self->{app}->fixedContext() ne $self->{json}->{context} )
    {
        error( 'Cannot deploy fixed-context app', $app->packageName, 'at context', $self->{json}->{context} );
        $ret = 0;
    }

    my @rolesOnHost  = UBOS::Host::rolesOnHostInSequence();
    my @installables = $self->installables();
    foreach my $installable ( @installables ) {
        my $packageName = $installable->packageName;

        foreach my $required ( $installable->requires()) {
            unless( grep { $required eq $_->packageName } @installables ) {
                error( 'Installable', $packageName, 'requires installable', $required, 'to be deployed to the same AppConfiguration' );
                $ret = 0;
            }
        }

        my $config = $self->obtainSubconfig(
                "Installable=$packageName",
                $installable );

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
# $triggers: triggers to be executed may be added to this hash
sub undeployOrCheck {
    my $self     = shift;
    my $doIt     = shift;
    my $triggers = shift;

    trace( 'AppConfiguration::undeployOrCheck', $doIt, $self->appConfigId );

    $self->_initialize();

    my $ret = 1;

    my $appConfigId = $self->appConfigId;

    # faster to do a simple recursive delete, instead of going point by point
    if( $doIt ) {
        UBOS::Utils::deleteRecursively( "$APPCONFIGPARSDIR/$appConfigId" );
    }

    my @reverseRolesOnHost  = reverse UBOS::Host::rolesOnHostInSequence();
    my @reverseInstallables = reverse $self->installables();
    foreach my $installable ( @reverseInstallables ) {
        my $packageName = $installable->packageName;

        my $config = $self->obtainSubconfig(
                "Installable=$packageName",
                $installable );

        $self->_addCustomizationPointValuesToConfig( $config, $installable );

        # Now for all the roles
        foreach my $role ( @reverseRolesOnHost ) {
            if( $installable->needsRole( $role )) {
                $ret &= $role->undeployOrCheck( $doIt, $self, $installable, $config );
            }
        }
    }

    return $ret;
}

##
# Suspend this AppConfiguration.
# $triggers: triggers to be executed may be added to this hash
sub suspend {
    my $self     = shift;
    my $triggers = shift;

    trace( 'AppConfiguration::suspend', $self->appConfigId );

    $self->_initialize();

    my $ret = 1;

    my $appConfigId = $self->appConfigId;

    my @reverseRolesOnHost  = reverse UBOS::Host::rolesOnHostInSequence();
    my @reverseInstallables = reverse $self->installables();
    foreach my $installable ( @reverseInstallables ) {
        my $packageName = $installable->packageName;

        my $config = $self->obtainSubconfig(
                "Installable=$packageName",
                $installable );

        $self->_addCustomizationPointValuesToConfig( $config, $installable );

        # Now for all the roles
        foreach my $role ( @reverseRolesOnHost ) {
            if( $installable->needsRole( $role )) {
                $ret &= $role->suspend( $self, $installable, $config );
            }
        }
    }

    return $ret;
}

##
# Resume this AppConfiguration.
# $triggers: triggers to be executed may be added to this hash
sub resume {
    my $self     = shift;
    my $triggers = shift;

    trace( 'AppConfiguration::resume', $self->appConfigId );

    $self->_initialize();

    my $ret = 1;

    my $appConfigId = $self->appConfigId;

    my @rolesOnHost  = UBOS::Host::rolesOnHostInSequence();
    my @installables = $self->installables();
    foreach my $installable ( @installables ) {
        my $packageName = $installable->packageName;

        my $config = $self->obtainSubconfig(
                "Installable=$packageName",
                $installable );

        $self->_addCustomizationPointValuesToConfig( $config, $installable );

        # Now for all the roles
        foreach my $role ( @rolesOnHost ) {
            if( $installable->needsRole( $role )) {
                $ret &= $role->resume( $self, $installable, $config );
            }
        }
    }

    return $ret;
}

##
# Run the installer(s) for the app at this AppConfiguration
# return: success or fail
sub runInstallers {
    my $self = shift;

    return $self->_runPostDeploy( 'installers', 'install' );
}

##
# Run the upgrader(s) for the app at this AppConfiguration
# return: success or fail
sub runUpgraders {
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

    trace( 'AppConfiguration', $self->{json}->{appconfigid}, '->_runPostDeploy', $methodName );

    unless( $self->{site} ) {
        fatal( 'Cannot _runPostDeploy AppConfiguration without site' );
    }

    my $ret          = 1;
    my @rolesOnHost  = UBOS::Host::rolesOnHostInSequence();
    my $appConfigId  = $self->appConfigId;
    my @installables = $self->installables();

    foreach my $installable ( @installables ) {
        my $packageName = $installable->packageName;

        my $config = $self->obtainSubconfig(
                "Installable=$packageName",
                $installable );

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

                my $itemCount = 0;
                foreach my $itemJson ( @$itemsJson ) {
                    my $item = $role->instantiateAppConfigurationItem( $itemJson, $self, $installable );

                    if( $item ) {
                        debugAndSuspend(
                                'Run post-deploy script', $itemCount,
                                'method',                 $methodName,
                                'in',                     $jsonSection,
                                'with role',              $role,
                                'of installable',         $installable,
                                'at appconfig',           $appConfigId );
                        $ret &= $item->runPostDeployScript( $methodName, $codeDir, $dir, $config );
                    }
                    ++$itemCount;
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

    $self->{app} = UBOS::App->new( $self->{json}->{appid}, $self->{skipFilesystemChecks}, $self->{manifestFileReader} );

    if( $self->{json}->{accessoryids} ) {
        my @acc = map
                  { UBOS::Accessory->new( $_, $self->{skipFilesystemChecks}, $self->{manifestFileReader} ) }
                  @{$self->{json}->{accessoryids}};
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
            if( $config->get( 'installable.customizationpoints.' . $custPointName . '.value' )) {
                # no need to do it again
                next;
            }

            my $custPointDef = $installableCustPoints->{$custPointName};

            my $value = $appConfigCustPoints->{$packageName}->{$custPointName};

            unless( defined( $value ) && defined( $value->{value} )) {
                # use default instead
                $value = $custPointDef->{default};
            }
            if( defined( $value )) {
                my $data = undef;
                if( exists( $value->{value} )) {
                    $data = $value->{value};
                    if( defined( $data )) { # value might be null
                        if( defined( $value->{encoding} ) && $value->{encoding} eq 'base64' ) {
                            $data = decode_base64( $data );
                        }
                    }

                } elsif( exists( $value->{expression} )) {
                    $data = $value->{expression};
                    $data = $self->config->replaceVariables( $data );
                }
                if( defined( $data ) && ( !exists( $installableCustPoints->{private} ) || !$installableCustPoints->{private} )) {
                    # do not generate the file in case of null data, or if customizationpoint is declared private
                    my $filename = "$APPCONFIGPARSDIR/$appConfigId/$packageName/$custPointName";
                    if( $save ) {
                        UBOS::Utils::saveFile( $filename, $data );
                    }
                    $config->put( 'installable.customizationpoints.' . $custPointName . '.filename', $filename );
                }
                $config->put( 'installable.customizationpoints.' . $custPointName . '.value', $data );
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

##
# Check that all required customization point values have been specified.
# If not, fatal out.
sub checkCustomizationPointValues {
    my $self = shift;

    my $appConfigCustPoints = $self->customizationPoints();
    foreach my $installable ( $self->installables ) {
        my $packageName           = $installable->packageName;
        my $installableCustPoints = $installable->customizationPoints;
        if( $installableCustPoints ) {
            foreach my $custPointName ( keys %$installableCustPoints ) {
                my $custPointDef = $installableCustPoints->{$custPointName};

                # check data type
                my $value = undef;
                if(    exists( $appConfigCustPoints->{$packageName} )
                    && exists( $appConfigCustPoints->{$packageName}->{$custPointName} )
                    && exists( $appConfigCustPoints->{$packageName}->{$custPointName}->{value} ))
                {
                    $value = $appConfigCustPoints->{$packageName}->{$custPointName}->{value};
                    if( defined( $value )) {
                        my $knownCustomizationPointTypes = $UBOS::Installable::knownCustomizationPointTypes;
                        my $custPointValidation = $knownCustomizationPointTypes->{ $custPointDef->{type}};
                        # checked earlier that this is non-null
                        unless( $custPointValidation->{valuecheck}->( $value, $custPointDef )) {
                            fatal(   'AppConfiguration ' . $self->appConfigId
                                   . ', package ' . $packageName
                                   . ', ' . $custPointValidation->{valuecheckerror} . ': ' . $custPointName
                                   . ', is ' . ( ref( $value ) || $value ));
                        }
                    }
                }

                # now check that required values are indeed provided
                unless( $custPointDef->{required} ) {
                    next;
                }
                if(    !defined( $custPointDef->{default} )
                    || !( defined( $custPointDef->{default}->{value} ) || defined( $custPointDef->{default}->{expression} ))) {
                    # make sure the Site JSON file provided one
                    unless( defined( $value )) {
                        fatal(   'AppConfiguration ' . $self->appConfigId
                               . ', package ' . $packageName
                               . ', required value not provided for customizationpoint: ' .  $custPointName );
                    }
                }
            }
        }
    }
    1;
}

##
# Print this appconfiguration in human-readable form.
# $detail: 1: only appconfigid,
#          2: plus app, accessories,
#          3: plus customizationpoints
sub print {
    my $self   = shift;
    my $detail = shift || 2;

    if( $detail <= 1 ) {
        print $self->appConfigId . "\n";

    } else {
        print "AppConfiguration: ";

        if( $self->context ) {
            print $self->context;
        } else {
            print '<root>';
        }

        print " (" . $self->appConfigId . ")";

        if( $detail < 3 ) {
            print ': ' . $self->app->packageName;
            foreach my $acc ( $self->accessories ) {
                print ' ' . $acc->packageName;
            }
            print "\n";
        } else {
            print "\n";

            my $custPoints = $self->resolvedCustomizationPoints;
            foreach my $installable ( $self->installables ) {
                print '    ';
                if( $installable == $self->app ) {
                    print 'app:      ';
                } else {
                    print 'accessory: ';
                }
                print $installable->packageName . "\n";
                my $installableCustPoints = $custPoints->{$installable->packageName};
                if( defined( $installableCustPoints )) {
                    foreach my $custPointName ( sort keys %$installableCustPoints ) {
                        my $custPointValue = $installableCustPoints->{$custPointName};

                        print '         customizationpoint ' . $custPointName . ': ' . $custPointValue . "\n";
                    }
                }
            }
        }
    }
}

1;
