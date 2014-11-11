#!/usr/bin/perl
#
# Command that lists the currently deployed sites.
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

package UBOS::Commands::Listsites;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $json          = 0;
    my $brief         = 0;
    my @siteIds       = ();
    my $backupFile    = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'json'         => \$json,
            'brief'        => \$brief,
            'siteid=s'     => \@siteIds,
            'backupfile=s' => \$backupFile );

    UBOS::Logging::initialize( 'ubos-admin', 'listsites', $verbose, $logConfigFile );

    if( !$parseOk || ( $json && $brief ) || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation: listsites', @_, '(add --help for help)' );
    }

    my $sites;
    if( $backupFile ) {
        unless( -r $backupFile ) {
            fatal( 'Cannot read backup file', $backupFile );
        }

        my $backup = UBOS::Backup::ZipFileBackup->new();
        unless( $backup->readArchive( $backupFile )) {
            fatal( 'Parsing backup file failed:', $backupFile );
        }
        my $sitesInBackup = $backup->sites();
        if( @siteIds ) {
            foreach my $siteId ( sort @siteIds ) {
                my $site = $sitesInBackup->{ $siteId };
                if( $site ) {
                    $sites->{$site->siteId} = $site;
                } else {
                    fatal( 'Cannot find Site with siteid', $siteId, 'in backup' );
                }
            }
        } else {
            $sites = $sitesInBackup;
        }

    } else {
        if( @siteIds ) {
            foreach my $siteId ( sort @siteIds ) {
                my $site = UBOS::Host::findSiteByPartialId( $siteId );
                if( $site ) {
                    $sites->{$site->siteId} = $site;
                } else {
                    fatal( $@ );
                }
            }
        } else {
            $sites = UBOS::Host::sites();
        }
    }

    if( $json ) {
        my $sitesJson = {};
        foreach my $site ( sort values %$sites ) {
            $sitesJson->{$site->siteId} = $site->siteJson;
        }
        UBOS::Utils::writeJsonToStdout( $sitesJson );

    } else {
        foreach my $site ( sort values %$sites ) {
            $site->print( $brief ? 1 : 2 );
        }
    }
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--json | --brief] [--siteid <siteid>]...
SSS
    Show the sites with siteid, or if not given, show all sites currently
    deployed to this device. If invoked as root, more information is available.
    --json: show them in JSON format
    --brief: only show the site ids.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--json | --brief] [--siteid <siteid>]... --backupfile <file>
SSS
    Show the sites with siteid, or if not given, show all sites contained
    in the specified backup file. If invoked as root, more information is available.
    --json: show them in JSON format
    --brief: only show the site ids.
    --backupfile: name of the backup file
HHH
    };
}

1;
