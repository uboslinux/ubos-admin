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

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my @siteIds = ();
    my @hosts   = ();
    my $file    = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'siteid=s' => \@siteIds,
            'host=s'   => \@hosts,
            'file=s'   => \$file );

    if( !$parseOk || @args || ( !@siteIds && !@hosts && !$file )
                           || ( @siteIds && @hosts )
                           || ( @siteIds && $file )
                           || ( @hosts && $file ))
    {
        fatal( 'Invalid invocation: undeploy', @_, '(add --help for help)' );
    }
    
    debug( 'Looking for site(s)' );

    my $oldSites = {};
    if( @hosts ) {
        my $sites = IndieBox::Host::sites();
        
        foreach my $host ( @hosts ) {
            my $found = 0;
            while( my( $siteId, $site ) = each %$sites ) {
                if( $site->hostName eq $host ) {
                    $oldSites->{$siteId} = $site;
                    $found = 1;
                    last;
                }
            }
            unless( $found ) {
                fatal( "Cannot find site with hostname $host. Not undeploying any site." );
            }
        }

    } else {
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

        foreach my $siteId ( @siteIds ) {
            my $site = IndieBox::Host::findSiteByPartialId( $siteId );
            if( $site ) {
                $oldSites->{$site->siteId} = $site;
            } else {
                fatal( "Cannot find site with siteid $siteId. Not undeploying any site." );
            }
            $site->checkUndeployable;
        }
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
    Undeploy one or more previously deployed website(s) by specifying their site id.
HHH
        <<SSS => <<HHH,
    --host <hostname> [--host <hostname>]...
SSS
    Undeploy one or more previously deployed website(s) by specifying their hostname.
    This is equivalent to undeploying the site ids, but may be more convenient.
HHH
        <<SSS => <<HHH
    --file <site.json>
SSS
    Undeploy one or more previously deployed website(s) whose site JSON
    file is given. This is equivalent to undeploying the site ids of the
    site(s) contained in the file.
HHH
    };
}

1;
