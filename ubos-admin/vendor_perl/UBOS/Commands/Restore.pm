#!/usr/bin/perl
#
# Command that restores data from a backup.
#
# The help text suggests that only one named site or appconfig can be
# restored at one time. However, that's not true. More than once may be
# restored at the same time, as long as all required other flags (e.g.
# --context) are provided once for each. They are matched by being
# processed in sequence.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Restore;

use Cwd;
use File::Temp;
use Getopt::Long qw( GetOptionsFromArray );
use Storable qw( dclone );
use UBOS::AnyBackup;
use UBOS::Host;
use UBOS::Logging;
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

    my $verbose         = 0;
    my $logConfigFile   = undef;
    my $debug         = undef;
    my $showIds         = 0;
    my $noTls           = 0;
    my $noTor           = 0;
    my @noTorHostname   = ();
    my @ins             = ();
    my @urls            = ();
    my $in              = undef;
    my $url             = undef;
    my @siteIds         = ();
    my @hostnames       = ();
    my $createNew       = 0;
    my @newSiteIds      = ();
    my @newHostnames    = ();
    my @appConfigIds    = ();
    my @toSiteIds       = ();
    my @toHostnames     = ();
    my @newAppConfigIds = ();
    my @newContexts     = ();
    my @migrateFrom     = ();
    my @migrateTo       = ();
    my $quiet           = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'         => \$verbose,
            'logConfig=s'      => \$logConfigFile,
            'debug'            => \$debug,
            'showids'          => \$showIds,
            'notls'            => \$noTls,
            'notor'            => \$noTor,
            'notorhostname=s'  => \@noTorHostname,
            'in=s'             => \@ins,
            'url=s'            => \@urls,
            'siteid=s'         => \@siteIds,
            'hostname=s'       => \@hostnames,
            'createnew'        => \$createNew,
            'newsiteid=s'      => \@newSiteIds,
            'newhostname=s'    => \@newHostnames,
            'appconfigid=s'    => \@appConfigIds,
            'tositeid=s'       => \@toSiteIds,
            'tohostname=s'     => \@toHostnames,
            'newappconfigid=s' => \@newAppConfigIds,
            'newcontext=s'     => \@newContexts,
            'migratefrom=s'    => \@migrateFrom,
            'migrateto=s'      => \@migrateTo,
            'quiet'            => \$quiet );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    my $nSites   = scalar( @siteIds )   + scalar( @hostnames );
    my $nToSites = scalar( @toSiteIds ) + scalar( @toHostnames );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile )
        || ( @ins + @urls != 1 )
        || ( $noTor && @noTorHostname == 0 )
        || ( !@appConfigIds && !$createNew && (
                   ( @siteIds && @hostnames )
                || @newSiteIds
                || ( @newHostnames && @newHostnames != $nSites )
                || @toSiteIds
                || @toHostnames
                || @newAppConfigIds
                || @newContexts
           ))
        || ( !@appConfigIds && $createNew && (
                   ( @siteIds && @hostnames )
                || ( @newSiteIds   && @newSiteIds != $nSites )
                || ( @newHostnames && @newHostnames != $nSites )
                || @toSiteIds
                || @toHostnames
                || @newAppConfigIds
                || @newContexts
           ))
        || ( @appConfigIds && !$createNew && (
                   $nSites
                || ( @toSiteIds && @toHostnames )
                || @newSiteIds
                || @newHostnames
                || ( $nToSites != 1 && $nToSites != @appConfigIds )
                || @newAppConfigIds
                || ( @newContexts && ( @newContexts != @appConfigIds ))
                || $noTls
                || $noTor
           ))
        || ( @appConfigIds && $createNew && (
                   $nSites
                || ( @toSiteIds && @toHostnames )
                || @newSiteIds
                || @newHostnames
                || ( $nToSites != @appConfigIds )
                || ( $nToSites != 1 && $nSites != @appConfigIds )
                || ( @newAppConfigIds && @newAppConfigIds != @appConfigIds )
                || ( @newContexts && ( @newContexts != @appConfigIds ))
                || $noTls
                || $noTor
           ))
        || ( @migrateFrom != @migrateTo )
        || ( @migrateFrom != _uniq( @migrateFrom )) )
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }
    if( @ins ) {
        $in = $ins[0];
    } else {
        $url = $urls[0];
    }

    my $file;
    my $tmpFile;
    if( $in ) {
        unless( -r $in ) {
            fatal( 'Cannot read file', $in );
        }
        $file = $in;
    } else {
        my $tmpDir = UBOS::Host::vars()->get( 'host.tmp', '/tmp' );

        $tmpFile = File::Temp->new( DIR => $tmpDir, UNLINK => 1 );
        close $tmpFile;
        $file = $tmpFile->filename();

        info( 'Downloading backup...' );

        my $stdout;
        my $stderr;
        if( UBOS::Utils::myexec( "curl -L -v -o '$file' '$url'", undef, \$stdout, \$stderr )) {
            fatal( 'Failed to download', $url );
        }
        if( $stderr =~ m!HTTP/1\.[01] (\d+)! ) {
            my $status = $1;
            unless( $status eq '200' ) {
                fatal( 'Failed to access', $url, 'with status', $status );
            }
        } # else it might have been a protocol other than http
    }

    my $backup = UBOS::AnyBackup->readArchive( $file );
    unless( $backup ) {
        fatal( UBOS::AnyBackup::cannotParseArchiveErrorMessage( $in || $url ));
    }

    my %migratePackages = ();
    for( my $i=0 ; $i<@migrateFrom ; ++$i ) {
        $migratePackages{$migrateFrom[$i]} = $migrateTo[$i];
    }

    my $ret;
    if( @appConfigIds ) {
        $ret = restoreAppConfigs(
                \@appConfigIds,
                \@toSiteIds,
                \@toHostnames,
                $createNew,
                \@newAppConfigIds,
                \@newContexts,
                $showIds,
                \%migratePackages,
                $backup,
                $quiet );
    } else {
        $ret = restoreSites(
                \@siteIds,
                \@hostnames,
                $createNew,
                \@newSiteIds,
                \@newHostnames,
                $noTls,
                $noTor,
                \@noTorHostname,
                $showIds,
                \%migratePackages,
                $backup,
                $quiet );
    }

    return $ret;
}

