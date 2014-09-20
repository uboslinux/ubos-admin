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

package UBOS::BackupManagers::ZipFileBackup;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use UBOS::AppConfiguration;
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
# Save the specified sites and AppConfigurations to a file, and return the corresponding Backup object
# $siteIds: list of siteids to be contained in the backup
# $appConfigIds: list of appconfigids to be contained in the backup that aren't part of the sites with the siteids
# $outFile: the file to save the backup to
sub new {
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
                fatal( 'This server does not run site', $siteId );
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

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    $self->{startTime}  = UBOS::Utils::time2string( time() );
    $self->{sites}      = $sites;
    $self->{appConfigs} = $appConfigs;
    $self->{zip}        = Archive::Zip->new();
    $self->{file}       = $outFile;

    ##
    my $zip = $self->{zip}; # makes code shorter

    $zip->addString( $fileType,                 $zipFileTypeEntry );
    $zip->addString( $self->{startTime} . "\n", $zipFileStartTimeEntry );

    ##

    $zip->addDirectory( "$zipFileSiteEntry/" );

    foreach my $site ( values %{$sites} ) {
        my $siteId = $site->siteId();
        $zip->addString( writeJsonToString( $site->siteJson() ), "$zipFileSiteEntry/$siteId.json" );
    }

    ##

    $zip->addDirectory( "$zipFileInstallablesEntry/" );

    # construct table of installables
    my %installables = ();
    foreach my $appConfig ( values %{$appConfigs} ) {
        foreach my $installable ( $appConfig->installables ) {
            $installables{$installable->packageName} = $installable;
        }
    }
    while( my( $packageName, $installable ) = each %installables ) {
        $zip->addString( writeJsonToString( $installable->installableJson()), "$zipFileInstallablesEntry/$packageName.json" );
    }

    ##

    $zip->addDirectory( "$zipFileAppConfigsEntry/" );

    my $rolesOnHost = UBOS::Host::rolesOnHost();
    
    foreach my $appConfig ( values %{$appConfigs} ) {
        my $appConfigId = $appConfig->appConfigId;
        $zip->addString( writeJsonToString( $appConfig->appConfigurationJson()), "$zipFileAppConfigsEntry/$appConfigId.json" );
        $zip->addDirectory( "$zipFileAppConfigsEntry/$appConfigId/" );

        foreach my $installable ( $appConfig->installables ) {
            my $packageName = $installable->packageName;
            $zip->addDirectory( "$zipFileAppConfigsEntry/$appConfigId/$packageName/" );

            my $config = new UBOS::Configuration(
                    "Installable=$packageName,AppConfiguration=" . $appConfigId,
                    {},
                    $installable->config,
                    $appConfig->config );

            foreach my $roleName ( @{$installable->roleNames} ) {
                my $role = $rolesOnHost->{$roleName};
                if( $role ) { # don't attempt to backup anything not installed on this host
                    my $appConfigPathInZip = "$zipFileAppConfigsEntry/$appConfigId/$packageName/$roleName";
                    $zip->addDirectory( "$appConfigPathInZip/" );

                    my $dir = $config->getResolveOrNull( "appconfig.$roleName.dir", undef, 1 );

                    my $appConfigItems = $installable->appConfigItemsInRole( $roleName );
                    if( $appConfigItems ) {

                        foreach my $appConfigItem ( @$appConfigItems ) {
                            if( !defined( $appConfigItem->{retentionpolicy} ) || !$appConfigItem->{retentionpolicy} ) {
                                # for now, we don't care what value this field has as long as it is non-empty
                                next;
                            }
                            my $item = $role->instantiateAppConfigurationItem( $appConfigItem, $appConfig, $installable );
                            if( $item ) {
                                $item->backup( $dir, $config, $self, $appConfigPathInZip, \@filesToDelete );
                            }
                        }
                    }
                }
            }
        }
    }

    $zip->writeToFileNamed( $outFile );

    foreach my $current ( @filesToDelete ) {
        unlink $current || error( 'Could not unlink', $current );
    }

    return $self;
}

