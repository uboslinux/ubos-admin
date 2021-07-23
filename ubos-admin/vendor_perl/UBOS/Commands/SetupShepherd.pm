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
    my $addKey        = 0;
    my $noKey         = 0;
    my $force         = 0;

    $SIG{__WARN__} = sub {}; # Suppress built-in error message when private key is submitted, as it will be interpreted as an option

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug,
            'file=s'      => \$file,
            'add-key'     => \$addKey,
            'no-key'      => \$noKey,
            'force'       => \$force );

    $SIG{__WARN__} = undef;

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args
        || ( $addKey && $force )
        || ( $noKey && $addKey )
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

    } elsif( $noKey ) {
        $keys = undef;

    } else {
        print( "Enter ssh key(s), followed by ^D.\n" );
        while( <STDIN> ) {
            $keys .= $_ . "\n";
        }
    }

    my $parsedKeysP;
    if( $noKey ) {
        $parsedKeysP = undef;

    } else {
        $parsedKeysP = UBOS::StaffManager::parseAuthorizedKeys( $keys );
        unless( $parsedKeysP ) {
            fatal( $@ );
        }
    }

    UBOS::StaffManager::setupUpdateShepherd( $parsedKeysP, $addKey, $force );

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
    Creates and sets up the shepherd account to make ssh login possible
    over the network.
DDD
        'cmds' => {
            <<SSS => <<HHH,
    [--force]
SSS
    Create the shepherd account. Read the public ssh key(s) for the
    authorized_keys file from stdin. If the account exists already,
    --force will overwrite the existing keys.
HHH
            <<SSS => <<HHH,
    --add-key
SSS
    Add additional public ssh key(s) for the authorized_keys file by reading
    from stdin. They will be appended to the existing authorized_keys.
    If the shepherd account does not exist yet, create it.
HHH
            <<SSS => <<HHH,
    [--force] --file <keyfile>
SSS
    Create the shepherd account. Read the public ssh key(s) for the
    authorized_keys file from <keyfile>. If the account exists already.
    --force will overwrite the existing keys.
HHH
            <<SSS => <<HHH,
    --add-key --file <keyfile>
SSS
    Add additional public ssh key(s) for the authorized_keys file by reading
    from <keyfile>. They will be appended to the existing authorized_keys.
    If the shepherd account does not exist yet, create it.
HHH
            <<SSS => <<HHH
    [--force] --no-key
SSS
    Create the shepherd account, but do not ask for or add any public
    keys. If the account exists already, --force will remove the existing
    keys.
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
