#!/usr/bin/perl
#
# A Backup implemented as a ZIP file
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

package UBOS::Backup::ZipFileBackup;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use UBOS::AppConfiguration;
use UBOS::Backup::ZipFileBackupContext;
use UBOS::Configuration;
use UBOS::Logging;
use UBOS::Site;
use UBOS::Utils qw( readJsonFromString writeJsonToString );
use JSON;

use base qw( UBOS::AbstractBackup );
use fields qw( zip file );

my $fileType                 = 'UBOS backup v1';
my $zipFileTypeEntry         = 'filetype';
my $zipFileStartTimeEntry    = 'starttime';
my $zipFileSiteEntry         = 'sites';
my $zipFileInstallablesEntry = 'installables';
my $zipFileAppConfigsEntry   = 'appconfigs';

##
# Constructor.
sub new {
    my $self = shift;
    
    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    return $self;
}

##
# Save the specified sites and AppConfigurations to a file, and return the corresponding Backup object
# $siteIds: list of siteids to be contained in the backup
# $appConfigIds: list of appconfigids to be contained in the backup that aren't part of the sites with the siteids
# $outFile: the file to save the backup to
# return: success or fail
sub create {
    my $self         = shift;
    my $siteIds      = shift;
    my $appConfigIds = shift;
    my $outFile      = shift;

    my $sites         = {};
    my $appConfigs    = {};
    my @filesToDelete = ();

    if( defined( $siteIds ) && @$siteIds ) {
        foreach my $siteId ( @$siteIds ) {
            my $site = UBOS::Host::findSiteByPartialId( $siteId );
            unless( defined( $site )) {
                fatal( $@ );
            }
            if( $sites->{$siteId}) {
                fatal( 'Duplicate siteid', $siteId );
            }
            $sites->{$siteId} = $site;

            foreach my $appConfig ( @{$site->appConfigs} ) {
                $appConfigs->{$appConfig->appConfigId()} = $appConfig;
            }
        }
    }
    if( defined( $appConfigIds ) && @$appConfigIds ) {
        foreach my $appConfigId ( @$appConfigIds ) {
            if( $appConfigs->{$appConfigId} ) {
                fatal( 'Duplicate appconfigid', $appConfigId );
            }
            my $foundAppConfig = undef;
			my $mySites        = UBOS::Host::sites();
            foreach my $mySite ( values %$mySites ) {
                $foundAppConfig = $mySite->appConfig( $appConfigId );
                if( $foundAppConfig ) {
                    $appConfigs->{$appConfigId} = $foundAppConfig;
                    last;
                }
            }
            unless( $foundAppConfig ) {
                fatal( 'This server does not run a site that has an app with appconfigid', $appConfigId );
            }
        }
    }
    if( ( !defined( $siteIds ) || @$siteIds == 0 ) && ( !defined( $appConfigIds ) || @$appConfigIds == 0 )) {
        my $mySites = UBOS::Host::sites();
        foreach my $mySite ( values %$mySites ) {
            $sites->{$mySite->siteId} = $mySite;
            foreach my $appConfig ( @{$mySite->appConfigs} ) {
                $appConfigs->{$appConfig->appConfigId()} = $appConfig;
            }
        }
    }
    my $ret = 1;

    $self->{startTime}  = UBOS::Utils::time2string( time() );
    $self->{zip}        = Archive::Zip->new();
    $self->{sites}      = $sites;
    $self->{appConfigs} = $appConfigs;
    $self->{file}       = $outFile;

    ##
    my $zip = $self->{zip}; # makes code shorter

    $ret &= ( $zip->addString( $fileType,                 $zipFileTypeEntry )      ? 1 : 0 );
    $ret &= ( $zip->addString( $self->{startTime} . "\n", $zipFileStartTimeEntry ) ? 1 : 0 );

    ##

    $ret &= ( $zip->addDirectory( "$zipFileSiteEntry/" ) ? 1 : 0 );

    foreach my $site ( values %{$sites} ) {
        my $siteId = $site->siteId();
        $ret &= ( $zip->addString( writeJsonToString( $site->siteJson() ), "$zipFileSiteEntry/$siteId.json" ) ? 1 : 0 );
    }

    ##

    $ret &= ( $zip->addDirectory( "$zipFileInstallablesEntry/" ) ? 1 : 0 );

    # construct table of installables
    my %installables = ();
    foreach my $appConfig ( values %{$appConfigs} ) {
        foreach my $installable ( $appConfig->installables ) {
            $installables{$installable->packageName} = $installable;
        }
    }
    while( my( $packageName, $installable ) = each %installables ) {
        $ret &= ( $zip->addString( writeJsonToString( $installable->installableJson()), "$zipFileInstallablesEntry/$packageName.json" ) ? 1 : 0 );
    }

    ##

    $ret &= ( $zip->addDirectory( "$zipFileAppConfigsEntry/" ) ? 1 : 0 );

    my $rolesOnHost = UBOS::Host::rolesOnHost();
    
    foreach my $appConfig ( values %{$appConfigs} ) {
        my $appConfigId = $appConfig->appConfigId;
        $ret &= ( $zip->addString( writeJsonToString( $appConfig->appConfigurationJson()), "$zipFileAppConfigsEntry/$appConfigId.json" ) ? 1 : 0 );
        $ret &= ( $zip->addDirectory( "$zipFileAppConfigsEntry/$appConfigId/" ) ? 1 : 0 );

        foreach my $installable ( $appConfig->installables ) {
            my $packageName = $installable->packageName;
            $ret &= ( $zip->addDirectory( "$zipFileAppConfigsEntry/$appConfigId/$packageName/" ) ? 1 : 0 );

            my $config = new UBOS::Configuration(
                    "Installable=$packageName,AppConfiguration=" . $appConfigId,
                    {},
                    $installable->config,
                    $appConfig->config );

            foreach my $roleName ( @{$installable->roleNames} ) {
                my $role = $rolesOnHost->{$roleName};
                if( $role ) { # don't attempt to backup anything not installed on this host
                    my $appConfigPathInZip = "$zipFileAppConfigsEntry/$appConfigId/$packageName/$roleName";
                    $ret &= ( $zip->addDirectory( "$appConfigPathInZip/" ) ? 1 : 0 );

                    my $dir = $config->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );

                    my $appConfigItems = $installable->appConfigItemsInRole( $roleName );
                    if( $appConfigItems ) {
                        my $backupContext = new UBOS::Backup::ZipFileBackupContext( $self, $appConfigPathInZip );

                        foreach my $appConfigItem ( @$appConfigItems ) {
                            if( !defined( $appConfigItem->{retentionpolicy} ) || !$appConfigItem->{retentionpolicy} ) {
                                # for now, we don't care what value this field has as long as it is non-empty
                                next;
                            }
                            my $item = $role->instantiateAppConfigurationItem( $appConfigItem, $appConfig, $installable );
                            if( $item ) {
                                $ret &= $item->backup( $dir, $config, $backupContext, \@filesToDelete );
                            }
                        }
                    }
                }
            }
        }
    }

    $ret &= (( $zip->writeToFileNamed( $outFile ) == AZ_OK ) ? 1 : 0 );

    foreach my $current ( @filesToDelete ) {
        unless( unlink $current ) {
            error( 'Could not unlink', $current );
            $ret = 0;
        }
    }

    return $ret;
}

