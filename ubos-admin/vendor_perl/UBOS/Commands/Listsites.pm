#!/usr/bin/perl
#
# Command that lists the currently deployed sites.
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

package UBOS::Commands::Listsites;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::AnyBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $json          = 0;
    my $brief         = 0;
    my @siteIds       = ();
    my @hosts         = ();

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug,
            'json'        => \$json,
            'brief'       => \$brief,
            'siteid=s'    => \@siteIds,
            'hostname=s'  => \@hosts );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || ( $json && $brief ) || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $sites;
    if( @siteIds || @hosts ) {
        foreach my $siteId ( @siteIds ) {
            my $site = UBOS::Host::findSiteByPartialId( $siteId );
            if( $site ) {
                $sites->{$site->siteId} = $site;
            } else {
                fatal( $@ );
            }
        }
        foreach my $host ( @hosts ) {
            my $site = UBOS::Host::findSiteByHostname( $host );
            if( $site ) {
                $sites->{$site->siteId} = $site;
            } else {
                fatal( $@ );
            }
        }
    } else {
        $sites = UBOS::Host::sites();
    }

    if( $json ) {
        my $sitesJson = {};
        foreach my $siteId ( keys %$sites ) {
            $sitesJson->{$siteId} = $sites->{$siteId}->siteJson;
        }
        UBOS::Utils::writeJsonToStdout( $sitesJson );

    } else {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->print( $brief ? 1 : 2 );
        }
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show information about the sites currently deployed on this device.
SSS
        'detail' => <<DDD,
    If invoked as root, more information may be shown than when invoked
    as a different user (e.g. credentials, keys, values for
    customization points marked as "private").
DDD
        'cmds' => {
            '' => <<HHH,
    Show all sites.
HHH
            <<SSS => <<HHH,
    --siteid <siteid> [--siteid <siteid>]...
SSS
    Show only the the site or sites with site ids <siteid>.
HHH
            <<SSS => <<HHH
    --hostname <hostname> [--hostname <hostname>]...
SSS
    Show only the the site or sites with hostnames <hostname>.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--json' => <<HHH,
    Use JSON as the output format, instead of human-readable text.
HHH
            '--brief' => <<HHH
    Only show the siteids.
HHH
        }
    };
}

1;
