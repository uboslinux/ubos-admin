#!/usr/bin/perl
#
# Abstract superclass for Backup contexts.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AbstractBackupContext;

use fields;

use UBOS::Logging;

##
# Callback by which an AppConfigurationItem can add a file to a Backup
# $fileToAdd: the name of the file to add in the file system
# $bucket: the name of the bucket to which the file shall be added
# return: success or fail
sub addFile {
    my $self      = shift;
    my $fileToAdd = shift;
    my $bucket    = shift;

    error( 'Cannot perform addFile on', $self );

    return 0;
}

##
# Callback by which an AppConfigurationItem can add a directory hierarchy to a Backup
# $dirToAdd: the name of the directory to add in the file system
# $bucket: the name of the bucket to which the directory hierarchy shall be added
# return: success or fail
sub addDirectoryHierarchy {
    my $self     = shift;
    my $dirToAdd = shift;
    my $bucket   = shift;

    error( 'Cannot perform addDirectoryHierarchy on', $self );

    return 0;
}

##
# Callback by which an AppConfigurationItem can restore a file from a Backup
# $bucket: the name of the bucket from which the file is to be restored
# return: name of the file
sub restore {
    my $self     = shift;
    my $bucket   = shift;

    error( 'Cannot perform restore on', $self );

    return undef;
}


##
# Helper method to restore a directory hierarchy from a Backup
# $bucket: the name of the bucket from which the directory hierarchy is to be restored
# $dirName: name of the director in the filesystem to be written
# return: success or fail
sub restoreRecursive {
    my $self    = shift;
    my $bucket  = shift;
    my $dirName = shift;

    error( 'Cannot restoreRecursive extract on', $self );

    return 0;
}

1;
