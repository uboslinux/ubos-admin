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
    my $json          = 0;
    my $brief         = 0;
    my @siteIds       = ();

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'json'        => \$json,
            'brief'       => \$brief,
            'siteid=s'    => \@siteIds );

    UBOS::Logging::initialize( 'ubos-admin', 'listsites', $verbose, $logConfigFile );

    if( !$parseOk || ( $json && $brief ) || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation: listsites', @_, '(add --help for help)' );
    }

    if( $json ) {
        my $sitesJson = {};
        if( @siteIds ) {
            foreach my $siteId ( @siteIds ) {
                my $site = UBOS::Host::findSiteByPartialId( $siteId );
                if( $site ) {
                    $sitesJson->{$site->siteId} = $site->siteJson;
                } else {
                    fatal();
                }
            }
        } else {
            my $sites = UBOS::Host::sites();
            foreach my $site ( values %$sites ) {
                $sitesJson->{$site->siteId} = $site->siteJson;
            }
        }
        UBOS::Utils::writeJsonToStdout( $sitesJson );

    } else { # human-readable, brief or not
        if( @siteIds ) {
            foreach my $siteId ( @siteIds ) {
                my $site = UBOS::Host::findSiteByPartialId( $siteId );
                if( $site ) {
                    $site->print( $brief ? 1 : 2 );
                } else {
                    fatal();
                }
            }
        } else {
            my $sites = UBOS::Host::sites();
            foreach my $site ( values %$sites ) {
                $site->print( $brief ? 1 : 2 );
            }
        }
    }
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--json | --brief] [--verbose | --logConfig <file>] [--siteid <siteid>]...
SSS
    Show the sites with siteid, or if not given, show all sites currently
    deployed to this device.
    --json: show them in JSON format
    --brief: only show the site ids.
HHH
    };
}

1;
