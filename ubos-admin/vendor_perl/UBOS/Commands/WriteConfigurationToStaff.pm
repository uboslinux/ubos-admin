#!/usr/bin/perl
#
# Command that writes the device's current configuration to a
# UBOS staff device
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
    my $directory     = undef;
    my $device        = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'debug'        => \$debug,
            'directory=s'  => \$directory );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || ( $directory && @args ) || @args > 1 || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $directory ) {
        unless( -d $directory ) {
            fatal( 'Directory does not exist:', $directory );
        }
    } elsif( @args ) {
        $device = shift @args;
        debugAndSuspend( 'Check staff device', $device );
        $device = UBOS::StaffManager::checkStaffDevice( $device );
        unless( $device ) {
            fatal( $@ );
        }

    } else {
        debugAndSuspend( 'Guess staff device' );
        $device = UBOS::StaffManager::guessStaffDevice();
        unless( $device ) {
            fatal( 'Cannot determine UBOS staff device' );
        }
    }

    my $errors = 0;
    if( $directory ) {
        $errors += UBOS::StaffManager::saveCurrentConfiguration( $directory );

    } else {
        my $targetDir;
        $errors += UBOS::StaffManager::mountDevice( $device, \$targetDir );
        $errors += UBOS::StaffManager::saveCurrentConfiguration( $targetDir->dirname() );
        $errors += UBOS::StaffManager::unmountDevice( $device, $targetDir ); 
    }

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
            <<SSS => <<HHH,
    --directory <dir>
SSS
    Write to a directory instead.
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