##
# Instantiate a Backup object from an archive file
# $archive: the archive file name
# return: the Backup object
sub readArchive {
    my $self    = shift;
    my $archive = shift;

    $self->{sites}      = {};
    $self->{appConfigs} = {};
    $self->{file}       = $archive;

    $self->{zip} = Archive::Zip->new();
    unless( $self->{zip}->read( $archive ) == AZ_OK ) {
        error( 'Failed reading file', $archive );
        return 0;
    }

    my $foundFileType = $self->{zip}->contents( $zipFileTypeEntry );
    if( $foundFileType ) {
        $foundFileType =~ s!^\s+!!;
        $foundFileType =~ s!\s+$!!;

        unless( $foundFileType eq $fileType ) {
            error( 'Invalid file type:', $foundFileType, "(expecting $fileType)" );
            return 0;
        }
    } else {
        error( 'No file type entry found. Is this a ubos backup file?' );
        return 0;
    }

    my $ret = 1;
    
    foreach my $siteJsonFile ( $self->{zip}->membersMatching( "$zipFileSiteEntry/.*\.json" )) {
        my $siteJsonContent = $self->{zip}->contents( $siteJsonFile );
        if( $siteJsonContent ) {
            my $siteJson  = readJsonFromString( $siteJsonContent );

            my $site = new UBOS::Site( $siteJson );

            $self->{sites}->{$site->siteId()} = $site;
        } else {
            error( 'Cannot read ZIP file entry', $siteJsonFile );
            $ret = 0;
        }
    }
    foreach my $appConfigJsonFile ( $self->{zip}->membersMatching( "$zipFileAppConfigsEntry/.*\.json" )) {
        my $appConfigJsonContent = $self->{zip}->contents( $appConfigJsonFile );
        if( $appConfigJsonContent ) {
            my $appConfigJson = readJsonFromString( $appConfigJsonContent );

            my $appConfig = new UBOS::AppConfiguration( $appConfigJson );

            $self->{appConfigs}->{$appConfig->appConfigId()} = $appConfig;
        } else {
            error( 'Cannot read ZIP file entry', $appConfigJsonFile );
            $ret = 0;
        }
    }

    $self->{startTime} = $self->{zip}->contents( $zipFileStartTimeEntry );

    return $ret;
}


