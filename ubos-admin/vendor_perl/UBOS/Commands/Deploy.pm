#!/usr/bin/perl
#
# Command that deploys one or more sites.
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

package UBOS::Commands::Deploy;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Logging;
use UBOS::UpdateBackup;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $file          = undef;
    my $stdin         = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'file=s'      => \$file,
            'stdin'       => \$stdin );

    UBOS::Logging::initialize( 'ubos-admin', 'deploy', $verbose, $logConfigFile );

    if( !$parseOk || @args || ( $file && $stdin ) || ( !$file && !$stdin ) || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation: deploy', @_, '(add --help for help)' );
    }

    debug( 'Parsing site JSON and checking' );

    my $json;
    if( $file ) {
        $json = readJsonFromFile( $file );
        $json = UBOS::Utils::insertSlurpedFiles( $json, dirname( $file ) );
    } else {
        $json = readJsonFromStdin();
        $json = UBOS::Utils::insertSlurpedFiles( $json, getcwd() );
    }

    my $newSitesHash = {};
    if( ref( $json ) eq 'HASH' && %$json ) {
		if( defined( $json->{siteid} )) {
            $json = [ $json ];
        } else {
			my @newJson = ();
            map { push @newJson, $_ } values %$json;
            $json = \@newJson;
		}
    }

    if( ref( $json ) eq 'ARRAY' ) {
        if( !@$json ) {
            fatal( 'No site given' );

        } else {
            foreach my $siteJson ( @$json ) {
                my $site   = UBOS::Site->new( $siteJson );
                my $siteId = $site->siteId;
                if( $newSitesHash->{$siteId} ) {
                    fatal( "Duplicate site definition: $siteId" );
                }
                $newSitesHash->{$siteId} = $site;
            }
        }
    } else {
        fatal( "Not a Site JSON file" );
    }

    my $oldSites = UBOS::Host::sites();
    my @newSites = values %$newSitesHash;

    # make sure AppConfigIds, SiteIds and hostnames are unique, and that all Sites are deployable
    my $haveIdAlready   = {}; # it's okay that we have an old site by this id
    my $haveHostAlready = {}; # it's not okay that we have an old site by this hostname if site id is different
    
    foreach my $oldSite ( values %$oldSites ) {
        $haveHostAlready->{$oldSite->hostName} = $oldSite;
    }
    
    foreach my $newSite ( @newSites ) {
        my $newSiteId = $newSite->siteId;
        if( $haveIdAlready->{$newSiteId} ) {
            fatal( 'More than one site or appconfig with id', $newSiteId );
        }
        $haveIdAlready->{$newSiteId} = $newSite;

        my $newSiteHostName = $newSite->hostName;
        if( $haveHostAlready->{$newSiteHostName} && $newSiteId ne $haveHostAlready->{$newSiteHostName}->siteId ) {
            fatal( 'There is already a site with hostname', $newSiteHostName );
        }
        $haveHostAlready->{$newSiteHostName} = $newSite;

        foreach my $newAppConfig ( @{$newSite->appConfigs} ) {
            my $newAppConfigId = $newAppConfig->appConfigId;
            if( $haveIdAlready->{$newAppConfigId} ) {
                fatal( 'More than one site or appconfig with id', $newAppConfigId );
            }
            $haveIdAlready->{$newSiteId} = $newSite;
        
            foreach my $oldSite ( values %$oldSites ) {
                foreach my $oldAppConfig ( @{$oldSite->appConfigs} ) {
                    if( $newAppConfigId eq $oldAppConfig->appConfigId ) {
                        if( $newSiteId ne $oldSite->siteId ) {
                            fatal(    'Non-unique appconfigid ' . $newAppConfigId
                                    . ' in sites ' . $newSiteId . ' and ' . $oldSite->siteId );
                        }
                    }
                }
            }
        }

        my $oldSite = $oldSites->{$newSiteId};
        if( defined( $oldSite )) {
            $oldSite->checkUndeployable;
        }
    }

    # May not be interrupted, bad things may happen if it is
	UBOS::Host::preventInterruptions();
    my $ret = 1;

    unless( UBOS::UpdateBackup::checkReady() ) {
        fatal( 'Cannot backup; backup directory not empty' );
    }

    debug( 'Installing prerequisites' );
    # This is a two-step process: first we need to install the applications that haven't been
    # installed yet, and then we need to install their dependencies

    my $prerequisites = {};
    foreach my $site ( @newSites ) {
        $site->addInstallablesToPrerequisites( $prerequisites );
    }
    UBOS::Host::ensurePackages( $prerequisites );

    $prerequisites = {};
    foreach my $site ( @newSites ) {
        $site->addDependenciesToPrerequisites( $prerequisites );
    }
    UBOS::Host::ensurePackages( $prerequisites );

    debug( 'Checking customization points' );
    
    foreach my $newSite ( @newSites ) {
        foreach my $newAppConfig ( @{$newSite->appConfigs} ) {
            my $appConfigCustPoints = $newAppConfig->customizationPoints();
            
            foreach my $installable ( $newAppConfig->installables ) {
                my $packageName           = $installable->packageName;
                my $installableCustPoints = $installable->customizationPoints;
                if( $installableCustPoints ) {
                    foreach my $custPointName ( keys %$installableCustPoints ) {
                        my $custPointDef = $installableCustPoints->{$custPointName};

                        # check data type
                        my $value = $appConfigCustPoints->{$packageName}->{$custPointName}->{value};
                        if( defined( $value )) {
                            my $knownCustomizationPointTypes = $UBOS::Installable::knownCustomizationPointTypes;
                            my $custPointValidation = $knownCustomizationPointTypes->{ $custPointDef->{type}};
                            # checked earlier that this is non-null
                            unless( $custPointValidation->{valuecheck}->( $value )) {
                                fatal(   'Site ' . $newSite->siteId
                                       . ', AppConfiguration ' . $newAppConfig->appConfigId
                                       . ', package ' . $packageName
                                       . ', ' . $custPointValidation->{valuecheckerror} . ': ' . $custPointName
                                       . ', is ' . ( ref( $value ) || $value ));
                            }
                        }
                        
                        # now check that required values are indeed provided
                        unless( $custPointDef->{required} ) {
                            next;
                        }
                        if( !defined( $custPointDef->{default} ) || !defined( $custPointDef->{default}->{value} )) {
                            # make sure the Site JSON file provided one
                            unless( defined( $value )) {
                                fatal(   'Site ' . $newSite->siteId
                                       . ', AppConfiguration ' . $newAppConfig->appConfigId
                                       . ', package ' . $packageName
                                       . ', required value not provided for customizationpoint: ' .  $custPointName );
                            }
                        }
                    }
                }
            }
        }
    }

    # Now that we have prerequisites, we can check whether the site is deployable
    foreach my $newSite ( @newSites ) {
        $newSite->checkDeployable();
    }

    debug( 'Setting up placeholder sites or suspending existing sites' );

    my $suspendTriggers = {};
    foreach my $site ( @newSites ) {
        my $oldSite = $oldSites->{$site->siteId};
        if( $oldSite ) {
            $ret &= $oldSite->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
        } else {
            $ret &= $site->setupPlaceholder( $suspendTriggers ); # show "coming soon"
        }
    }
    UBOS::Host::executeTriggers( $suspendTriggers );

    debug( 'Backing up, undeploying and redeploying' );

    my $deployUndeployTriggers = {};
    foreach my $site ( @newSites ) {
        my $oldSite = $oldSites->{$site->siteId};
        if( $oldSite ) {
            my $backup = UBOS::UpdateBackup->new();
            $ret &= $backup->create( { $site->siteId => $oldSite } );
            $ret &= $oldSite->undeploy( $deployUndeployTriggers );
            
            $ret &= $site->deploy( $deployUndeployTriggers );
            $ret &= $backup->restoreSite( $site );

            $backup->delete();

        } else {
            $ret &= $site->deploy( $deployUndeployTriggers );
        }
    }
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    debug( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( @newSites ) {
        $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
    }
    UBOS::Host::executeTriggers( $resumeTriggers );

    debug( 'Running installers/upgraders' );

    foreach my $site ( @newSites ) {
        my $oldSite = $oldSites->{$site->siteId};
        if( $oldSite ) {
            foreach my $appConfig ( @{$site->appConfigs} ) {
                if( $oldSite->appConfig( $appConfig->appConfigId() )) {
                    $ret &= $appConfig->runUpgrader();
                } else {
                    $ret &= $appConfig->runInstaller();
                }
            }
        } else {
            foreach my $appConfig ( @{$site->appConfigs} ) {
                $ret &= $appConfig->runInstaller();
            }
        }
    }

    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--siteid <siteid>] ... --stdin
SSS
    Deploy or update one or more websites based on the Site JSON
    information read from stdin. If one or more <siteid>s are given, ignore
    all information contained in <site.json> other than sites with the
    specified <siteid>s. This includes setting up the virtual host(s),
    installing and configuring all web applications for the website(s).
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--siteid <siteid>] ... --file <site.json>
SSS
    Deploy or update one or more websites based on the information
    contained in <site.json>. If one or more <siteid>s are given, ignore
    all information contained in <site.json> other than sites with the
    specified <siteid>s. This includes setting up the virtual host(s),
    installing and configuring all web applications for the website(s).
HHH
    };
}

1;
