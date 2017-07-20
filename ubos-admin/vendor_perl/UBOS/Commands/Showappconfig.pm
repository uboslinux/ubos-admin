#!/usr/bin/perl
#
# Command that shows information about a currently deployed appconfigid.
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
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $json          = 0;
    my $brief         = 0;
    my $siteId;
    my $host;
    my $appConfigId;
    my $context;
    my $url;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'json'          => \$json,
            'brief'         => \$brief,
            'siteid=s'      => \$siteId,
            'hostname=s'    => \$host,
            'appconfigid=s' => \$appConfigId,
            'context=s'     => \$context,
            'url=s'         => \$url );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( $json && $brief )
        || ( $appConfigId && ( $siteId || $host || $context || $url ))
        || ( $siteId && $host )
        || ( $siteId && $url )
        || ( $host && $url )
        || ( !$appConfigId && !$context && !$url )
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $appConfig;
    if( $appConfigId ) {
        $appConfig = UBOS::Host::findAppConfigurationByPartialId( $appConfigId );
        unless( $appConfig ) {
            fatal( 'Cannot find a appconfiguration with appconfigid:', $appConfigId );
        }
    } else {
        # Can use the same code here for url vs. host+context
        if( $url && $url =~ m!^(https?://)?([-a-z0-9_.]+)(/.*)?$! ) {
            $host    = $2;
            $context = $3;
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
        'summary' => <<SSS,
    Show information about one AppConfiguration currently deployed on
    this device.
SSS
        'detail' => <<DDD,
    If invoked as root, more information may be shown than when invoked
    as a different user (e.g. credentials, keys, values for
    customization points marked as "private").
DDD
        'cmds' => {
            <<SSS => <<HHH,
    --appconfigid <appconfigid>
SSS
    Show information about the AppConfiguration with the provided
    <appconfigid>.
HHH
            <<SSS => <<HHH,
    --siteid <siteid> --context <context>
SSS
    Show information about the AppConfiguration at the site with
    site id <siteid> and context path <context>.
HHH
            <<SSS => <<HHH,
    --hostname <hostname> --context <context>
SSS
    Show information about the AppConfiguration at the site with
    hostname <hostname> and context path <context>.
HHH
            <<SSS => <<HHH
    --url <url>
SSS
    Show information about the AppConfiguration referred to by URL
    <url>.
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
    Only show the appconfigid.
HHH
        }
    };
}

1;
