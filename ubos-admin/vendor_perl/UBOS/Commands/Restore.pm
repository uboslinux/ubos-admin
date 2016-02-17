#!/usr/bin/perl
#
# Command that restores data from a backup.
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
use Getopt::Long qw( GetOptionsFromArray );
use Storable qw( dclone );
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
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
    my $in            = undef;
    my @siteIds       = ();
    my @appConfigIds  = ();
    my $toSiteId      = undef;
    my $toHostname    = undef;
    my $hostname      = undef;
    my $context       = undef;
    my $createNew     = 0;
    my $newSiteId     = undef;
    my $showIds       = 0;
    my $noTls         = undef;
    my $quiet         = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'in=s'          => \$in,
            'siteid=s'      => \@siteIds,
            'appconfigid=s' => \@appConfigIds,
            'tositeid=s'    => \$toSiteId,
            'tohostname=s'  => \$toHostname,
            'hostname=s'    => \$hostname,
            'context=s'     => \$context,
            'createnew'     => \$createNew,
            'newsiteid=s'   => \$newSiteId,
            'showids'       => \$showIds,
            'notls'         => \$noTls,
            'quiet'         => \$quiet );

    UBOS::Logging::initialize( 'ubos-admin', 'restore', $verbose, $logConfigFile );

    if(    !$parseOk
        || @args
        || !$in
        || ( $verbose && $logConfigFile )
        || ( @siteIds && ( @appConfigIds || $toSiteId || $toHostname || $context ))
        || ( !@siteIds && !@appConfigIds && ( $toSiteId || $toHostname || $createNew || $newSiteId ))
        || ( $noTls && ( !@siteIds || $toHostname ))
        || ( $context && @appConfigIds > 1 )
        || ( $newSiteId && ( @siteIds > 1 || @appConfigIds ))
        || ( @appConfigIds && !$toSiteId && !$toHostname )
        || ( $hostname && ( @appConfigIds || @siteIds > 1 )))
    {
        fatal( 'Invalid invocation: restore', @_, '(add --help for help)' );
    }

    unless( -r $in ) {
        fatal( 'Cannot read file', $in );
    }
    my $backup = UBOS::Backup::ZipFileBackup->new();
    $backup->readArchive( $in );

    my $ret;
    if( @appConfigIds ) {
        $ret = restoreAppConfigs( \@appConfigIds, $toSiteId, $toHostname, $createNew, $context, $showIds, $backup, $quiet );
    } else {
        $ret = restoreSites( \@siteIds, $createNew, $newSiteId, $hostname, $showIds, $noTls, $backup, $quiet );
    }
    return $ret;
}

