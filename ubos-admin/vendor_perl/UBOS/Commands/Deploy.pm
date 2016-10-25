#!/usr/bin/perl
#
# Command that deploys one or more sites.
#
# This file is part of ubos-admin.
# (C) 2012-2015 Indie Computing Corp.
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
    my $cmd  = shift;
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

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( $file && $stdin ) || ( !$file && !$stdin ) || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    debug( 'Parsing site JSON and checking' );

    my $json;
    if( $file ) {
        $json = readJsonFromFile( $file );
        unless( $json ) {
            exit 1;
        }
        $json = UBOS::Utils::insertSlurpedFiles( $json, dirname( $file ) );
    } else {
        $json = readJsonFromStdin();
        unless( $json ) {
            fatal( 'No JSON input provided on stdin' );
        }
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
                my $site   = UBOS::Site->new( $siteJson, 1 ); # allow templates without siteId and appConfigIds
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
    my $haveIdAlready      = {}; # it's okay that we have an old site by this id
    my $haveHostAlready    = {}; # it's not okay that we have an old site by this hostname if site id is different
    my $haveAnyHostAlready = 0; # true if we have the * (any) host
    
    foreach my $oldSite ( values %$oldSites ) {
        $haveHostAlready->{$oldSite->hostname} = $oldSite;
        if( '*' eq $oldSite->hostname ) {
            $haveAnyHostAlready = 1;
        }
    }
    
    foreach my $newSite ( @newSites ) {
        my $newSiteId = $newSite->siteId;
        if( $haveIdAlready->{$newSiteId} ) {
            fatal( 'More than one site or appconfig with id', $newSiteId );
        }
        $haveIdAlready->{$newSiteId} = $newSite;

        my $newSiteHostName = $newSite->hostname;
        if( defined( $oldSites->{$newSiteId} )) {
            my $existingSite = $oldSites->{$newSiteId};

            # site is being redeployed
            if( $newSiteHostName eq '*' ) {
                if( keys %$oldSites > 1 ) {
                    fatal( "You can only redeploy a site with hostname * (any) if no other sites exist." );
                }
                
            } else {
                if( $haveHostAlready->{$newSiteHostName} && $newSiteId ne $existingSite->siteId ) {
                    fatal( 'There is already a different site with hostname', $newSiteHostName );
                }
            }

        } else {
            # site is new
            if( $newSiteHostName eq '*' ) {
                if( keys %$oldSites > 0 ) {
                    fatal( "You can only create a site with hostname * (any) if no other sites exist." );
                }

            } else {
                if( $haveAnyHostAlready ) {
                    fatal( "There is already a site with hostname * (any), so no other site can be created." );
                }
                if( $haveHostAlready->{$newSiteHostName} ) {
                    fatal( 'There is already a different site with hostname', $newSiteHostName );
                }
            }            
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

    UBOS::UpdateBackup::checkReadyOrQuit();

    info( 'Installing prerequisites' );
    # This is a two-step process: first we need to install the applications that haven't been
    # installed yet, and then we need to install their dependencies

    my $prerequisites = {};
    foreach my $site ( @newSites ) {
        $site->addInstallablesToPrerequisites( $prerequisites );
    }
    if( UBOS::Host::ensurePackages( $prerequisites ) < 0 ) {
        fatal( $@ );
    }

    $prerequisites = {};
    foreach my $site ( @newSites ) {
        $site->addDependenciesToPrerequisites( $prerequisites );
    }
    if( UBOS::Host::ensurePackages( $prerequisites ) < 0 ) {
        fatal( $@ );
    }

    debug( 'Checking context paths and customization points', $ret );
    
    foreach my $newSite ( @newSites ) {
        my %contexts = ();
        foreach my $newAppConfig ( @{$newSite->appConfigs} ) {
            # check contexts
            my $context = $newAppConfig->context();
            if( defined( $context )) { # amazonses may not
                if( exists( $contexts{$context} )) {
                    fatal(   'Site ' . $newSite->siteId . ': more than one appconfig with context ' . $context );
                }
                if( keys %contexts ) {
                    if( $context eq '' || defined( $contexts{''} ) ) {
                        fatal(   'Site ' . $newSite->siteId . ': cannot deploy app at root context if other apps are deployed at other contexts' );
                    }
                }
                $contexts{$context} = $newAppConfig;
            }

            $newAppConfig->checkCustomizationPointValues();
        }
    }

    # Now that we have prerequisites, we can check whether the site is deployable
    foreach my $newSite ( @newSites ) {
        unless( $newSite->checkDeployable()) {
            fatal();
        }
    }

    info( 'Setting up placeholder sites or suspending existing sites' );

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

    my @letsEncryptCertsNeededSites = grep { $_->hasLetsEncryptTls() && !$_->hasLetsEncryptCerts() } @newSites;
    if( @letsEncryptCertsNeededSites ) {
        if( @letsEncryptCertsNeededSites > 1 ) {
            info( 'Obtaining letsencrypt certificates' );
        } else {
            info( 'Obtaining letsencrypt certificate' );
        }
        foreach my $site ( @letsEncryptCertsNeededSites ) {
            my $success = $site->obtainLetsEncryptCertificate();
            unless( $success ) {
                warning( 'Failed to obtain letsencrypt certificate for site', $site->hostname, '(', $site->siteId, '). Deploying site without TLS.' );
                $site->unsetLetsEncryptTls;
            }
            $ret &= $success;
        }
    }

    info( 'Backing up, undeploying and redeploying' );

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

    info( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( @newSites ) {
        $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
    }
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running installers/upgraders' );

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

    unless( $ret ) {
        error( "Deploy failed." );
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
