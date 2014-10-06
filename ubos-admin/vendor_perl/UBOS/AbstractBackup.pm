#!/usr/bin/perl
#
# Abstract superclass for Backups
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

package UBOS::AbstractBackup;

use fields qw( sites appConfigs startTime );

use UBOS::Logging;

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

    error( 'Cannot perform new on', $self );
}

##
# Instantiate a Backup object from an archive file
# $archive: the archive file name
# return: the Backup object
sub newFromArchive {
    my $self    = shift;
    my $archive = shift;

    error( 'Cannot perform newFromArchive on', $self );
}

##
# Determine the start time in UNIX time format
sub startTime {
    my $self = shift;

    return UBOS::Utils::string2time( $self->{startTime} );
}

##
# Determine the sites contained in this Backup.
# return: hash of siteid to Site
sub sites {
    my $self = shift;

    return $self->{sites};
}

##
# Determine the AppConfigurations contained in this Backup.
# return: hash of appconfigid to AppConfiguration
sub appConfigs {
    my $self = shift;

    return $self->{appConfigs};
}

##
# Restore a site including all AppConfigurations from a backup
# $site: the Site to restore
# $backup: the Backup from where to restore
# return: success or fail
sub restoreSite {
    my $self    = shift;
    my $site    = shift;

    my $ret = 1;
    foreach my $appConfig ( @{$site->appConfigs} ) {
        $ret &= $self->restoreAppConfiguration( $site->siteId, $appConfig );
    }

    return $ret;
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

    error( 'Cannot perform restoreAppConfiguration on', $self );
}

1;