##
# Call if we restore appconfigurations, not sites        
sub restoreAppConfigs {
    my @appConfigIds = @{shift()};
    my $toSiteId     = shift;
    my $toHostname   = shift;
    my $createNew    = shift;
    my $context      = shift;
    my $showIds      = shift;
    my $backup       = shift;
    my $quiet        = shift;

    my $appConfigsInBackup = $backup->appConfigs();
    my %requiredPackages   = ();

    # tosite must exist on the host
    my $toSite;
    if( $toSiteId ) {
        $toSite = UBOS::Host::findSiteByPartialId( $toSiteId );
    } else {
        $toSite = UBOS::Host::findSiteByHostname( $toHostname );
    }
    unless( $toSite ) {
        fatal( $@ );
    }

    my %appConfigsToRestore = (); # appconfigid -> AppConfiguration in backup

    # appconfigids cannot overlap within the backup, or on the host
    foreach my $appConfigId ( @appConfigIds ) {
        my $appConfig = _findAppConfigurationByPartialId( $appConfigId, $appConfigsInBackup );
        unless( $appConfig ) {
            fatal( $@ );
        }
        if( !$createNew && UBOS::Host::findAppConfigurationById( $appConfig->appConfigId )) {
            fatal( 'There is already a currently deployed app configuration with appconfigid', $appConfig->appConfigId );
        }
        if( exists( $appConfigsToRestore{$appConfig->appConfigId} )) {
            fatal( 'Appconfigid specified more than once:', $appConfig->appConfigId );
        }
        $appConfigsToRestore{$appConfig->appConfigId} = $appConfig;

        # determine which packages we might need
        map { $requiredPackages{$_->packageName} = 1; } $appConfig->installables;
    }

    # $context cannot exist on same host
    if( defined( $context )) {
        unless( UBOS::AppConfiguration::isValidContext( $context )) {
            fatal( 'Context must be a slash followed by one or more characters, or be entirely empty' );
        }
        foreach my $appConfigOnHost ( @{$toSite->appConfigs} ) {
            if( $context eq $appConfigOnHost->context() ) {
                fatal( 'Already an AppConfiguration at context', $context ? $context : "<root>" );
            }
        }
    } else {
        foreach my $appConfigOnHost ( @{$toSite->appConfigs} ) {
            my $appConfigOnHostContext = $appConfigOnHost->context;
            foreach my $appConfigToRestore ( values %appConfigsToRestore ) {
                my $appConfigToRestoreContext = $appConfigToRestore->context();
                if( $appConfigOnHostContext eq $appConfigToRestoreContext ) {
                    fatal( 'Cannot restore AppConfiguration to context that is already taken:', $appConfigOnHostContext ? $appConfigOnHostContext : "<root>" );
                }
            }
        }
    }
    my @requiredPackageNames = keys %requiredPackages;
    UBOS::Host::ensurePackages( \@requiredPackageNames, $quiet );

    # May not be interrupted, bad things may happen if it is
	UBOS::Host::preventInterruptions();
    my $ret = 1;

    info( 'Suspending site' );

    my $suspendTriggers = {};
    $ret &= $toSite->suspend( $suspendTriggers ); # replace with "in progress page"
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Constructing new version of site' );

    my %appConfigIdTranslation = (); # maps old appconfigid -> new appconfigid
    my $siteJsonNew = dclone( $toSite->siteJson()); # create new Site JSON
    foreach my $appConfig ( values %appConfigsToRestore ) {
        my $appConfigJsonNew = dclone( $appConfig->appConfigurationJson() );
        if( $createNew ) {
            $appConfigJsonNew->{appconfigid} = UBOS::Host::createNewAppConfigId;
        }
        if( $context ) {
            $appConfigJsonNew->{context} = $context;
        }
        unless( $siteJsonNew->{appconfigs} ) { # site could be empty
            $siteJsonNew->{appconfigs} = [];
        }
        push @{$siteJsonNew->{appconfigs}}, $appConfigJsonNew;
        $appConfigIdTranslation{$appConfig->appConfigId} = $appConfigJsonNew->{appconfigid};
    }
    my $toSiteNew = UBOS::Site->new( $siteJsonNew );

    info( 'Deploying new version of site' );

    my $deployUndeployTriggers = {};
    $ret &= $toSite->undeploy( $deployUndeployTriggers );
    $ret &= $toSiteNew->deploy( $deployUndeployTriggers );
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Restoring data' );

    foreach my $appConfigIdInBackup ( keys %appConfigIdTranslation ) {
        my $appConfigIdOnHost = $appConfigIdTranslation{$appConfigIdInBackup};

        my $appConfigInBackup = $appConfigsToRestore{$appConfigIdInBackup};
        my $appConfigOnHost   = $toSiteNew->appConfig( $appConfigIdOnHost );
        $ret &= $backup->restoreAppConfiguration(
                $appConfigInBackup,
                $appConfigOnHost );
    }

    info( 'Resuming site' );

    my $resumeTriggers = {};
    $ret &= $toSiteNew->resume( $resumeTriggers );
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running upgraders' );

    foreach my $appConfigIdOnHost ( values %appConfigIdTranslation ) {
        my $appConfigOnHost = $toSiteNew->appConfig( $appConfigIdOnHost );
        $ret &= $appConfigOnHost->runUpgrader();
    }

    if( $showIds ) {
        foreach my $appConfigIdOnHost ( values %appConfigIdTranslation ) {
            print $appConfigIdOnHost->appConfigId . "\n";
        }
    }

    return $ret;    
}
    
