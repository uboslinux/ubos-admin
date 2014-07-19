#!/usr/bin/perl
#
# Command that undeploys one or more sites.
#
# This file is part of indiebox-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Commands::Undeploy;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray );
use IndieBox::BackupManagers::ZipFileBackupManager;
use IndieBox::Host;
use IndieBox::Logging;
use IndieBox::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    my @siteIds = ();
    my $file    = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'siteid=s' => \@siteIds,
            'file=s'   => \$file );

    if( !$parseOk || @args || ( !@siteIds && !$file ) || ( @siteIds && $file )) {
        fatal( 'Invalid command-line arguments, add --help for help' );
    }
    
    debug( 'Looking for site(s)' );

    if( $file ) {
        # if $file is given, construct @siteIds from there
        my $json = readJsonFromFile( $file );
        $json = IndieBox::Utils::insertSlurpedFiles( $json, dirname( $file ) );

        if( ref( $json ) eq 'HASH' && %$json ) {
            # This is either a site json directly, or a hash of site jsons (for which we ignore the keys)
            if( defined( $json->{siteid} )) {
                @siteIds = ( $json->{siteid} );
            } else {
                @siteIds = map { $_->{siteid} || fatal( 'No siteid found in JSON file' ) } values %$json;
            }
        } elsif( ref( $json ) eq 'ARRAY' ) {
            if( !@$json ) {
                fatal( 'No site given' );
            } else {
                @siteIds = map { $_->{siteid} || fatal( 'No siteid found in JSON file' ) } @$json;
            }
        }
    }

    my $oldSites = {};
    foreach my $siteId ( @siteIds ) {
        my $site = IndieBox::Host::findSiteByPartialId( $siteId );
        if( $site ) {
            $oldSites->{$site->siteId} = $site;
        } else {
            fatal( "Cannot find site with siteid $siteId. Not undeploying any site." );
        }
        $site->checkUndeployable;
    }

    # May not be interrupted, bad things may happen if it is
	IndieBox::Host::preventInterruptions();

    debug( 'Disabling site(s)' );

    my $disableTriggers = {};
    foreach my $oldSite ( values %$oldSites ) {
        $oldSite->disable( $disableTriggers ); # replace with "404 page"
    }
    IndieBox::Host::executeTriggers( $disableTriggers );

    debug( 'Backing up and undeploying' );

    my $backupManager = new IndieBox::BackupManagers::ZipFileBackupManager();

    my $adminBackups     = {};
    my $undeployTriggers = {};
    foreach my $oldSite ( values %$oldSites ) {
        my $backup  = $backupManager->adminBackupSite( $oldSite );
        $oldSite->undeploy( $undeployTriggers );
        $adminBackups->{$oldSite->siteId} = $backup;
    }
    IndieBox::Host::executeTriggers( $undeployTriggers );

    $backupManager->purgeAdminBackups();
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    --siteid <siteid> [--siteid <siteid>]...
SSS
    Undeploy one or more previously deployed website(s).
HHH
        <<SSS => <<HHH
    --file <site.json>
SSS
    Undeploy one or more previously deployed website(s) whose site JSON
    file is given. This is a convenience invocation.
HHH
    };
}

1;
