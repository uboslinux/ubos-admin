#!/usr/bin/perl
#
# Deploy the found Site templates.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::DeploySiteTemplates;

use UBOS::Host;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::StaffManager;
use UBOS::Utils;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'DeploySiteTemplates::performAtLoad', $staffRootDir, $isActualStaffDevice );

    return deploySiteTemplates( $staffRootDir );
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'DeploySiteTemplates::performAtSave', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# Deploy Site templates found below this directory, unless disabled.
# If anything goes wrong, we don't do anything at all.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub deploySiteTemplates {
    my $staffRootDir = shift;

    unless( UBOS::Host::vars()->getResolve( 'host.deploysitetemplatesonboot', 1 )) {
        return 0;
    }

    trace( 'StaffManager::deploySiteTemplates', $staffRootDir );

    my $errors = 0;

    my $hostId = UBOS::Host::hostId();

    my @templateFiles = ();
    foreach my $templateDir (
            "$staffRootDir/site-templates",
            "$staffRootDir/flock/$hostId/site-templates" )
                    # The host-specific templates overwrite the general ones
    {
        if( -d $templateDir ) {
            if( opendir( DIR, $templateDir )) {
                while( my $entry = readdir DIR ) {
                    if( $entry !~ m!^\.! && $entry =~ m!\.json$! ) {
                        # ignore files that start with . (like ., .., and MacOS resource files)
                        push @templateFiles, "$templateDir/$entry";
                    }
                }
                closedir DIR;
            } else {
                error( 'Cannot read from directory:', $templateDir );
                ++$errors;
            }
        }
    }

    my @sitesFromTemplates = (); # Some may be already deployed, we skip those. Identify by hostname
    my $existingSites      = UBOS::Host::sites();
    my $existingHosts      = {};
    map { $existingHosts->{$_->hostname()} = 1 } values %$existingSites;

    foreach my $templateFile ( @templateFiles ) {

        trace( 'Reading template file:', $templateFile );
        my $json = readJsonFromFile( $templateFile );
        if( $json ) {
            my $newSite = UBOS::Site->new( $json, 1 );

            if( !$newSite ) {
                error( 'Failed to create site from:', $templateFile, ':', $@ );
                ++$errors;

            } elsif( !exists( $existingHosts->{$newSite->hostname()} )) {
                push @sitesFromTemplates, $newSite;

            } # else skip, we have it already
        } else {
            ++$errors;
        }
    }
    if( $errors ) {
        return $errors;
    }

    unless( @sitesFromTemplates ) {
        return 0; # nothing to do
    }

    my $oldSites = UBOS::Host::sites();

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

    my @newSites = (); # only those that had no error
    foreach my $newSite ( @sitesFromTemplates ) {
        my $newSiteId = $newSite->siteId;
        if( $haveIdAlready->{$newSiteId} ) {
            # skip
            next;
        }
        $haveIdAlready->{$newSiteId} = $newSite;

        my $newSiteHostName = $newSite->hostname;
        if( defined( $oldSites->{$newSiteId} )) {
            # do not redeploy
            next;

        } elsif( !$newSite->isTor() ) {
            # site is new and not tor
            if( $newSiteHostName eq '*' ) {
                if( keys %$oldSites > 0 ) {
                    error( "You can only create a site with hostname * (any) if no other sites exist." );
                    ++$errors;
                    return $errors;
                }

            } else {
                if( $haveAnyHostAlready ) {
                    error( "There is already a site with hostname * (any), so no other site can be created." );
                    ++$errors;
                    return $errors;
                }
                if( $haveHostAlready->{$newSiteHostName} ) {
                    error( 'There is already a different site with hostname', $newSiteHostName );
                    ++$errors;
                    return $errors;
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
                error( 'More than one site or appconfig with id', $newAppConfigId );
                ++$errors;
                return $errors;
            }
            $haveIdAlready->{$newSiteId} = $newSite;

            foreach my $oldSite ( values %$oldSites ) {
                foreach my $oldAppConfig ( @{$oldSite->appConfigs} ) {
                    if( $newAppConfigId eq $oldAppConfig->appConfigId ) {
                        if( $newSiteId ne $oldSite->siteId ) {
                            error(    'Non-unique appconfigid ' . $newAppConfigId
                                    . ' in sites ' . $newSiteId . ' and ' . $oldSite->siteId );
                            ++$errors;
                            return $errors;
                        }
                    }
                }
            }
        }
        push @newSites, $newSite;
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Lock::preventInterruptions();

    # No backup needed, we aren't redeploying

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
        error( $@ );
        ++$errors;
        return $errors;
    }

    $prerequisites = {};
    foreach my $site ( @newSites ) {
        $site->addDependenciesToPrerequisites( $prerequisites );
    }
    if( UBOS::Host::ensurePackages( $prerequisites ) < 0 ) {
        error( $@ );
        ++$errors;
        return $errors;
    }

    trace( 'Checking context paths and customization points', $errors );

    foreach my $newSite ( @newSites ) {
        my %contexts = ();
        foreach my $newAppConfig ( @{$newSite->appConfigs} ) {
            # check contexts
            my $context = $newAppConfig->context();
            if( defined( $context )) { # amazonses may not
                if( exists( $contexts{$context} )) {
                    error(   'Site ' . $newSite->siteId . ': more than one appconfig with context ' . $context );
                    ++$errors;
                    return $errors;
                }
            }
            if( keys %contexts ) {
                if( $context eq '' || defined( $contexts{''} ) ) {
                    error(   'Site ' . $newSite->siteId . ': cannot deploy app at root context if other apps are deployed at other contexts' );
                    ++$errors;
                    return $errors;
                }
            }
            unless( $newAppConfig->checkCompleteCustomizationPointValues()) {
                error( $@ );
                ++$errors;
                return $errors;
            }

            my $appPackage = $newAppConfig->app()->packageName();
            foreach my $acc ( $newAppConfig->accessories() ) {
                if( !$acc->canBeUsedWithApp( $appPackage ) ) {
                    error( 'Accessory', $acc->packageName(), 'cannot be used in appconfig', $newAppConfig->appConfigId(), 'as it does not belong to app', $appPackage );
                    ++$errors;
                    return $errors;
                }
            }

            $contexts{$context} = $newAppConfig;
        }
    }

    # Now that we have prerequisites, we can check whether the site is deployable
    foreach my $newSite ( @newSites ) {
        unless( $newSite->checkDeployable()) {
            error( 'New site is not deployable:', $newSite );
            ++$errors;
            return $errors;
        }
    }

    info( 'Setting up placeholder sites or suspending existing sites' );

    my $suspendTriggers = {};
    foreach my $site ( @newSites ) {
        my $oldSite = $oldSites->{$site->siteId};
        if( $oldSite ) {
            debugAndSuspend( 'Suspend site', $oldSite->siteId() );
            unless( $oldSite->suspend( $suspendTriggers )) { # replace with "upgrade in progress page"
                ++$errors;
            }
        } else {
            debugAndSuspend( 'Setup placeholder for site', $site->siteId() );
            unless( $site->setupPlaceholder( $suspendTriggers )) { # show "coming soon"
                ++$errors;
            }
        }
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Backing up, undeploying and redeploying' );

    my $deployUndeployTriggers = {};
    foreach my $site ( @newSites ) {
        debugAndSuspend( 'Deploying site', $site->siteId() );
        unless( $site->deploy( $deployUndeployTriggers )) {
            ++$errors;
        }
    }
    UBOS::Networking::NetConfigUtils::updateOpenPorts();

    debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Resuming sites' );

    my $resumeTriggers = {};
    foreach my $site ( @newSites ) {
        debugAndSuspend( 'Resuming site', $site->siteId() );
        unless( $site->resume( $resumeTriggers )) { # remove "upgrade in progress page"
            ++$errors;
        }
    }
    debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running installers/upgraders' );

    foreach my $site ( @newSites ) {
        foreach my $appConfig ( @{$site->appConfigs} ) {
            debugAndSuspend( 'Running installer for appconfig', $appConfig->appConfigId );
            unless( $appConfig->runInstallers()) {
                ++$errors;
            }
        }
    }

    return $errors;
}

1;