##
# Called if we restore entire sites
sub restoreSites {
    my @siteIds   = @{shift()};
    my $createNew = shift;
    my $newSiteId = shift;
    my $hostname  = shift;
    my $showIds   = shift;
    my $noTls     = shift;
    my $backup    = shift;
    my $quiet     = shift;

    my $sitesInBackup      = $backup->sites();
    my $appConfigsInBackup = $backup->appConfigs();
    my $sites              = UBOS::Host::sites();

    if( $newSiteId ) {
        if( !UBOS::Host::isValidSiteId( $newSiteId )) {
            fatal( 'Note a valid siteid:', $newSiteId );
        }
        if( UBOS::Host::findSiteById( $newSiteId )) {
            fatal( 'There is already a currently deployed site with siteid', $newSiteId );
        }
    }
        
    if( !@siteIds ) {
        @siteIds = keys %$sitesInBackup;
    }

    my %sitesToRestore      = ();
    my %appConfigsToRestore = ();

    # siteids and appconfigids cannot overlap within the backup, or on the host
    foreach my $siteId ( @siteIds ) {
        my $site = UBOS::Host::findSiteByPartialId( $siteId, $sitesInBackup );
        unless( $site ) {
            fatal( $@ );
        }
        if( !$createNew && UBOS::Host::findSiteById( $site->siteId )) {
            fatal( 'There is already a currently deployed site with siteid', $site->siteId );
        }
        if( exists( $sitesToRestore{$site->siteId} )) {
            fatal( 'Siteid specified more than once:', $site->siteId );
        }
        $sitesToRestore{$site->siteId} = $site;

        if( !$createNew ) {
            # check internal consistency
            foreach my $appConfig ( @{$site->appConfigs} ) {
                if( !$createNew && UBOS::Host::findAppConfigurationById( $appConfig->appConfigId )) {
                    fatal( 'There is already a currently deployed app configuration with appconfigid', $appConfig->appConfigId );
                }
                
                if( exists( $appConfigsToRestore{$appConfig->appConfigId} )) {
                    fatal( 'Appconfigid found more than once:', $appConfig->appConfigId );
                }
                $appConfigsToRestore{$appConfig->appConfigId} = $appConfig;
            }
        }
    }

    # $hostname cannot exist on same host
    if( $hostname ) {
        foreach my $site ( values %$sites ) {
            if( $hostname eq $site->hostname ) {
                fatal( 'This host already runs a site at hostname', $hostname );
            }
        }
    } else {
        foreach my $siteOnHost ( values %$sites ) {
            my $hostnameOnHost = $siteOnHost->hostname;
            foreach my $siteToRestore ( values %sitesToRestore ) {
                my $hostnameToRestore = $siteToRestore->hostname();
                if( $hostnameOnHost eq $hostnameToRestore ) {
                    fatal( 'Cannot restore Site to hostname that is already taken:', $hostnameToRestore );
                }
            }
        }
    }

    # determine which packages we might need
    my %requiredPackages = ();
    foreach my $siteInBackup ( values %$sitesInBackup ) {
        foreach my $appConfigInBackup( @{$siteInBackup->appConfigs} ) {
            map { $requiredPackages{$_->packageName} = 1; } $appConfigInBackup->installables;
        }
    }

    my @requiredPackageNames = keys %requiredPackages;
    UBOS::Host::ensurePackages( \@requiredPackageNames, $quiet );

    # May not be interrupted, bad things may happen if it is
	UBOS::Host::preventInterruptions();
    my $ret = 1;

    info( 'Constructing new version of sites' );

    my %appConfigIdTranslation = (); # maps old appconfigid -> new appconfigid

    my %sitesNew = (); # maps old SiteId -> new Site
    foreach my $site ( values %sitesToRestore ) {
        my $siteJsonNew = dclone( $site->siteJson() );
        if( $createNew ) {
            $siteJsonNew->{siteid} = UBOS::Host::createNewSiteId;
        } elsif( $newSiteId ) {
            $siteJsonNew->{siteid} = $newSiteId;
        }
        if( $hostname ) {
            $siteJsonNew->{hostname} = $hostname;
        }
        if( $createNew ) {
            foreach my $appConfigJsonNew ( @{$siteJsonNew->{appconfigs}} ) {
                my $newAppConfigId = UBOS::Host::createNewAppConfigId;
                
                $appConfigIdTranslation{$appConfigJsonNew->{appconfigid}} = $newAppConfigId;
                $appConfigJsonNew->{appconfigid}                          = $newAppConfigId;
            }
        } else {
            foreach my $appConfigJson ( @{$siteJsonNew->{appconfigs}} ) {
                $appConfigIdTranslation{$appConfigJson->{appconfigid}} = $appConfigJson->{appconfigid};
            }
        }
        my $newSite = UBOS::Site->new( $siteJsonNew );
        if( $noTls ) {
            $newSite->deleteTlsInfo();
        }
        $sitesNew{$site->siteId} = $newSite;
    }

    info( 'Setting up placeholders for restored sites' );

    my $suspendTriggers = {};
    foreach my $siteNew ( values %sitesNew ) {
        $ret &= $siteNew->setupPlaceholder( $suspendTriggers ); # show "coming soon"
    }
    UBOS::Host::executeTriggers( $suspendTriggers );

    info( 'Deploying new version of sites' );

    my $deployUndeployTriggers = {};
    foreach my $siteNew ( values %sitesNew ) {
        $ret &= $siteNew->deploy( $deployUndeployTriggers );
    }
    UBOS::Host::executeTriggers( $deployUndeployTriggers );

    info( 'Restoring data' );

    foreach my $appConfigIdInBackup ( keys %appConfigIdTranslation ) {
        my $appConfigIdOnHost = $appConfigIdTranslation{$appConfigIdInBackup};
        my $appConfigInBackup = $appConfigsInBackup->{$appConfigIdInBackup};
        my $appConfigOnHost   = UBOS::Host::findAppConfigurationById( $appConfigIdOnHost );

        $ret &= $backup->restoreAppConfiguration(
                $appConfigInBackup,
                $appConfigOnHost );
    }

    info( 'Resuming site' );

    my $resumeTriggers = {};
    foreach my $siteNew ( values %sitesNew ) {
        $ret &= $siteNew->resume( $resumeTriggers );
    }
    UBOS::Host::executeTriggers( $resumeTriggers );

    info( 'Running upgraders' );

    foreach my $appConfigIdOnHost ( values %appConfigIdTranslation ) {
        my $appConfigOnHost = UBOS::Host::findAppConfigurationById( $appConfigIdOnHost );
        $ret &= $appConfigOnHost->runUpgrader();
    }

    if( $showIds ) {
        foreach my $siteNew ( values %sitesNew ) {
            print $siteNew->siteId . "\n";
        }
    }
    return $ret;
}

