#!/usr/bin/perl
#
# Command that writes the device's current configuration to a
# UBOS staff device
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

package UBOS::Commands::WriteConfigurationToStaff;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Logging;
use UBOS::StaffManager;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $device        = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'debug'        => \$debug );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args > 1 || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( @args ) {
        $device = shift @args;
        debugAndSuspend( 'Check staff device', $device );
        $device = UBOS::StaffManager::checkStaffDevice( $device );
        unless( -b $device ) {
            fatal( 'Not a valid UBOS staff device:', $device );
        }

    } else {
        debugAndSuspend( 'Guess staff device' );
        $device = UBOS::StaffManager::guessStaffDevice();
        unless( $device ) {
            fatal( 'Cannot determine UBOS staff device' );
        }
    }

    my $targetDir;
    my $errors = 0;
    
    $errors += UBOS::StaffManager::mountDevice( $device, \$targetDir );
    $errors += UBOS::StaffManager::saveCurrentConfiguration( $targetDir->dirname() );
    $errors += UBOS::StaffManager::unmountDevice( $device, $targetDir ); 

    return $errors ? 0 : 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Write the current device's configuration to a UBOS staff device.
SSS
        'cmds' => {
            '' => <<HHH,
    Guess which device is the UBOS staff device.
HHH
            <<SSS => <<HHH,
    <ubos-staff-device>
SSS
    Write to the provided UBOS staff device, such as /dev/sdc.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH
    Use an alternate log configuration file for this command.
HHH
        }
    };
}

1;
