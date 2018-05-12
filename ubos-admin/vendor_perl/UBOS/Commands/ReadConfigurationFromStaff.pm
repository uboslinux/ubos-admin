#!/usr/bin/perl
#
# Command that reads the device's desired configuration from
# a UBOS staff device
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::ReadConfigurationFromStaff;

use Cwd;
use File::Temp;
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
    my $dir           = undef;
    my $device        = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'directory=s' => \$dir,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args > 1 || ( @args && $dir ) || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $errors       = 0;
    my $staffRootDir = undef;

    if( $dir ) {
        unless( -d $dir ) {
            fatal( 'Directory does not exist:', $dir );
        }

    } else {
        if( @args ) {
            $device = shift @args;
            debugAndSuspend( 'Checking staff device', $device );
            $device = UBOS::StaffManager::checkStaffDevice( $device );
            unless( $device ) {
                fatal( $@ );
            }

        } else {
            debugAndSuspend( 'Guessing staff device' );
            $device = UBOS::StaffManager::guessStaffDevice();
            unless( $device ) {
                fatal( 'Cannot determine UBOS staff device' );
            }
        }
        trace( 'Staff device:', $device );

        $errors += UBOS::StaffManager::mountDevice( $device, \$staffRootDir );
        $dir     = $staffRootDir->dirname();
    }

    $errors += UBOS::StaffManager::loadCurrentConfiguration( $dir );

    if( $staffRootDir ) {
        $errors += UBOS::StaffManager::unmountDevice( $device, $staffRootDir );
    }

    return $errors ? 0 : 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Configure this device with information read from a UBOS staff device.
SSS
        'detail' => <<DDD,
    This command performs similar actions would be performed when the
    device is booted with a UBOS staff device attached.
DDD
        'cmds' => {
            '' => <<HHH,
    Guess which device is the UBOS staff device.
HHH
            <<SSS => <<HHH,
    <ubos-staff-device>
SSS
    Read from the provided UBOS staff device, such as /dev/sdc.
HHH
            <<SSS => <<HHH
    --directory <directory>
SSS
    Read from a directory that contains UBOS staff information instead.
    Mostly used for testing.
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