##
# Helper method to find an AppConfiguration from a partial id among the
# AppConfigurations in the backup.
sub _findAppConfigurationByPartialId {
    my $id                 = shift;
    my $appConfigsInBackup = shift;

    my $ret;
    if( $id =~ m!^(.*)\.\.\.$! ) {
        my $partial    = $1;
        my @candidates = ();

        foreach my $appConfigId ( keys %$appConfigsInBackup ) {
            my $appConfig = $appConfigsInBackup->{$appConfigId};

            if( $appConfig->appConfigId =~ m!^$partial! ) {
                push @candidates, $appConfig;
            }
        }
        if( @candidates == 1 ) {
            $ret = $candidates[0];

        } elsif( @candidates ) {
	        $@ = "There is more than one AppConfiguration in the backup whose app config id starts with $partial: "
                 . join( " vs ", map { $_->appConfigId } @candidates ) . '.';
            return undef;

        } else {
            $@ = "No AppConfiguration found in backup whose app config id starts with $partial.";
            return undef;
        }
	
    } else {
        foreach my $appConfigId ( keys %$appConfigsInBackup ) {
            my $appConfig = $appConfigsInBackup->{$appConfigId};

            if( $appConfig->appConfigId eq $id ) {
                $ret = $appConfig;
            }
        }
        unless( $ret ) {
            $@ = "No AppConfiguration found in backup with app config id $id.";
            return undef;
        }
    }

    unless( $ret ) {
        error( "Restore failed." );
    }
    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--notls] --in <backupfile>
SSS
    Restore all sites contained in backupfile. This includes all
    applications and their data. None of the sites in the backup file
    must currently exist on the host: siteids, appconfigids, and hostnames
    must all be different.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--notls] --siteid <siteid> [--hostname <hostname>] --in <backupfile>
SSS
    Restore the site with siteid contained in backupfile. This includes
    all applications at that site and their data. This site currently
    must not exist on the host: siteid, appconfigids, and hostname must
    all be different. Optionally use a different hostname.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--notls] --siteid <fromsiteid> --newsiteid <newsiteid> [--hostname <hostname>] --in <backupfile>
SSS
    Restore the site with siteid contained in backupfile, but instead of using
    the siteids and appconfigids given in the backup, use newsiteid for the
    siteid, and allocate new appconfigids. Optionally also use a different hostname.

    This exists mainly to facilitate testing.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] [--notls] --siteid <fromsiteid> --createnew [--hostname <hostname>] --in <backupfile>
SSS
    Restore the site with siteid contained in backupfile, but instead of using
    the siteids and appconfigids given in the backup, allocate new ones.
    Optionally also use a different hostname.

    This allows the user to run the restored backup of a site in parallel
    with the current site, albeit at a different hostname.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--showids] --appconfigid <appconfigid> ( --tositeid <tositeid> | --tohostname <tohostname> ) [--context <context>] --in <backupfile>
SSS
    Restore AppConfiguration appconfigid by adding it as a new AppConfiguration
    to a currently deployed Site with tositeid. No AppConfiguration with appconfigid
    must currently exist on the host. Optionally use a different context path
    for the AppConfiguration. 
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--showids] --appconfigid <appconfigid> ( --tositeid <tositeid> | --tohostname <tohostname> ) --createnew [--context <context>] --in <backupfile>
SSS
    Restore AppConfiguration appconfigid by adding it as a new AppConfiguration
    to a currently deployed Site with tositeid, but instead of using the
    appconfigid given in the backup, allocate a new one. Optionally use a
    different context path for the AppConfiguration. 
HHH
    };
}

1;
