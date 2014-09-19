#!/usr/bin/perl
#
# Abstract supertype of BackupManager implementations.
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

package UBOS::AbstractBackupManager;

use fields;

##
# Constructor
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

    error( 'Cannot perform backup on', $self );
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
# Read a Backup
# $archive: the archive file name
sub newFromArchive {
    my $self    = shift;
    my $archive = shift;
    
    error( 'Cannot perform newFromArchive on', $self );
}

1;
