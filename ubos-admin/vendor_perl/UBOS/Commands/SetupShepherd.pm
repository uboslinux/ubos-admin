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
    my $file          = undef;
    my $add           = 0;
    my $force         = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'    => \$verbose,
            'logConfig=s' => \$logConfigFile,
            'debug'       => \$debug,
            'file=s'      => \$file,
            'add-key'     => \$add,
            'force'       => \$force );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args > 1
        || ( $file  && @args )
        || ( !$file && @args == 0 )
        || ( $add && $force )
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $key;
    if( @args ) {
        $key = $args[0];
    } elsif( -r $file ) {
        $key = UBOS::Utils::slurpFile( $file );
    } else {
        fatal( 'File cannot be read or does not exist:', $file );
    }

    unless( $key =~ m!^ssh-\S+ ! ) {
        if( $file ) {
            fatal( 'This does not look like a valid ssh public key:', $key );
        } else {
            fatal( 'This does not look like a valid ssh public key. Perhaps you need to put it in quotes?:', $key );
        }
    }

    UBOS::StaffManager::setupUpdateShepherd( $key, $add, $force );

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
    This command creates the shepherd account if it does not exist yet,
    and optionally, adds or replaces a public ssh key on the shepherd
    account so key-based ssh login is possible over the network.
DDD
        'cmds' => {
            '' => <<HHH,
    When creating the shepherd account, do not set a public ssh key.
    If the shepherd account exists already, does nothing.
HHH
            <<SSS => <<HHH,
    [--force] <public ssh key>
SSS
    Set the given public ssh key on the shepherd account. If the shepherd
    account does not exist yet, create it first. This will overwrite an
    existing key, but only if --force is given.
HHH
            <<SSS => <<HHH,
    --add-key <public ssh key>
SSS
    Add the given public ssh key to the shepherd account. If a previous
    ssh key was already set, add this ssh key and do not replace the
    previous one. If the shepherd account does not exist yet, create it
    first.
HHH
            <<SSS => <<HHH,
    [--force] --file <keyfile>
SSS
    Set the public ssh key contained in <keyfile> on the shepherd account.
    If the shepherd account does not exist yet, create it first. This will
    overwrite an existing key, but only if --force is given.
HHH
            <<SSS => <<HHH
    --add-key --file <keyfile>
SSS
    Add the public ssh key contained in <keyfile> to the shepherd account.
    If a previous ssh key was already set, add this ssh key and do not
    replace the previous one. If the shepherd account does not exist yet,
    create it first.
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
