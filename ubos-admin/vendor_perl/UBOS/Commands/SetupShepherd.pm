#!/usr/bin/perl
#
# Command that creates/updates the shepherd account without the use of
# UBOS Staff.
#
# This file is part of ubos-admin.
# (C) 2012-2016 Indie Computing Corp.
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

package UBOS::Commands::SetupShepherd;

use Cwd;
use File::Temp;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::ConfigurationManager;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $device        = undef;
    my $add           = 0; # default is replace

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'add'         => \$add );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || ( $add && @args == 0 ) || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    foreach my $key ( @args ) {
        unless( $key =~ m!^ssh-\S+ \S+ \S+\@\S+$! ) {
            fatal( 'This does not look like a valid ssh public key. Perhaps you need to put it in quotes?:', $key );
        }
    }
    UBOS::ConfigurationManager::setupUpdateShepherd( $add, @args );

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [[--add] <public ssh key>] ...
SSS
    Create the shepherd account if it does not exist yet. Replace (or add,
    if --add is specified) the given public ssh key(s) on the shepherd account.
    This is a command-line mechanism similar to what can be done with the
    UBOS Staff.
HHH
    };
}

1;
