#!/usr/bin/perl
#
# Command that deploys one or more sites.
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
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $useAsTemplate = undef;
    my @files         = ();
    my $stdin         = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug,
            'template'    => \$useAsTemplate,
            'files=s'     => \@files,
            'stdin'       => \$stdin );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || ( @files && $stdin ) || ( !@files && !$stdin ) || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    trace( 'Parsing site JSON and checking' );

    my @jsons = ();
    if( @files ) {
        foreach my $file ( @files ) {
            my $json = readJsonFromFile( $file );
            unless( $json ) {
                fatal();
            }
            $json = UBOS::Utils::insertSlurpedFiles( $json, dirname( $file ) );
            if( ref( $json ) eq ARRAY ) {
                push @jsons, @$json;
            } else {
                push @jsons, $json;
            }
        }
    } else {
        my $json = readJsonFromStdin();
        unless( $json ) {
            fatal( 'No JSON input provided on stdin' );
        }
        $json = UBOS::Utils::insertSlurpedFiles( $json, getcwd() );
        if( ref( $json ) eq ARRAY ) {
            push @jsons, @$json;
        } else {
            push @jsons, $json;
        }
    }

    my $newSitesHash = {};

   foreach my $json ( @jsons ) {
       my $site   = UBOS::Site->new( $json, $useAsTemplate );
       my $siteId = $site->siteId;
       if( $newSitesHash->{$siteId} ) {
           fatal( "Duplicate site definition: $siteId" );
       }
       $newSitesHash->{$siteId} = $site;
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

        } elsif( !$newSite->isTor() ) {
            # site is new and not tor
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
        if( defined( $newSiteHostName )) {
            # not tor
            $haveHostAlready->{$newSiteHostName} = $newSite;
        }

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
        if( $site->isTor() ) {
            $prerequisites->{'tor'} = 'tor';
        }
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

    trace( 'Checking context paths and customization points', $ret );

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
            debugAndSuspend( 'Suspend site', $oldSite->siteId() );
            $ret &= $oldSite->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
        } else {
            debugAndSuspend( 'Setup placeholder for site', $site->siteId() );
            $ret &= $site->setupPlaceholder( $suspendTriggers ); # show "coming soon"
        }
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $suspendTriggers );

    my @letsEncryptCertsNeededSites = grep { $_->hasLetsEncryptTls() && !$_->hasLetsEncryptCerts() } @newSites;
    if( @letsEncryptCertsNeededSites ) {
        if( @letsEncryptCertsNeededSites > 1 ) {
            info( 'Obtaining letsencrypt certificates' );
        } else {
            info( 'Obtaining letsencrypt certificate' );
        }
        foreach my $site ( @letsEncryptCertsNeededSites ) {
            debugAndSuspend( 'Obtain letsencrypt certificate for site', $site->siteId() );
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
            debugAndSuspend( 'Creating UpdateBackup for site', $site->siteId() );
            $ret &= $backup->create( { $site->siteId => $oldSite } );

            debugAndSuspend( 'Undeploying site', $oldSite->siteId() );
            $ret &= $oldSite->undeploy( $deployUndeployTriggers );

            debugAndSuspend( 'Deploying site', $site->siteId() );
            $ret &= $site->deploy( $deployUndeployTriggers );
            debugAndSuspend( 'Restoring from UpdateBackup for site', $site->siteId() );
            $ret &= $backup->restoreSite( $site );

            $backup->delete();

        } else {
            debugAndSuspend( 'Deploying site', $site->siteId() );
            $ret &= $site->deploy( $deployUndeployTriggers );
        }
    }
    debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( @newSites ) {
        debugAndSuspend( 'Resuming site', $site->siteId() );
        $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
    }
    debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running installers/upgraders' );

    foreach my $site ( @newSites ) {
        my $oldSite = $oldSites->{$site->siteId};
        if( $oldSite ) {
            foreach my $appConfig ( @{$site->appConfigs} ) {
                if( $oldSite->appConfig( $appConfig->appConfigId() )) {
                    debugAndSuspend( 'Running upgrader for appconfig', $appConfig->appConfigId );
                    $ret &= $appConfig->runUpgraders();
                } else {
                    debugAndSuspend( 'Running installer for appconfig', $appConfig->appConfigId );
                    $ret &= $appConfig->runInstallers();
                }
            }
        } else {
            foreach my $appConfig ( @{$site->appConfigs} ) {
                debugAndSuspend( 'Running installer for appconfig', $appConfig->appConfigId );
                $ret &= $appConfig->runInstallers();
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
        'summary' => <<SSS,
    Deploy one or more websites.
SSS
        'detail' => <<DDD,
    This command will set up the virtual host(s), download, install and
    configure all web applications and their accessories for the
    website(s), potentially obtain and provisioning TLS or Tor keys,
    populate databases and the like, and restart daemons, depending on
    the site configuration(s) and the needs of the application(s).
    Each site's desired configuration is provided in one or more Site
    JSON files.
DDD
        'cmds' => {
            <<SSS => <<HHH,
    --stdin
SSS
    Read Site JSON information from the terminal. (Useful when deploying
    over the internet, using a command such as:
    cat site.json | ssh shepherd\@device sudo ubos-admin deploy --stdin)
HHH
        <<SSS => <<HHH,
    --file <site.json> [--file <site.json> ]...
SSS
    Read the Site JSON information from one or more Site JSON files.
HHH
        <<SSS => <<HHH
    --template --file <site.json> [--file <site.json> ]...
SSS
    Read the Site JSON information from one or more Site JSON files.
    However, ignore the site ids and appconfigids in the provided file(s)
    and assign new ones instead.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH
    Use an alternate log configuration file for this command.
HHH
        }
    };
}

1;