##
# Instantiate a Backup object from an archive file
# $archive: the archive file name
# return: the Backup object
sub newFromArchive {
    my $self    = shift;
    my $archive = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    $self->{sites}      = {};
    $self->{appConfigs} = {};
    $self->{file}       = $archive;

    $self->{zip} = Archive::Zip->new();
    unless( $self->{zip}->read( $archive ) == AZ_OK ) {
        fatal( 'Failed reading file', $archive );
    }

    my $foundFileType = $self->{zip}->contents( $zipFileTypeEntry );
    unless( $foundFileType eq $fileType ) {
        fatal( 'Invalid file type:', $foundFileType );
    }

    foreach my $siteJsonFile ( $self->{zip}->membersMatching( "$zipFileSiteEntry/.*\.json" )) {
        my $siteJsonContent = $self->{zip}->contents( $siteJsonFile );
        my $siteJson        = readJsonFromString( $siteJsonContent );

        my $site = new UBOS::Site( $siteJson );

        $self->{sites}->{$site->siteId()} = $site;
    }
    foreach my $appConfigJsonFile ( $self->{zip}->membersMatching( "$zipFileAppConfigsEntry/.*\.json" )) {
        my $appConfigJsonContent = $self->{zip}->contents( $appConfigJsonFile );
        my $appConfigJson        = readJsonFromString( $appConfigJsonContent );

        my $appConfig = new UBOS::AppConfiguration( $appConfigJson );

        $self->{appConfigs}->{$appConfig->appConfigId()} = $appConfig;
    }

    $self->{startTime} = $self->{zip}->contents( $zipFileStartTimeEntry );

    return $self;
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
sub restoreAppConfiguration {
    my $self      = shift;
    my $siteId    = shift;
    my $appConfig = shift;

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

                    foreach my $appConfigItem ( @$appConfigItems ) {
                        if( !defined( $appConfigItem->{retentionpolicy} ) || !$appConfigItem->{retentionpolicy} ) {
                            # for now, we don't care what value this field has as long as it is non-empty
                            next;
                        }
                        my $item = $role->instantiateAppConfigurationItem( $appConfigItem, $appConfig, $installable );
                        if( $item ) {
                            $item->restore( $dir, $config, $self, $appConfigPathInZip );
                        }
                    }
                }
            }
        }
    }
}

##
# Callback by which an AppConfigurationItem can add a file to a Backup
# $fileToAdd: the name of the file to add in the file system
# $nameInBackup: the name of the file in the Backup
sub addFile {
    my $self         = shift;
    my $fileToAdd    = shift;
    my $nameInBackup = shift;

    $self->{zip}->addFile( $fileToAdd, $nameInBackup );
}

##
# Callback by which an AppConfigurationItem can add a directory hierarchy to a Backup
# $dirToAdd: the name of the directory to add in the file system
# $nameInBackup: the name of the directory in the Backup
sub addDirectoryHierarchy {
    my $self         = shift;
    my $dirToAdd     = shift;
    my $nameInBackup = shift;

    $self->_addRecursive( $dirToAdd, $nameInBackup );
}

##
# Recursive helper method to add a directory hierarchy to a zip file
# $fileName: the name of the object in the filesystem
# $zipName: the name of the object in the zip file
sub _addRecursive {
    my $self     = shift;
    my $fileName = shift;
    my $zipName  = shift;

    if( -l $fileName ) {
        my $member = $self->{zip}->addString( readlink $fileName, $zipName );
        $member->{'externalFileAttributes'} = 0xA1FF0000;
        # This comes from the source code of Archive::Zip; there doesn't seem to be an API

    } elsif( -f $fileName ) {
        $self->{zip}->addFile( $fileName, $zipName );

    } elsif( -d $fileName ) {
        $self->{zip}->addDirectory( "$fileName/", "$zipName/" );

        my @children = ();
        opendir( DIR, $fileName ) or fatal( 'Could not read directory', $fileName, $! );

        while( my $file = readdir( DIR )) {
            if( $file =~ m!^\.\.?$! ) { # skip . and .. but not other .something files
                next;
            }
            push @children, "$fileName/$file";
        }
        closedir( DIR );

        foreach my $child ( @children ) {
            my $relative = $child;
            $relative = substr( $relative, length( $fileName ) + 1 );

            $self->_addRecursive( $child, "$zipName/$relative" );
        }

    } else {
        warning( 'Not a file or directory. Backup skipping:', $fileName, 'not a file or directory.' );
    }

    1;
}

##
# Callback by which an AppConfigurationItem can extract a file from a Backup
# $nameInBackup: the name of the file in the Backup
# $fileName: name of the file in the filesystem to be written
# return: 1 if the extraction was performed
sub restore {
    my $self         = shift;
    my $nameInBackup = shift;
    my $fileName     = shift;

    my $member = $self->{zip}->memberNamed( $nameInBackup );
    if( $member ) {
        $self->{zip}->extractMember( $member, $fileName );

        return 1;
    }
    return 0;
}


##
# Helper method to restore a directory hierarchy from a Backup
# $nameInBackup: the name of the directory in the Backup
# $dirName: name of the director in the filesystem to be written
sub restoreRecursive {
    my $self         = shift;
    my $nameInBackup = shift;
    my $dirName      = shift;
    my $mode         = shift;
    my $uid          = shift;
    my $gid          = shift;

    $self->{zip}->extractTree( $nameInBackup, $dirName );

    my $asOct;
    if( $mode == -1 ) {
        $asOct = "755";
    } else {
        $asOct = sprintf( "%o", $mode );
    }
    UBOS::Utils::myexec( "chmod -R $asOct $dirName" ); # no -h on Linux

    if( defined( $uid )) {
        UBOS::Utils::myexec( 'chown -R -h ' . ( 0 + $uid ) . " $dirName" );
    }
    if( defined( $gid )) {
        UBOS::Utils::myexec( 'chgrp -R -h ' . ( 0 + $gid ) . " $dirName" );
    }

    1;
}
1;
