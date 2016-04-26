#!/usr/bin/perl
#
# Command that undeploys one or more sites.
#
# This file is part of ubos-admin.
# (C) 2012-2015 Indie Computing Corp.
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

package UBOS::Commands::Undeploy;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray );
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
    my @siteIds       = ();
    my @hosts         = ();
    my $all           = 0;
    my $file          = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'siteid=s'    => \@siteIds,
            'hostname=s'  => \@hosts,
            'all'         => \$all,
            'file=s'      => \$file );

    UBOS::Logging::initialize( 'ubos-admin', 'undeploy', $verbose, $logConfigFile );

    if( !$parseOk || @args || ( !@siteIds && !@hosts && !$all && !$file )
                           || ( @siteIds && @hosts )
                           || ( @siteIds && $file )
                           || ( @hosts && $file )
                           || ( $all && ( @siteIds || @hosts || $file ))
                           || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation: undeploy', @_, '(add --help for help)' );
    }
    
    debug( 'Looking for site(s)' );

    my $oldSites = {};
    if( @hosts ) {        
        foreach my $host ( @hosts ) {
            my $site = UBOS::Host::findSiteByHostname( $host );
            if( $site ) {
                $oldSites->{$site->siteId} = $site;
            } else {
                fatal( "Cannot find site with hostname $host. Not undeploying any site." );
            }
        }

    } elsif( $all ) {
        $oldSites = UBOS::Host::sites();

    } else {
        if( $file ) {
            # if $file is given, construct @siteIds from there
            my $json = readJsonFromFile( $file );
            $json = UBOS::Utils::insertSlurpedFiles( $json, dirname( $file ) );

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
            my $site = UBOS::Host::findSiteByPartialId( $siteId );
            if( $site ) {
                $oldSites->{$site->siteId} = $site;
            } else {
                fatal( "$@ Not undeploying any site." );
            }
        }
    }

    foreach my $site ( values %$oldSites ) {
        unless( $site->checkUndeployable ) {
            fatal( 'Cannot undeploy site', $site->siteId );
        }
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();
    my $ret = 1;

    debug( 'Disabling site(s)' );

    my $disableTriggers = {};
    foreach my $oldSite ( values %$oldSites ) {
        $ret &= $oldSite->disable( $disableTriggers ); # replace with "404 page"
    }
    UBOS::Host::executeTriggers( $disableTriggers );

    info( 'Undeploying' );

    my $undeployTriggers = {};
    foreach my $oldSite ( values %$oldSites ) {
        $ret &= $oldSite->undeploy( $undeployTriggers );
    }
    UBOS::Host::executeTriggers( $undeployTriggers );

    unless( $ret ) {
        error( "Undeploy failed." );
    }
    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] --siteid <siteid> [--siteid <siteid>]...
SSS
    Undeploy one or more previously deployed site(s) by specifying their site id.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] --hostname <hostname> [--hostname <hostname>]...
SSS
    Undeploy one or more previously deployed site(s) by specifying their hostname.
    This is equivalent to undeploying the site ids, but may be more convenient.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] --file <site.json>
SSS
    Undeploy one or more previously deployed site(s) whose site JSON
    file is given. This is equivalent to undeploying the site ids of the
    site(s) contained in the file.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] --all
SSS
    Undeploy all currently deployed site(s).
HHH
    };
}

1;
