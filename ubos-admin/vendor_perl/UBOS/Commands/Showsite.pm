#!/usr/bin/perl
#
# Command that shows information about a currently deployed site.
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

package UBOS::Commands::Showsite;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
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
    my $json          = 0;
    my $brief         = 0;
    my $siteId;
    my $host;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'json'        => \$json,
            'brief'       => \$brief,
            'siteid=s'    => \$siteId,
            'hostname=s'  => \$host );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || ( $json && $brief ) || ( !$siteId && !$host ) || ( $siteId && $host ) || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $site;
    if( $host ) {
        $site = UBOS::Host::findSiteByHostname( $host );
        unless( $site ) {
            fatal( 'Cannot find a site with hostname:', $host );
        }
    } else {
        $site = UBOS::Host::findSiteByPartialId( $siteId );
        unless( $site ) {
            fatal( $@ );
        }
    }

    if( $json ) {
        UBOS::Utils::writeJsonToStdout( $site->siteJson );

    } else { # human-readable, brief or not
        $site->print( $brief ? 1 : 2 );
    }
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--json | --brief] --siteid <siteid>
SSS
    Show the site with the provided siteid.
    If invoked as root, more information is available.
    --json: show it in JSON format
    --brief: only show the site id
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--json | --brief] --hostname <hostname>
SSS
    Show the site with the provided hostname.
    If invoked as root, more information is available.
    --json: show it in JSON format
    --brief: only show the site id
HHH
    };
}

1;
