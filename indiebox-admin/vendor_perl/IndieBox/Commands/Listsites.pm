#!/usr/bin/perl
#
# Command that lists the currently deployed sites.
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

package IndieBox::Commands::Listsites;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use IndieBox::Host;
use IndieBox::Logging;
use IndieBox::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    my $json    = 0;
    my $brief   = 0;
    my @siteIds = ();

    my $parseOk = GetOptionsFromArray(
            \@args,
            'json'     => \$json,
            'brief'    => \$brief,
            'siteid=s' => \@siteIds );

    if( !$parseOk || ( $json && $brief ) || @args ) {
        fatal( 'Invalid command-line arguments, add --help for help' );
    }

    if( $json ) {
        my $sitesJson = {};
        if( @siteIds ) {
            foreach my $siteId ( @siteIds ) {
                my $site = IndieBox::Host::findSiteByPartialId( $siteId );
                if( $site ) {
                    $sitesJson->{$site->siteId} = $site->siteJson;
                } else {
                    fatal();
                }
            }
        } else {
            my $sites = IndieBox::Host::sites();
            foreach my $site ( values %$sites ) {
                $sitesJson->{$site->siteId} = $site->siteJson;
            }
        }
        IndieBox::Utils::writeJsonToStdout( $sitesJson );

    } else { # human-readable, brief or not
        if( @siteIds ) {
            foreach my $siteId ( @siteIds ) {
                my $site = IndieBox::Host::findSiteByPartialId( $siteId );
                if( $site ) {
                    $site->print( $brief ? 1 : 2 );
                } else {
                    fatal();
                }
            }
        } else {
            my $sites = IndieBox::Host::sites();
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
    [--json | --brief] [--siteid <siteid>]...
SSS
    Show the sites with siteid, or if not given, show all sites currently
    deployed to this device.
    --json: show them in JSON format
    --brief: only show the site ids.
HHH
    };
}

1;
