#!/usr/bin/perl
#
# Command that writes the device's current configuration to a
# configuration device, called the UBOS staff
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

package UBOS::Commands::WriteConfigurationToStaff;

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

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args > 1 || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( @args ) {
        $device = shift @args;
        $device = UBOS::ConfigurationManager::checkConfigurationDevice( $device );
        unless( -b $device ) {
            fatal( 'Not a valid UBOS staff device:', $device );
        }
        
    } else {
        $device = UBOS::ConfigurationManager::guessConfigurationDevice();
        unless( $device ) {
            fatal( 'Cannot determine UBOS staff device' );
        }
    }

    my $targetFile = File::Temp->newdir( DIR => getcwd(), UNLINK => 1 );
    my $target     = $targetFile->dirname;
    my $errors     = 0;

    if( UBOS::Utils::myexec( "mount -t vfat '$device' '$target'" )) {
        ++$errors;
    }

    $errors += UBOS::ConfigurationManager::saveCurrentConfiguration( $target );

    if( UBOS::Utils::myexec( "umount '$target'" )) {
        ++$errors;
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [ <ubos-staff-device> ]
SSS
    Write the current device's configuration to a UBOS staff device. If no
    drive block device is given, guess the device.
HHH
    };
}

1;
