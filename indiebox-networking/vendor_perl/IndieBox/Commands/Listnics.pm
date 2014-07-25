#!/usr/bin/perl
#
# Command that lists the known network interfaces.
#
# This file is part of indiebox-networking.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-networking is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-networking is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-networking.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Commands::Listnics;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use IndieBox::Logging;
use IndieBox::Networking::NetConfigUtils;
use IndieBox::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    my $verbose   = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose' => \$verbose );

    my $nics = IndieBox::Networking::NetConfigUtils::getAllNics();

    my $print;
    if( $verbose ) {
		$print = sub {
			my $v   = shift;
			my $ret = $v->{type} . ' (';
			foreach my $att ( 'name', 'type', 'mac', 'atts', 'flags', 'brd') {
                my $val = $v->{$att};

			    if( defined( $val )) {
					if( $ret ) {
						$ret .= ' ';
					}
					$ret .= $att;
					$ret .= '=';
					
					if( ref( $val )) {
						$ret .= '(' . join( ', ', map { if( $val->{$_} eq 1 ) { $_; } else { "$_=" . $val->{$_}; } } keys %$val ) . ')';
					} elsif( $v->{$att} =~ m!\s! ) {
						$ret .= "'" . $v->{$att} . "'";
					} else {
						$ret .= $v->{$att};
					}
				}
		    }
			$ret .= ')';
			return $ret;
		};
   	} else {
        $print = sub {
			my $v = shift;
			return $v->{name} || $v->{type};
		};
	}
    IndieBox::Utils::printHashAsColumns( $nics, $print, 'IndieBox::Networking::NetConfigUtils::compareNics' );
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        '[--verbose]' => <<HHH
    Show known network interfaces.
HHH
    };
}

1;
