#!/usr/bin/perl
#
# Command that shows information about a currently deployed site.
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
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $json          = 0;
    my $siteId;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'json'        => \$json,
            'siteid=s'    => \$siteId );

    UBOS::Logging::initialize( 'ubos-admin', 'showsite', $verbose, $logConfigFile );

    if( !$parseOk || !$siteId || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation: showsite', @_, '(add --help for help)' );
    }

    my $site = UBOS::Host::findSiteByPartialId( $siteId );
    unless( $site ) {
        fatal( $@ );
    }
		
    if( $json ) {
        UBOS::Utils::writeJsonToStdout( $site->siteJson );

    } else { # human-readable, brief or not
        $site->print();
    }
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--json] --siteid <siteid>
SSS
    Show the site with siteid.
    --json: show it in JSON format
HHH
    };
}

1;
