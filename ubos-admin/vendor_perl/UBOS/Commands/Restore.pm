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
# This file is part of ubos-admin.
# (C) 2012-2016 Indie Computing Corp.
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
# return: desired exit code
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose         = 0;
    my $logConfigFile   = undef;
    my $showIds         = 0;
    my $noTls           = 0;
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
            'showids'          => \$showIds,
            'notls'            => \$noTls,
            'in=s'             => \$in,
            'url=s'            => \$url,
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

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    my $nSites   = scalar( @siteIds )   + scalar( @hostnames );
    my $nToSites = scalar( @toSiteIds ) + scalar( @toHostnames );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile )
        || ( !$in && !$url )
        || ( $in && $url )
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
           ))
        || ( @migrateFrom != @migrateTo )
        || ( @migrateFrom != _uniq( @migrateFrom )) )
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $file;
    my $tmpFile;
    if( $in ) {
        unless( -r $in ) {
            fatal( 'Cannot read file', $in );
        }
        $file = $in;
    } else {
        $tmpFile = File::Temp->new( UNLINK => 1 );
        close $tmpFile;
        $file = $tmpFile->filename();

        info( 'Downloading...' );

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
        $ret = restoreAppConfigs( \@appConfigIds, \@toSiteIds, \@toHostnames, $createNew, \@newAppConfigIds, \@newContexts, $showIds, \%migratePackages, $backup, $quiet );
    } else {
        $ret = restoreSites( \@siteIds, \@hostnames, $createNew, \@newSiteIds, \@newHostnames, $noTls, $showIds, \%migratePackages, $backup, $quiet );
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
        $ret &= $toSite->suspend( $suspendTriggers ); # replace with "in progress page"
    }
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Updating site(s)' );

    my $deployUndeployTriggers = {};
    my %newAppConfigs          = (); # new appconfig id => new app config
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

            $site->addDeployAppConfiguration( $newAppConfig, $deployUndeployTriggers );

            $newAppConfigs{$newAppConfigId} = $newAppConfig;
        }
    }
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Restoring data' );

    for( my $i=0 ; $i<@appConfigIdsToRestore ; ++$i ) {
        my $newAppConfigId = $appConfigIdsToRestore[$i];
        my $oldAppConfigId = $appConfigIdTranslation{$newAppConfigId};
        my $siteId         = $toSites[$i];

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
        $ret &= $toSite->resume( $resumeTriggers );
    }
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running upgraders' );

    foreach my $newAppConfigId ( @appConfigIdsToRestore ) {
        my $appConfig = $newAppConfigs{$newAppConfigId};

        $ret &= $appConfig->runUpgrader();
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
    my @siteIds      = @{shift()};
    my @hostnames    = @{shift()};
    my $createNew    = shift;
    my @newSiteIds   = @{shift()};
    my @newHostnames = @{shift()};
    my $noTls        = shift;
    my $showIds      = shift;
    my $migratePackages = shift;
    my $backup       = shift;
    my $quiet        = shift;

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

    debug( 'Backup siteids to restore:', @oldSiteIds );

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
            $appConfigIdTranslation{$newAppConfigId} = $appConfig->appConfigId;

            push @{$siteIdsToAppConfigIds{$newSiteId}}, $newAppConfigId;
        }
    }
    debug( 'Host siteids to restore to:', @siteIdsToRestore );

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

        my $newSite = UBOS::Site->new( $siteJsonNew );
        if( $noTls ) {
            $newSite->deleteTlsInfo();
        }
        push @sitesNew, $newSite;
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
        $ret &= $siteNew->setupPlaceholder( $suspendTriggers ); # show "coming soon"

        if( $siteNew->hasLetsEncryptTls() && !$siteNew->hasLetsEncryptCerts()) {
            info( 'Obtaining letsencrypt certificate for site', $siteNew->hostname, '(', $siteNew->siteId, ')' );

            my $success = $siteNew->obtainLetsEncryptCertificate();
            unless( $success ) {
                warning( 'Failed to obtain letsencrypt certificate for site', $siteNew->hostname, '(', $siteNew->siteId, '). Deploying site without TLS.' );
                $siteNew->unsetLetsEncryptTls;
            }
            $ret &= $success;
        }
    }
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Deploying new version of sites' );

    my $deployUndeployTriggers = {};
    foreach my $siteNew ( @sitesNew ) {
        $ret &= $siteNew->deploy( $deployUndeployTriggers );
    }
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Restoring data' );

    foreach my $newSiteId ( keys %siteIdsToAppConfigIds ) {
        foreach my $newAppConfigId ( @{$siteIdsToAppConfigIds{$newSiteId}} ) {
            my $oldAppConfigId = $appConfigIdTranslation{$newAppConfigId};
            my $oldAppConfig   = $appConfigsInBackup->{$oldAppConfigId};

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
        $ret &= $siteNew->resume( $resumeTriggers );
    }
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running upgraders' );

    foreach my $newAppConfigId ( sort keys %appConfigIdTranslation ) {
        my $newAppConfig = UBOS::Host::findAppConfigurationById( $newAppConfigId );
        $ret &= $newAppConfig->runUpgrader();
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
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--notls] [--migratefrom <package-a> --migrateto <package-b>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore all sites contained in backupfile. This includes all
    applications at that site and their data. None of the sites in the backup
    file must currently exist on the host: siteids, appconfigids, and
    hostnames must all be different.
    Instead of restoring app or accessory package-a, restore to package-b.
    Alternatively, a URL may be specified from where to retrieve the
    backupfile.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--notls] [--migratefrom <package-a> --migrateto <package-b>] ( --siteid <siteid> | --hostname <hostname> ) [--newhostname <hostname>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore the site with siteid or hostname contained in backupfile. This
    includes all applications at that site and their data. This site currently
    must not exist on the host: siteid, appconfigids, and hostname must
    all be different.
    Instead of restoring app or accessory package-a, restore to package-b.
    Alternatively, a URL may be specified from where to retrieve the
    backupfile.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--notls] [--migratefrom <package-a> --migrateto <package-b>] ( --siteid <siteid> | --hostname <hostname> ) --createnew [--newsiteid <newid>] [--newhostname <hostname>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore the site with siteid or hostname contained in backupfile, but
    instead of using the siteids and appconfigids given in the backup,
    allocate new ones. Optionally specify the new siteid to use with --newsiteid.
    Optionally recreate the site on the host with a new hostname with --newhostname.
    Instead of restoring app or accessory package-a, restore to package-b.
    Alternatively, a URL may be specified from where to retrieve the
    backupfile.

    This allows the user to run the restored backup of a site in parallel
    with the current site, as long as they use a different hostname.

    This exists mainly to facilitate testing.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--migratefrom <package-a> --migrateto <package-b>] --appconfigid <appconfigid> ( --tositeid <tositeid> | --tohostname <tohostname> ) [--newcontext <context>] ( --in <backupfile> | --url <backupurl> )
SSS
    Restore AppConfiguration appconfigid by adding it as a new AppConfiguration
    to a currently deployed Site with tositeid. No AppConfiguration with appconfigid
    must currently exist on the host. Optionally use a different context path
    for the AppConfiguration using --newcontext.
    Instead of restoring app or accessory package-a, restore to package-b.
    Alternatively, a URL may be specified from where to retrieve the
    backupfile.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--showids] [--migratefrom <package-a> --migrateto <package-b>] --appconfigid <appconfigid> ( --tositeid <tositeid> | --tohostname <tohostname> ) --createnew [--newappconfigid <newid>] [--newcontext <context>] --in <backupfile>
SSS
    Restore AppConfiguration appconfigid by adding it as a new AppConfiguration
    to a currently deployed Site with tositeid, but instead of using the
    appconfigid given in the backup, allocate a new one. Optional specify the
    new appconfigid to use with --newappconfigid. Optionally use a
    different context path for the AppConfiguration using --newcontext.
    Instead of restoring app or accessory package-a, restore to package-b.
    Alternatively, a URL may be specified from where to retrieve the
    backupfile.
HHH
    };
}

1;
