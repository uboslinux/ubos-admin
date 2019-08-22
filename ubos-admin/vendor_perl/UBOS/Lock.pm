#!/usr/bin/perl
#
# Central administration script for UBOS administration
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

package UBOS::Lock;

use Fcntl ':flock';

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

1;

# mandatory line, flocking depends on DATA file handle
__DATA__
