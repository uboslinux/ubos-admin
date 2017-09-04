#!/usr/bin/perl
#
# Abstract superclass for Backups
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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
# Constructor.
sub new {
    my $self = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    return $self;
}

##
# Save the specified Sites and AppConfigurations to a file, and return the
# corresponding Backup object. If a Site has N AppConfigurations, all of those
# AppConfigurations must be listed in the $appConfigs
# array to be backed up. If they are not, only Site meta-data (but none of the AppConfiguration data)
# will be saved.
# $sites: array of Site objects
# $appConfigs: array of AppConfiguration objects
# $noTls: if 1, do not include TLS info
# $noTorKey: if 1, do not include Tor private keys for Tor sites
# $outFile: the file to save the backup to
sub create {
    my $self          = shift;
    my $sites         = shift;
    my $appConfigs    = shift;
    my $noTls         = shift;
    my $noTorKey      = shift;
    my $outFile       = shift;

    error( 'Cannot perform create on', $self );
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
# Determine the type of backup
sub backupType {
    my $self = shift;

    return ref( $self );
}

##
# Determine the start time in UNIX time format
sub startTime {
    my $self = shift;

    return UBOS::Utils::string2time( $self->{startTime} );
}

##
# Determine the start time in printable time format
sub startTimeString {
    my $self = shift;

    return $self->{startTime};
}

##
# Determine the sites contained in this Backup.
# return: hash of siteid to Site
sub sites {
    my $self = shift;

    return $self->{sites};
}

##
# Find one site with a given siteId contained in this Backup
# return: Site
sub findSiteById {
    my $self   = shift;
    my $siteId = shift;

    return UBOS::Host::findSiteById( $siteId, $self->{sites} );
}

##
# Find one site with a partial siteId contained in this Backup
# return: Site
sub findSiteByPartialId {
    my $self   = shift;
    my $siteId = shift;

    return UBOS::Host::findSiteByPartialId( $siteId, $self->{sites} );
}

##
# Find one site with a given hostname contained in this Backup
# return: Site
sub findSiteByHostname {
    my $self     = shift;
    my $hostname = shift;

    return UBOS::Host::findSiteByHostname( $hostname, $self->{sites} );
}

##
# Determine the AppConfigurations contained in this Backup.
# return: hash of appconfigid to AppConfiguration
sub appConfigs {
    my $self = shift;

    return $self->{appConfigs};
}

##
# Find one AppConfiguration with a given appConfigId contained in this Backup
# return: AppConfiguration
sub findAppConfigurationById {
    my $self        = shift;
    my $appConfigId = shift;

    foreach my $appConfigId ( keys %{$self->{appConfigs}} ) {
        my $appConfig = $self->{appConfigs}->{$appConfigId};

        if( $appConfig->appConfigId eq $appConfigId ) {
            return $appConfig;
        }
    }
    return undef;
}

##
# Find one AppConfiguration from a given appConfigId contained in this Backup
# return: AppConfiguration
sub findAppConfigurationByPartialId {
    my $self               = shift;
    my $appConfigId        = shift;
    my $appConfigsInBackup = shift;

    my $ret;
    if( $appConfigId =~ m!^(.*)\.\.\.$! ) {
        my $partial    = $1;
        my @candidates = ();

        foreach my $appConfigId ( keys %{$self->{appConfigs}} ) {
            my $appConfig = $self->{appConfigs}->{$appConfigId};

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
        foreach my $appConfig ( values %{$self->appConfigs} ) {
            if( $appConfig->appConfigId eq $appConfigId ) {
                $ret = $appConfig;
            }
        }
        unless( $ret ) {
            $@ = "No AppConfiguration found in backup with app config id $appConfigId.";
            return undef;
        }
    }

    return $ret;
}

##
# Restore a site including all AppConfigurations from a backup
# $site: the Site to restore
# $backup: the Backup from where to restore
# return: success or fail
sub restoreSite {
    my $self    = shift;
    my $site    = shift;

    my $siteId = $site->siteId();
    my $ret = 1;
    foreach my $appConfig ( @{$site->appConfigs} ) {
        debugAndSuspend( 'AppConfiguration', $appConfig, 'of site', $siteId );
        $ret &= $self->restoreAppConfiguration( $siteId, $siteId, $appConfig, $appConfig );
    }

    return $ret;
}

##
# Restore a single AppConfiguration from Backup.
# $siteIdInBackup: the site id of the AppConfiguration to restore, as it is stored in the Backup
# $siteIdOnHost: the site id of the AppConfiguration to restore, on the host
# $appConfigInBackup: the AppConfiguration to restore, as it is stored in the Backup
# $appConfigOnHost: the AppConfiguration to restore to, on the host
# $migrationTable: hash of old package names to new packages names, for migrations
# return: success or fail
sub restoreAppConfiguration {
    my $self              = shift;
    my $siteIdInBackup    = shift;
    my $siteIdOnHost      = shift;
    my $appConfigInBackup = shift;
    my $appConfigOnHost   = shift;
    my $migrationTable    = shift;

    error( 'Cannot perform restoreAppConfiguration on', $self );
}

1;
