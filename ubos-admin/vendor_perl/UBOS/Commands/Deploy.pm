#!/usr/bin/perl
#
# Command that deploys one or more sites.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Deploy;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray :config pass_through ); # for parsing by BackupOperation, DataTransferProtocol
use UBOS::BackupOperation;
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Terminal;
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

    unless( UBOS::Lock::acquire() ) {
        colPrintError( "$@\n" );
        exit -2;
    }

    my $verbose           = 0;
    my $logConfigFile     = undef;
    my $debug             = undef;
    my $useAsTemplate     = undef;
    my @files             = ();
    my $stdin             = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug,
            'template'    => \$useAsTemplate,
            'file=s'      => \@files,
            'stdin'       => \$stdin );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( @files && $stdin )
        || ( !@files && !$stdin )
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $backupOperation = UBOS::BackupOperation::parseArgumentsPartial( \@args );
    unless( $backupOperation ) {
        if( $@ ) {
            fatal( $@ );
        } else {
            fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
        }
    }

    if( @args ) {
        # some are left over
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
            if( ref( $json ) eq 'ARRAY' ) {
                # Several site JSONs in an array
                push @jsons, @$json;
            } elsif( exists( $json->{hostname} ) || exists( $json->{tor} )) {
                # Single site JSON
                push @jsons, $json;
            } else {
                # Several site JSONs in a hash as produced by listsites --json
                push @jsons, values %$json;
            }
        }
    } else {
        my $json = readJsonFromStdin();
        unless( $json ) {
            fatal( 'No JSON input provided on stdin' );
        }
        $json = UBOS::Utils::insertSlurpedFiles( $json, getcwd() );
        if( ref( $json ) eq 'ARRAY' ) {
            # Several site JSONs in an array
            push @jsons, @$json;
        } elsif( exists( $json->{hostname} )) {
            # Single site JSON
            push @jsons, $json;
        } else {
            # Several site JSONs in a hash as produced by listsites --json
            push @jsons, values %$json;
        }
    }

    my $newSitesHash = {};

    foreach my $json ( @jsons ) {
        my $site = UBOS::Site->new( $json, $useAsTemplate );
        unless( $site ) {
            fatal( $@ );
        }

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
                if(( grep { !$_->isTor() } values %$oldSites ) > 1 ) {
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
    UBOS::Lock::preventInterruptions();
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

            unless( $newAppConfig->completeImpliedAccessories()) {
                fatal( $@ );
            }
            unless( $newAppConfig->checkCompleteCustomizationPointValues()) {
                fatal( $@ );
            }

            my $appPackage = $newAppConfig->app()->packageName();
            foreach my $acc ( $newAppConfig->accessories() ) {
                if( !$acc->canBeUsedWithApp( $appPackage ) ) {
                    fatal( 'Accessory', $acc->packageName(), 'cannot be used in appconfig', $newAppConfig->appConfigId(), 'as it does not belong to app', $appPackage );
                }
            }
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

    if( keys %$oldSites ) {
        info( 'Backing up, undeploying and redeploying' );
    } else {
        info( 'Deploying' );
    }

    $backupOperation->setSitesToBackUp( $newSitesHash );
    my $backupSucceeded  = $backupOperation->constructCheckPipeline();
    $backupSucceeded    &= $backupOperation->doBackup();

    if( $backupSucceeded ) {
        my $deployUndeployTriggers = {};
        foreach my $site ( @newSites ) {
            my $oldSite = $oldSites->{$site->siteId};
            if( $oldSite ) {
                my $updateBackup = UBOS::UpdateBackup->new();
                debugAndSuspend( 'Creating UpdateBackup for site', $site->siteId() );
                $ret &= $updateBackup->create( { $site->siteId => $oldSite } );

                debugAndSuspend( 'Undeploying site', $oldSite->siteId() );
                $ret &= $oldSite->undeploy( $deployUndeployTriggers );

                debugAndSuspend( 'Deploying site', $site->siteId() );
                $ret &= $site->deploy( $deployUndeployTriggers );

                debugAndSuspend( 'Restoring from UpdateBackup for site', $site->siteId() );
                $ret &= $updateBackup->restoreSite( $site );
                $ret &= $site->runInstallersOrUpgraders( $oldSite, 0 );

                if( $ret ) {
                    trace( 'Deleting update backup for site', $site->siteId );
                    debugAndSuspend( 'Delete update backup' );
                    $updateBackup->delete();
                } else {
                    warning( 'Something went wrong during restore of update backup. Not deleting update backup for site', $site->siteId );
                }

            } else {
                debugAndSuspend( 'Deploying site', $site->siteId() );
                $ret &= $site->deploy( $deployUndeployTriggers );
                $ret &= $site->runInstallersOrUpgraders( undef, 0 );
            }
        }
        UBOS::Networking::NetConfigUtils::updateOpenPorts();

        debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
        UBOS::Host::executeTriggers( $deployUndeployTriggers );
    }

    info( 'Resuming sites' );

    my $resumeTriggers = {};

    if( $backupSucceeded ) {
        foreach my $site ( @newSites ) {
            debugAndSuspend( 'Resuming site', $site->siteId() );
            $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
        }

    } else {
        foreach my $site ( values %$oldSites ) {
            debugAndSuspend( 'Resuming site', $site->siteId() );
            $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
        }
        $ret = 0;
    }
    debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    if( $backupSucceeded ) {
        foreach my $site ( @newSites ) {
            my $oldSite = $oldSites->{$site->siteId};
            $ret &= $site->runInstallersOrUpgraders( $oldSite, 1 );
        }
    }

    unless( $backupOperation->doUpload()) {
        error( $@ );
    }

    unless( $backupOperation->finish()) {
        error( $@ );
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
            '--backuptofile <backupfileurl>' => <<HHH,
    Before updating the site(s), back up all data from all affected sites
    by saving all data from all apps and accessories at those sites into
    the named file <backupfileurl>, which can be a local file name or a URL.
HHH
            '--backuptodirectory <backupdirurl>' => <<HHH,
SSS
    Before updating the site(s), back up all data from all affected sites
    by saving all data from all apps and accessories at those sites into
    a file with an auto-generated name, which will be located in the
    directory <backupdirurl>, which can be a local directory name or a URL
    referring to a directory.
HHH
            '--notls' => <<HHH,
    If a backup is to be created, and a site uses TLS, do not put the TLS
    key and certificate into the backup.
HHH
            '--notorkey' => <<HHH,
    If a backup is to be created, and a site is on the Tor network, do
    not put the Tor key into the backup.
HHH
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
