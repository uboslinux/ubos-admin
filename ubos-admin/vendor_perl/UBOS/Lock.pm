#!/usr/bin/perl
#
# Prevent multiple executions of this script in parallel, and
# related functionality.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

package UBOS::Lock;

use UBOS::Host;
use Fcntl ':flock';

my %NOINTERRUPTSIG = (
    'HUP'  => 'IGNORE',
    'INT'  => 'IGNORE',
    'QUIT' => 'IGNORE'
);
my %OLDSIG; # Store previous values of $SIG

#####
# Check that only one copy of the script is running at any time.
# return: if 1, everything is fine, the lock is acquired, please proceed
sub acquire {
    # See __DATA__ at end of file
    if( flock( DATA, LOCK_EX|LOCK_NB )) {
        return 1;
    } else {
        $@ = "Another copy of ubos-admin is running already. Please try again later.";
        return 0;
    }
}

#####
# Release the lock.
# return: success or failure
sub release {
    # See __DATA__ at end of file
    if( flock( DATA, LOCK_UN )) {
        return 1;
    } else {
        $@ = "Failed to release UBOS::Lock.";
        return 0;
    }
}

#####
# Prevent interruptions of this process
sub preventInterruptions {

    setpgrp(); # prevent signals from reaching sub-processes

    foreach $key ( keys %NOINTERRUPTSIG ) {
        $OLDSIG{$key} = $SIG{$key};
        $SIG{$key}    = $NOINTERRUPTSIG{$key};
    }

    UBOS::Host::setState( 'InMaintenance' );
}

#####
# Allow interruptions of this process again
sub allowInterruptions {

    foreach $key ( keys %NOINTERRUPTSIG ) {
        $SIG{$key} = $OLDSIG{$key};
    }
}

1;

# mandatory line, flocking depends on DATA file handle
__DATA__