##
# Obtain the file that holds this Backup, if any
# return: file name
sub fileName {
    my $self = shift;

    return $self->{file};
}
    
##
# Restore a single AppConfiguration from Backup
# $siteId: the SiteId of the AppConfiguration
# $appConfig: the AppConfiguration to restore
# return: success or fail
sub restoreAppConfiguration {
    my $self      = shift;
    my $siteId    = shift;
    my $appConfig = shift;

    my $ret         = 1;
    my $zip         = $self->{zip};
    my $appConfigId = $appConfig->appConfigId;
    my $rolesOnHost = UBOS::Host::rolesOnHost();

    foreach my $installable ( $appConfig->installables ) {
        my $packageName = $installable->packageName;

        unless( $zip->memberNamed( "$zipFileAppConfigsEntry/$appConfigId/$packageName/" )) {
            next;
        }

        my $config = new UBOS::Configuration(
                "Installable=$packageName,AppConfiguration=" . $appConfigId,
                {},
                $installable->config,
                $appConfig->config );

        foreach my $roleName ( @{$installable->roleNames} ) {
            my $role = $rolesOnHost->{$roleName};
            if( $role ) { # don't attempt to restore anything not installed on this host
                my $appConfigPathInZip = "$zipFileAppConfigsEntry/$appConfigId/$packageName/$roleName";
                unless( $zip->memberNamed( "$appConfigPathInZip/" )) {
                    next;
                }

                my $appConfigItems = $installable->appConfigItemsInRole( $roleName );
                if( $appConfigItems ) {
                    my $dir = $config->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );

                    my $backupContext = new UBOS::Backup::ZipFileBackupContext( $self, $appConfigPathInZip );

                    foreach my $appConfigItem ( @$appConfigItems ) {
                        if( !defined( $appConfigItem->{retentionpolicy} ) || !$appConfigItem->{retentionpolicy} ) {
                            # for now, we don't care what value this field has as long as it is non-empty
                            next;
                        }
                        my $item = $role->instantiateAppConfigurationItem( $appConfigItem, $appConfig, $installable );
                        if( $item ) {
                            $ret &= $item->restore( $dir, $config, $backupContext );
                        }
                    }
                }
            }
        }
    }
    return $ret;
}

1;
