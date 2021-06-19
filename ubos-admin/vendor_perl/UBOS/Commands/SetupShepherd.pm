#!/usr/bin/perl
#
# Command that creates/updates the shepherd account without the use of
# UBOS Staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::SetupShepherd;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Lock;
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

    unless( UBOS::Lock::acquire() ) {
        colPrintError( "$@\n" );
        exit -2;
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $file          = undef;
    my $add           = 0;
    my $force         = 0;

    $SIG{__WARN__} = sub {}; # Suppress built-in error message when private key is submitted, as it will be interpreted as an option

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug,
            'file=s'      => \$file,
            'add-key'     => \$add,
            'force'       => \$force );

    $SIG{__WARN__} = undef;

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args
        || ( $add && $force )
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, '(add --help for help)' );
    }

    my $keys;
    if( $file ) {
        if( -r $file ) {
            $keys = UBOS::Utils::slurpFile( $file );
        } else {
            fatal( 'File cannot be read or does not exist:', $file );
        }
    } else {
        print( "Enter ssh key(s), followed by ^D.\n" );
        while( <STDIN> ) {
            $keys .= $_ . "\n";
        }
    }

    my $parsedKeysP = UBOS::StaffManager::parseAuthorizedKeys( $keys );
    unless( $parsedKeysP ) {
        fatal( $@ );
    }

    UBOS::StaffManager::setupUpdateShepherd( $parsedKeysP, $add, $force );

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Configure the shepherd account.
SSS
        'detail' => <<DDD,
    This command creates the shepherd account if it does not exist yet.
    It may also add or replace public ssh keys on the shepherd
    account so key-based ssh login is possible over the network.
DDD
        'cmds' => {
            <<SSS => <<HHH,
    [--force]
SSS
    Create the shepherd account if it does not exist yet. Read the public ssh
    key(s) for the authorized_keys file from stdin.
    --force will overwrite the existing keys if the account exists already.
HHH
            <<SSS => <<HHH,
    --add-key
SSS
    Create the shepherd account if it does not exist yet. Read additional
    public ssh key(s) for the authorized_keys file from stdin, which will be
    appended.
HHH
            <<SSS => <<HHH,
    [--force] --file <keyfile>
SSS
    Create the shepherd account if it does not exist yet. Read the public ssh
    key(s) for the authorized_keys file from the provided file.
    --force will overwrite the existing keys if the account exists already.
HHH
            <<SSS => <<HHH
    --add-key --file <keyfile>
SSS
    Create the shepherd account if it does not exist yet. Read additional
    public ssh key(s) for the authorized_keys file from the provided file, which
    will be appended.
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