##
# Call if we restore appconfigurations, not sites
sub restoreAppConfigs {
    my @appConfigIds    = @{shift()};
    my @toSiteIds       = @{shift()};
    my @toHostnames     = @{shift()};
    my $createNew       = shift;
    my @newAppConfigIds = @{shift()};
    my @newContexts     = @{shift()};
    my $showIds         = shift;
    my $migratePackages = shift;
    my $backup          = shift;
    my $quiet           = shift;

    my $appConfigsInBackup = $backup->appConfigs();
    my $sites              = UBOS::Host::sites();

    # 1. Establish appConfigId translation table
    # 2. Establish context translation table
    # 3. Check there will be no overlap in appConfigIds or contexts
    # 4. Establish list of new AppConfigIds to restore
    my %appConfigIdTranslation = (); # new appConfigId -> old appConfigId, contains existing sites
    my %contextToAppConfigId   = (); # siteid -> context -> new appconfigid, contains existing sites
    my %appConfigIdToContext   = (); # new appconfigid -> new context
    my @appConfigIdsToRestore  = (); # new appconfigids only
    my %siteIdsToAppConfigIds  = (); # to-be-updated site id -> array of new appconfigid

    # tosites and tohostnames must exist on the host
    # also assemble toSites
    my @toSites = ();
    foreach my $toSiteId ( @toSiteIds ) {
        my $toSite = UBOS::Host::findSiteByPartialId( $toSiteId );
        unless( $toSite ) {
            fatal( $@ );
        }
        push @toSites, $toSite;
    }
    foreach my $toHostname ( @toHostnames ) {
        unless( UBOS::Host::isValidHostname( $toHostname )) {
            fatal( 'Not a valid hostname:', $toHostname );
        }
        my $toSite = UBOS::Host::findSiteByHostname( $toHostname );
        unless( $toSite ) {
            fatal( $@ );
        }
        push @toSites, $toSite;
    }

    # fill the translation tables with currently deployed sites
    foreach my $site ( values %$sites ) {
        foreach my $appConfig ( @{$site->appConfigs} ) {
            $appConfigIdTranslation{$appConfig->appConfigId} = $appConfig->appConfigId;
            $contextToAppConfigId{$site->siteId}->{$appConfig->context} = $appConfig->appConfigId;
            $appConfigIdToContext{$appConfig->appConfigId} = $appConfig->context;
        }
    }

    my %requiredPackages = ();
    for( my $i=0 ; $i<@appConfigIds ; ++$i ) {
        my $oldAppConfigId = $appConfigIds[$i];
        my $appConfig = $backup->findAppConfigurationByPartialId( $oldAppConfigId );
        unless( $appConfig ) {
            fatal( $@ );
        }

        my $toSite = $toSites[$i];

        my $newAppConfigId;
        my $newContext;
        if( @newAppConfigIds ) {
            $newAppConfigId = $newAppConfigIds[$i];
        } elsif( $createNew ) {
            $newAppConfigId = UBOS::Host::createNewAppConfigId();
        } else {
            $newAppConfigId = $appConfig->appConfigId;
        }
        if( @newContexts ) {
            $newContext = $newContexts[$i];
        } else {
            $newContext = $appConfig->context;
        }
        if( exists( $appConfigIdTranslation{$newAppConfigId} )) {
            fatal( 'AppConfiguration with this appconfigid already exists:', $newAppConfigId );
        }
        if( exists( $contextToAppConfigId{$toSite->siteId}->{$newContext} )) {
            fatal( 'AppConfiguration with this context already exists on site:', $toSite->siteId, $newContext ? $newContext : '<root>' );
        }

        $contextToAppConfigId{$toSite->siteId}->{$newContext} = $newAppConfigId;
        $appConfigIdToContext{$newAppConfigId} = $newContext;
        push @appConfigIdsToRestore, $newAppConfigId;
        push @{$siteIdsToAppConfigIds{$toSite->siteId}}, $newAppConfigId;
    }

    info( 'Installing prerequisites' );
    # This is a two-step process: first we need to install the applications that haven't been
    # installed yet, and then we need to install their dependencies

    my $prerequisites = {};
    foreach my $toSite ( @toSites ) {
        $toSite->addInstallablesToPrerequisites( $prerequisites );
    }
    if( UBOS::Host::ensurePackages( _migratePackages( $prerequisites, $migratePackages ), $quiet ) < 0 ) {
        fatal( $@ );
    }

    $prerequisites = {};
    foreach my $toSite ( @toSites ) {
        $toSite->addDependenciesToPrerequisites( $prerequisites );
    }
    if( UBOS::Host::ensurePackages( _migratePackages( $prerequisites, $migratePackages ), $quiet ) < 0 ) {
        fatal( $@ );
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();
    my $ret = 1;

    info( 'Suspending site(s)' );

    my $suspendTriggers = {};
    foreach my $toSite ( @toSites ) {
        debugAndSuspend( 'Suspending site', $toSite->siteId );
        $ret &= $toSite->suspend( $suspendTriggers ); # replace with "in progress page"
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Updating site(s)' );

    my $deployUndeployTriggers = {};
    my %newAppConfigs          = (); # new appconfig id => new appconfig
    foreach my $siteId ( keys %siteIdsToAppConfigIds ) {
        my $site = $sites->{$siteId};

        foreach my $newAppConfigId ( @{$siteIdsToAppConfigIds{$siteId}} ) {
            my $oldAppConfigId = $appConfigIdTranslation{$newAppConfigId};
            my $oldAppConfig   = $backup->findAppConfigurationById( $oldAppConfigId );

            my $appConfigJsonNew = dclone( $oldAppConfig->appConfigurationJson() );
            $appConfigJsonNew->{appconfigid}  = $newAppConfigId;
            $appConfigJsonNew->{context}      = $appConfigIdToContext{$newAppConfigId};
            $appConfigJsonNew->{appid}        = _migratePackages( $appConfigJsonNew->{appid}, $migratePackages );
            $appConfigJsonNew->{accessoryids} = _migratePackages( $appConfigJsonNew->{accessoryids}, $migratePackages );
            unless( $appConfigJsonNew->{accessoryids} ) {
                delete $appConfigJsonNew->{accessoryids};
            }
            my $newAppConfig = UBOS::AppConfiguration->new( $appConfigJsonNew, $site );

            debugAndSuspend( 'Adding and deploying appconfig', $newAppConfig->appConfigId );
            $site->addDeployAppConfiguration( $newAppConfig, $deployUndeployTriggers );

            $newAppConfigs{$newAppConfigId} = $newAppConfig;
        }
    }
    debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Restoring data' );

    for( my $i=0 ; $i<@appConfigIdsToRestore ; ++$i ) {
        my $newAppConfigId = $appConfigIdsToRestore[$i];
        my $oldAppConfigId = $appConfigIdTranslation{$newAppConfigId};
        my $siteId         = $toSites[$i];

        debugAndSuspend( 'Restoring appconfig', $oldAppConfigId, 'to', $newAppConfigId, 'at site', $siteId );
        $ret &= $backup->restoreAppConfiguration(
                $siteId,
                $siteId,
                $backup->findAppConfigurationById( $oldAppConfigId ),
                $newAppConfigs{$newAppConfigId},
                $migratePackages );
    }

    info( 'Resuming site(s)' );

    my $resumeTriggers = {};
    foreach my $toSite ( @toSites ) {
        debugAndSuspend( 'Resuming site', $toSite->siteId );
        $ret &= $toSite->resume( $resumeTriggers );
    }

    UBOS::Networking::NetConfigUtils::updateOpenPorts();

    debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running upgraders' );

    foreach my $newAppConfigId ( @appConfigIdsToRestore ) {
        my $appConfig = $newAppConfigs{$newAppConfigId};

        debugAndSuspend( 'Running upgraders at appconfig', $appConfig->appConfigId );
        $ret &= $appConfig->runUpgraders();
    }

    if( $showIds ) {
        foreach my $newAppConfigId ( @appConfigIdsToRestore ) {
            print $newAppConfigId . "\n";
        }
    }

    return $ret;
}

##
# Called if we restore entire sites
sub restoreSites {
    my @siteIds         = @{shift()};
    my @hostnames       = @{shift()};
    my $createNew       = shift;
    my @newSiteIds      = @{shift()};
    my @newHostnames    = @{shift()};
    my $noTls           = shift;
    my $noTor           = shift;
    my @noTorHostname   = @{shift()};
    my $showIds         = shift;
    my $migratePackages = shift;
    my $backup          = shift;
    my $quiet           = shift;

    my $sitesInBackup      = $backup->sites();
    my $appConfigsInBackup = $backup->appConfigs();
    my $sites              = UBOS::Host::sites();

    # 1. Establish siteId translation table
    # 2. Establish appConfigId translation table
    # 3. Establish hostname translation table
    # 4. Check there will be no overlap in siteIds or hostnames
    # 5. Establish list of new SiteIds to restore
    my %siteIdTranslation      = (); # Calculated from (partial) @siteIds and @hostnames, new siteId -> old siteId, contains existing sites
    my %appConfigIdTranslation = (); # new appConfigId -> old appConfigId, contains existing sites
    my %hostnameToSiteId       = (); # hostname -> new siteId, contains existing sites
    my %siteIdToHostname       = (); # new siteId -> new hostname
    my @siteIdsToRestore       = (); # new siteIds only
    my %siteIdsToAppConfigIds  = (); # to-be-updated site id -> array of new appconfigid

    # fill the translation tables with currently deployed sites
    foreach my $site ( values %$sites ) {
        $siteIdTranslation{$site->siteId}  = $site->siteId;
        $hostnameToSiteId{$site->hostname} = $site->siteId;

        foreach my $appConfig ( @{$site->appConfigs} ) {
            $appConfigIdTranslation{$appConfig->appConfigId} = $appConfig->appConfigId;
        }
    }

    my @oldSiteIds = _findSitesInBackupFromSiteIds(    $backup, \@siteIds );
    push @oldSiteIds, _findSitesInBackupFromHostnames( $backup, \@hostnames );

    unless( @oldSiteIds ) {
        # no --siteid or --hostname was specified: take all
        @oldSiteIds = keys %$sitesInBackup;
    }

    trace( 'Backup siteids to restore:', @oldSiteIds );

    for( my $i=0 ; $i<@oldSiteIds ; ++$i ) {
        my $oldSiteId = $oldSiteIds[$i];
        my $site = $backup->findSiteById( $oldSiteId );

        my $newSiteId;
        my $newHostname;
        if( @newSiteIds ) {
            $newSiteId = $newSiteIds[$i];
        } elsif( $createNew ) {
            $newSiteId = UBOS::Host::createNewSiteId();
        } else {
            $newSiteId = $site->siteId;
        }
        if( @newHostnames ) {
            $newHostname = $newHostnames[$i];
        } else {
            $newHostname = $site->hostname;
        }
        if( exists( $siteIdTranslation{$newSiteId} )) {
            fatal( 'Site with this siteid exists already:', $newSiteId );
        }
        if( exists( $hostnameToSiteId{$newHostname} )) {
            fatal( 'Site with this hostname exists already:', $newHostname );
        }

        $siteIdTranslation{$newSiteId}  = $site->siteId;
        $hostnameToSiteId{$newHostname} = $newSiteId;
        $siteIdToHostname{$newSiteId}   = $newHostname;

        push @siteIdsToRestore, $newSiteId;

        foreach my $appConfig ( @{$site->appConfigs} ) {
            my $newAppConfigId;
            if( $createNew ) {
                $newAppConfigId = UBOS::Host::createNewAppConfigId();
            } else {
                $newAppConfigId = $appConfig->appConfigId;
            }
            if( exists( $appConfigIdTranslation{$newAppConfigId} )) {
                fatal( 'AppConfig with this appConfigId exists already:', $newAppConfigId );
            }
            if( exists( $appConfigIdTranslation{$appConfig->appConfigId} )) {
                delete $appConfigIdTranslation{$appConfig->appConfigId};
            }
            $appConfigIdTranslation{$newAppConfigId} = $appConfig->appConfigId;

            push @{$siteIdsToAppConfigIds{$newSiteId}}, $newAppConfigId;
        }
    }
    trace( 'Host siteids to restore to:', @siteIdsToRestore );

    info( 'Constructing new version of sites' );

    my @sitesNew = ();
    foreach my $newSiteId ( @siteIdsToRestore ) {
        my $oldSiteId = $siteIdTranslation{$newSiteId};
        my $oldSite   = $backup->findSiteById( $oldSiteId );

        my $siteJsonNew = dclone( $oldSite->siteJson() );
        $siteJsonNew->{siteid}     = $newSiteId;
        $siteJsonNew->{hostname}   = $siteIdToHostname{$newSiteId};
        $siteJsonNew->{appconfigs} = []; # rebuild

        foreach my $newAppConfigId ( keys %appConfigIdTranslation ) {
            my $oldAppConfigId = $appConfigIdTranslation{$newAppConfigId};
            my $oldAppConfig   = $oldSite->appConfig( $oldAppConfigId ); # may be undef; wrong site

            if( $oldAppConfig ) {
                my $appConfigJsonNew = dclone( $oldAppConfig->appConfigurationJson() );
                $appConfigJsonNew->{appconfigid}  = $newAppConfigId;
                $appConfigJsonNew->{appid}        = _migratePackages( $appConfigJsonNew->{appid}, $migratePackages );
                $appConfigJsonNew->{accessoryids} = _migratePackages( $appConfigJsonNew->{accessoryids}, $migratePackages );
                unless( $appConfigJsonNew->{accessoryids} ) {
                    delete $appConfigJsonNew->{accessoryids};
                }

                push @{$siteJsonNew->{appconfigs}}, $appConfigJsonNew;
            }
        }
        if( $noTor && exists( $siteJsonNew->{tor} )) {
            unless( @noTorHostname ) {
                fatal( 'More tor sites to restore with --notor than --notorhostname arguments given' );
            }
            my $newHostname = shift @noTorHostname;
            $siteJsonNew->{hostname} = $newHostname;

            delete $siteJsonNew->{tor};
        }

        my $newSite = UBOS::Site->new( $siteJsonNew );
        if( $newSite ) {
            if( $noTls ) {
                $newSite->deleteTlsInfo();
            }
            push @sitesNew, $newSite;
        } else {
            fatal( $@ );
        }
    }
    if( @noTorHostname ) {
        fatal( 'Too many --notorhostname arguments given for the sites to be restored' );
    }

    info( 'Installing prerequisites' );
    # This is a two-step process: first we need to install the applications that haven't been
    # installed yet, and then we need to install their dependencies

    my $prerequisites = {};
    foreach my $newSite ( @sitesNew ) {
        $newSite->addInstallablesToPrerequisites( $prerequisites );
    }
    if( UBOS::Host::ensurePackages( _migratePackages( $prerequisites, $migratePackages ), $quiet ) < 0 ) {
        fatal( $@ );
    }

    $prerequisites = {};
    foreach my $newSite ( @sitesNew ) {
        $newSite->addDependenciesToPrerequisites( $prerequisites );
    }
    if( UBOS::Host::ensurePackages( _migratePackages( $prerequisites, $migratePackages ), $quiet ) < 0 ) {
        fatal( $@ );
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();
    my $ret = 1;

    info( 'Setting up placeholders for restored sites' );

    my $suspendTriggers = {};
    foreach my $siteNew ( @sitesNew ) {
        debugAndSuspend( 'Setting up placeholder for site', $siteNew->siteId );
        $ret &= $siteNew->setupPlaceholder( $suspendTriggers ); # show "coming soon"

        if( $siteNew->hasLetsEncryptTls() && !$siteNew->hasLetsEncryptCerts()) {
            info( 'Obtaining letsencrypt certificate for site', $siteNew->hostname, '(', $siteNew->siteId, ')' );

            debugAndSuspend( 'Obtaining letsencrypt certificate for site', $siteNew->siteId );
            my $success = $siteNew->obtainLetsEncryptCertificate();
            unless( $success ) {
                warning( 'Failed to obtain letsencrypt certificate for site', $siteNew->hostname, '(', $siteNew->siteId, '). Deploying site without TLS.' );
                $siteNew->unsetLetsEncryptTls;
            }
            $ret &= $success;
        }
    }
    debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Deploying new version of sites' );

    my $deployUndeployTriggers = {};
    foreach my $siteNew ( @sitesNew ) {
        debugAndSuspend( 'Deploy site', $siteNew->siteId );
        $ret &= $siteNew->deploy( $deployUndeployTriggers );
    }
    debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Restoring data' );

    foreach my $newSiteId ( keys %siteIdsToAppConfigIds ) {
        foreach my $newAppConfigId ( @{$siteIdsToAppConfigIds{$newSiteId}} ) {
            my $oldAppConfigId = $appConfigIdTranslation{$newAppConfigId};
            my $oldAppConfig   = $appConfigsInBackup->{$oldAppConfigId};

            debugAndSuspend( 'Restore appconfig', $oldAppConfigId, 'to', $newAppConfigId, 'for site', $newSiteId );
            $ret &= $backup->restoreAppConfiguration(
                    $siteIdTranslation{$newSiteId},
                    $newSiteId,
                    $oldAppConfig,
                    UBOS::Host::findAppConfigurationById( $newAppConfigId ),
                    $migratePackages );
        }
    }

    info( 'Resuming site' );

    my $resumeTriggers = {};
    foreach my $siteNew ( @sitesNew ) {
        debugAndSuspend( 'Resume site', $siteNew->siteId );
        $ret &= $siteNew->resume( $resumeTriggers );
    }

    UBOS::Networking::NetConfigUtils::updateOpenPorts();

    debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running upgraders' );

    foreach my $newSiteId ( keys %siteIdsToAppConfigIds ) {
        foreach my $newAppConfigId ( @{$siteIdsToAppConfigIds{$newSiteId}} ) {
            my $newAppConfig = UBOS::Host::findAppConfigurationById( $newAppConfigId );
            debugAndSuspend( 'Run upgraders for appconfig', $newAppConfig->appConfigId );
            $ret &= $newAppConfig->runUpgraders();
        }
    }

    if( $showIds ) {
        foreach my $siteNew ( @sitesNew ) {
            print $siteNew->siteId . "\n";
            foreach my $appConfigNew ( @{$siteNew->appConfigs} ) {
                print '    ' . $appConfigNew->appConfigId . "\n";
            }
        }
    }
    return $ret;
}

##
# Given partial siteIds, find the corresponding sites in the backup
# $backup: the backup
# $siteIds: array of partial siteIds
# return: siteIds found
sub _findSitesInBackupFromSiteIds {
    my $backup  = shift;
    my $siteIds = shift;

    my @ret = ();
    foreach my $siteId ( @$siteIds ) {
        my $site = $backup->findSiteByPartialId( $siteId );
        unless( $site ) {
            fatal( $@ );
        }

        push @ret, $site->siteId;
    }
    return @ret;
}

##
# Given hostnames, find the corresponding sites in the backup
# $backup: the backup
# $hostnames: array of hostnames
# return: siteIds found
sub _findSitesInBackupFromHostnames {
    my $backup    = shift;
    my $hostnames = shift;

    my @ret = ();
    foreach my $hostname ( @$hostnames ) {
        unless( UBOS::Host::isValidHostname( $hostname )) {
            fatal( 'Not a valid hostname:', $hostname );
        }
        my $site = $backup->findSiteByHostname( $hostname );
        unless( $site ) {
            fatal( 'No site with this hostname in backup:', $hostname );
        }
        push @ret, $site->siteId;
    }
    return @ret;
}

##
# Translate a hash or array of package names into migrated packages names.
# $oldPackages: hash or array of package names to be translated
# $translation: hash of old package name to new package name; if no entry, keep old name
# return: list of new package names
sub _migratePackages {
    my $oldPackages = shift;
    my $translation = shift;

    if( !defined( $oldPackages )) {
        return undef;
    }
    if( ref( $oldPackages ) eq '' ) {
        return exists( $translation->{$oldPackages} ) ? $translation->{$oldPackages} : $oldPackages;
    }
    if( ref( $oldPackages ) eq 'HASH' ) {
        $oldPackages = [ sort keys %$oldPackages ];
    }

    my @ret = map { my $p = $_; exists( $translation->{$p} ) ? $translation->{$p} : $p; } @$oldPackages;
    return \@ret;
}

##
# Return a subset of the provided list that only contains unique members.
# @list: the list
# return: list or subset of list
sub _uniq {
    my @list = @_;

    my %have = ();
    my @ret  = ();
    map {
        my $l = $_;
        unless( exists( $have{$l} )) {
            push @ret, $l;
        }
        $have{$l} = $l;
    } @list;
    return @ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Restore sites or AppConfigurations from a backup file.
SSS
        'detail' => <<DDD,
    Various options are provided to only selectively restore some sites
    or AppConfigurations contained in the backup file, or to restore
    data into a somewhat different configuration (e.g. different host
    name). None of the sites or AppConfigurations to be restored must
    currently be deployed on this device. The backup file can generally
    be provided as a local file (with --in <backupfile>) or as a URL
    from where it will be downloaded (with --url <backupurl>). This
    operation does not modify the backup file.
DDD
        'cmds' => {
        <<SSS => <<HHH,
    --in <backupfile>
SSS
    Restore all sites contained in local UBOS backup file <backupfile>.
    This includes all applications at that site and their data.
HHH
        <<SSS => <<HHH,
    --url <backupurl>
SSS
    Download a UBOS backup file from URL <backupurl>, and restore all
    sites contained in that backup file. This includes all applications
    at that site and their data.
HHH
        <<SSS => <<HHH,
    --siteid <siteid> [--newhostname <newhostname>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore only one site identified by its site id <siteid> from local
    UBOS backup file <backupfile>, or from the UBOS backup file
    downloaded from URL <backupurl>. Optionally, if --newhostname
    <newhostname> is provided, assign a different hostname when
    deploying.
HHH
        <<SSS => <<HHH,
    --hostname <hostname> [--newhostname <newhostname>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore only one site identified by its hostname <hostname> from
    local UBOS backup file <backupfile>, or from the UBOS backup file
    downloaded from URL <backupurl>. Optionally, if --newhostname
    <newhostname> is provided, assign a different hostname when
    deploying.
HHH
        <<SSS => <<HHH,
    --siteid <siteid> --createnew [--newsiteid <newid>] [--newhostname <hostname>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore only one site identified by its site id <siteid> from local
    UBOS backup file <backupfile>, or from the UBOS backup file
    downloaded from URL <backupurl>. However, use a new site id <newid>
    for it (or, if not provided, generate a new one). Optionally, if
    --newhostname <newhostname> is provided, assign a different hostname
    when deploying.
HHH
        <<SSS => <<HHH,
    --hostname <hostname> --createnew [--newsiteid <newid>] [--newhostname <hostname>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore only one site identified by its hostname <hostname> from
    local UBOS backup file <backupfile>, or from the UBOS backup file
    downloaded from URL <backupurl>. However, use a new site id <newid>
    for it (or, if not provided, generate a new one). Optionally, if
    --newhostname <newhostname> is provided, assign a different hostname
    when deploying.
HHH
        <<SSS => <<HHH,
    --appconfigid <appconfigid> --tositeid <tositeid> [--newcontext <context>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore only one AppConfiguration identified by its appconfigid
    <appconfigid> from local UBOS backup file <backupfile>, or from the
    UBOS backup file downloaded from URL <backupurl>, by adding it as a
    new AppConfiguration to a currently deployed site identified by
    its site id <tositeid>. Optionally, if --newcontext <context> is
    provided, deploy the AppConfiguration to a different context path.
HHH
        <<SSS => <<HHH,
    --appconfigid <appconfigid> --tohostname <tohostname> [--newcontext <context>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore only one AppConfiguration identified by its appconfigid
    <appconfigid> from local UBOS backup file <backupfile>, or from the
    UBOS backup file downloaded from URL <backupurl>, by adding it as a
    new AppConfiguration to a currently deployed site identified by
    its hostname <tohostname>. Optionally, if --newcontext <context> is
    provided, deploy the AppConfiguration to a different context path.
HHH
        <<SSS => <<HHH,
    --appconfigid <appconfigid> --tositeid <tositeid> --createnew [--newappconfigid <newid>] [--newcontext <context>] --in <backupfile>
SSS
    Restore only one AppConfiguration identified by its appconfigid
    <appconfigid> from local UBOS backup file <backupfile>, or from the
    UBOS backup file downloaded from URL <backupurl>, by adding it as a
    new AppConfiguration to a currently deployed site identified by its
    site id <tositeid>. However, use new appconfigid <newid> for it (or,
    if not provided, generate a new one). Optionally, if --newcontext
    <context> is provided, deploy the AppConfiguration to a different
    context path.
HHH
        <<SSS => <<HHH
    --appconfigid <appconfigid> --tohostname <tohostname> --createnew [--newappconfigid <newid>] [--newcontext <context>] --in <backupfile>
SSS
    Restore only one AppConfiguration identified by its appconfigid
    <appconfigid> from local UBOS backup file <backupfile>, or from the
    UBOS backup file downloaded from URL <backupurl>, by adding it as a
    new AppConfiguration to a currently deployed site identified by
    its hostname <tohostname>. However, use new appconfigid <newid>
    for it (or, if not provided, generate a new one). Optionally, if
    --newcontext <context> is provided, deploy the AppConfiguration to a
    different context path.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--showids' => <<HHH,
    If specified, print the identifiers of the sites and
    AppConfigurations that were restored.
HHH
            '--notls' => <<HHH,
    If specified, ignore TLS information that may be contained in the
    backup and restore to a non-TLS site instead.
HHH
            '--notor' => <<HHH,
    If specified, restore Tor sites that may be contained in the backup
    to a non-Tor site instead. For each site being restored, a
    --notorhostname must be provided.
HHH
            '--notorhostname <hostname>' => <<HHH,
    If --notor is specified, this flag provides replacement hostnames
    for the Tor sites contained in the backup. This must be given as
    many times as sites are to be restored, in the same sequence as
    the to-be-restored sites to know which sites end up with which new
    hostname.
HHH
            '--migratefrom <package-a>' => <<HHH,
    Indicates that instead of restoring to the app <package-a> as
    indicated in the backup file, the restore shall be performed to app
    <package-b>, which is specified with the --migrateto argument.
HHH
            '--migrateto <package-b>' => <<HHH,
    For the app <package-a> which was specified with --migratefrom, the
    restore shall be performed to app <package-b>. These two arguments
    must come in pairs, are are matched to each other in sequence.
HHH
        }
    };
}

1;
