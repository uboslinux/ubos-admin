#!/usr/bin/perl
#
# Command that shows information about a currently deployed appconfigid.
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

package UBOS::Commands::Showappconfig;

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

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $json          = 0;
    my $brief         = 0;
    my $siteId;
    my $host;
    my $appConfigId;
    my $context;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'json'          => \$json,
            'brief'         => \$brief,
            'siteid=s'      => \$siteId,
            'hostname=s'    => \$host,
            'appconfigid=s' => \$appConfigId,
            'context=s'     => \$context );

    UBOS::Logging::initialize( 'ubos-admin', 'showappconfig', $verbose, $logConfigFile );

    if(    !$parseOk
        || ( $json && $brief )
        || ( $appConfigId && ( $siteId || $host || $context ))
        || ( !$appConfigId && ( !$context || ( $siteId && $host )))
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation: showappconfig', @_, '(add --help for help)' );
    }

    my $appConfig;
    if( $appConfigId ) {
        $appConfig = UBOS::Host::findAppConfigurationByPartialId( $appConfigId );
        unless( $appConfig ) {
            fatal( 'Cannot find a appconfiguration with appconfigid:', $appConfigId );
        }
    } else {
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
        $appConfig = $site->appConfigAtContext( $context );
        unless( $appConfig ) {
            if( $context ) {
                fatal( 'Cannot find an appconfiguration at context path', $context );
            } else {
                fatal( 'Cannot find an appconfiguration at root context' );
            }
        }
    }

    if( $json ) {
        UBOS::Utils::writeJsonToStdout( $appConfig->appConfigurationJson );

    } else { # human-readable, brief or not
        $appConfig->print( $brief ? 1 : 2 );
    }
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--json | --brief] --appconfigid <appconfigid>
SSS
    Show the appconfiguration with the provided appconfigid.
    If invoked as root, more information is available.
    --json: show it in JSON format
    --brief: only show the appconfig id
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--json | --brief] --siteid <siteid> --context <context>
SSS
    Show the appconfiguration at the site with siteid with the provided context path.
    If invoked as root, more information is available.
    --json: show it in JSON format
    --brief: only show the appconfig id
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--json | --brief] --hostname <hostname> --context <context>
SSS
    Show the appconfiguration at the provided hostname with the provided context path.
    If invoked as root, more information is available.
    --json: show it in JSON format
    --brief: only show the appconfig id
HHH
    };
}

1;
