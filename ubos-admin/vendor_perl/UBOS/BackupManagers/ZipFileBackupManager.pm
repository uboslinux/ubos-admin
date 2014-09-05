#!/usr/bin/perl
#
# Manages Backups implemented as a ZIP file
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

package UBOS::BackupManagers::ZipFileBackupManager;

use fields;

use UBOS::BackupManagers::ZipFileBackup;
use UBOS::Logging;

##
# Constructor
# $dir: the directory in which to make new backups
sub new {
    my $self = shift;
    
    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    return $self;
}

##
# Create a Backup.
# $siteIds: list of siteids to be contained in the backup
# $appConfigIds: list of appconfigids to be contained in the backup that aren't part of the sites with the siteids
# $outFile: the file to save the backup to, if any
# return: the Backup object
sub backup {
    my $self         = shift;
    my $siteIds      = shift;
    my $appConfigIds = shift;
    my $outFile      = shift;

    return new UBOS::BackupManagers::ZipFileBackup( $siteIds, $appConfigIds, $outFile );
}

##
# Convenience method to create a Backup containing exactly one site.
# $site: the Site to be backed up
# $outFile: the file to save the backup to
# return: the Backup object
sub backupSite {
    my $self    = shift;
    my $site    = shift;
    my $outFile = shift;
    
    return $self->backup( [ $site->siteId ], undef, $outFile );
}

##
# Convenience method to create an administrative Backup containing exactly one site.
# $site: the Site to be backed up
# return: the Backup object
sub adminBackupSite {
    my $self    = shift;
    my $site    = shift;
    
    my $config  = $site->config;
    my $outFile = $config->getResolve( 'zipfilebackupmanager.adminsitebackupfile' );

    return $self->backup( [ $site->siteId ], undef, $outFile );
}

##
# Convenience method to create a Backup containing exactly one site.
# $site: the Site to be backed up
# $outFile: the file to save the backup to, if any
# return: the Backup object
sub testBackupSite {
    my $self    = shift;
    my $site    = shift;
    
    my $config  = $site->config;
    my $outFile = $config->getResolve( 'zipfilebackupmanager.testsitebackupfile' );

    return $self->backup( [ $site->siteId ], undef, $outFile );
}

##
# Read a Backup
# $archive: the archive file name
sub newFromArchive {
    my $self    = shift;
    my $archive = shift;
    
    return UBOS::BackupManagers::ZipFileBackup->newFromArchive( $archive );
}

##
# Purge administrative backups on this device.
sub purgeAdminBackups {

    return _purgeBackupsIn(
            UBOS::Host::config()->getResolve( 'zipfilebackupmanager.adminbackupdir' ),
            UBOS::Host::config()->getResolve( 'zipfilebackupmanager.adminbackuplifetime' ));
}

##
# Purge testing backups on this device.
sub purgeTestBackups {

    return _purgeBackupsIn(
            UBOS::Host::config()->getResolve( 'zipfilebackupmanager.testbackupdir' ),
            UBOS::Host::config()->getResolve( 'zipfilebackupmanager.testbackuplifetime' ));
}

##
# Purge backups located in the given directory that are older than the given seconds.
sub _purgeBackupsIn {
    my $dir     = shift;
    my $seconds = shift;
    my $suffix  = shift || UBOS::Host::config()->getResolve( 'zipfilebackupmanager.backupsuffix' );
    
    unless( $dir && $seconds ) {
        return 0;
    }
    
    debug( '_purgeBackupsIn', $dir, $seconds, $suffix );

    my $cutoff = time() - $seconds;
    my @files = <"$dir*$suffix">;
    foreach my $file ( @files ) {
        my $backup = UBOS::BackupManagers::ZipFileBackup->newFromArchive( $file );
        if( $backup->startTime() < $cutoff ) {
            UBOS::Utils::deleteFile( $file );
        }
    }
    return 1;
}

1;
