#!/usr/bin/perl
#
# Command that shows information about a currently deployed site.
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

package IndieBox::Commands::Showsite;

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

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $json   = 0;
    my $siteId;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'json'     => \$json,
            'siteid=s' => \$siteId );

    if( !$parseOk || !$siteId || @args ) {
        fatal( 'Invalid invocation: showsite', @_, '(add --help for help)' );
    }

    my $site = IndieBox::Host::findSiteByPartialId( $siteId );
    
    unless( $site ) {
        fatal();
    }
		
    if( $json ) {
        IndieBox::Utils::writeJsonToStdout( $site->siteJson );

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
    [--json] --siteid <siteid>
SSS
    Show the site with siteid.
    --json: show it in JSON format
HHH
    };
}

1;
