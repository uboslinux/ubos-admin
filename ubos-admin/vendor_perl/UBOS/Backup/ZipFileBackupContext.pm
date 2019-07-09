#!/usr/bin/perl
#
# A Backup Context for ZipFileBackups
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Backup::ZipFileBackupContext;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use UBOS::Logging;

use base qw( UBOS::AbstractBackupContext );
use fields qw( backup contextPathInBackup );

my %dontCompressExtensions = (
    # already compressed images
    'png'   => 1,
    'gif'   => 1,
    'jpg'   => 1,

    # already compressed audio and video
    'mp3'   => 1,
    'mpeg'  => 1,
    'ogg'   => 1,
    'm4a'   => 1,
    'm4p'   => 1,
    'm4v'   => 1,
    # not wav

    # other compressed files
    'pdf'   => 1,
    'ipa'   => 1, # iOS app

    # archive files
    'bz'    => 1,
    'bz2'   => 1,
    'bzip'  => 1,
    'bzip2' => 1,
    'gz'    => 1,
    'gzip'  => 1,
    'rar'   => 1,
    'tgj'   => 1,
    'tgz'   => 1,
    'xz'    => 1,
    'z'     => 1,
    'zip'   => 1,
);

##
# Constructor
sub new {
    my $self                = shift;
    my $backup              = shift;
    my $contextPathInBackup = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->{backup}              = $backup;
    $self->{contextPathInBackup} = "$contextPathInBackup/"; # add it here, that makes it faster

    return $self;
}

##
# Obtain printable representation, for error messages.
# return: string
sub asString {
    my $self = shift;

    return "backup entry " . $self->{contextPathInBackup};
}

##
# Callback by which an AppConfigurationItem can add a file to a Backup
# $fileToAdd: the name of the file to add in the file system
# $bucket: the name of the bucket to which the file shall be added
# return: success or fail
sub addFile {
    my $self      = shift;
    my $fileToAdd = shift;
    my $bucket    = shift;

    trace( 'ZipFileBackupContext::addFile', $fileToAdd, $bucket );

    if( ref( $fileToAdd ) || ref( $bucket )) {
        error( 'Invalid data type for addFile', ref( $fileToAdd ) || $fileToAdd, ref( $bucket ) || $bucket );
        return 0;
    }
    my $zipName = $self->{contextPathInBackup} . $bucket;

    # Use the extension of the actual file here, not the bucket name (which probably has no extension)
    if( $self->{backup}->{zip}->addFile( $fileToAdd, $zipName, _compressionLevel( $fileToAdd ))) {
        return 1;
    }
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

    trace( 'ZipFileBackupContext::addDirectoryHierarchy', $dirToAdd, $bucket );

    return $self->_addRecursive( $dirToAdd, $self->{contextPathInBackup} . $bucket );
}

##
# Callback by which an AppConfigurationItem can restore a file from a Backup
# $bucket: the name of the bucket from which the file is to be restored
# $fileName: name of the file in the filesystem to be written
# return: success or fail
sub restore {
    my $self     = shift;
    my $bucket   = shift;
    my $fileName = shift;

    trace( 'ZipFileBackupContext::restore', $bucket, $fileName, $self->{contextPathInBackup} );

    my $member = $self->{backup}->{zip}->memberNamed( $self->{contextPathInBackup} . $bucket );
    unless( $member ) {
        return undef;
    }

    if( $self->{backup}->{zip}->extractMember( $member, $fileName ) == AZ_OK ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Helper method to restore a directory hierarchy from a Backup
# $bucket: the name of the bucket from which the directory hierarchy is to be restored
# $dirName: name of the directory in the filesystem to be written
# return: success or fail
sub restoreRecursive {
    my $self    = shift;
    my $bucket  = shift;
    my $dirName = shift;

    trace( 'ZipFileBackupContext::restoreRecursive', $bucket, $dirName, $self->{contextPathInBackup} );

    # Contrary to the docs, trailing slashes are required, otherwise
    # restoring /foo will also restore /foobar
    if( $self->{backup}->{zip}->extractTree( $self->{contextPathInBackup} . $bucket . '/', $dirName . '/' )) {
        return 0;
    }
    return 1;
}

##
# Recursive helper method to add a directory hierarchy to a zip file
# $fileName: the name of the object in the filesystem
# $zipName: the name of the object in the zip file
# return: success or fail
sub _addRecursive {
    my $self     = shift;
    my $fileName = shift;
    my $zipName  = shift;

    my $ret = 1;
    if( -l $fileName ) {
        my $member = $self->{backup}->{zip}->addString( readlink $fileName, $zipName );
        $member->{'externalFileAttributes'} = 0xA1FF0000;
        # This comes from the source code of Archive::Zip; there doesn't seem to be an API

    } elsif( -f $fileName ) {
        $ret &= ( $self->{backup}->{zip}->addFile( $fileName, $zipName, _compressionLevel( $zipName )) ? 1 : 0 );

    } elsif( -d $fileName ) {
        $ret &= ( $self->{backup}->{zip}->addDirectory( "$fileName/", "$zipName/" ) ? 1 : 0 );

        my @children = ();
        if( opendir( DIR, $fileName )) {
            while( my $file = readdir( DIR )) {
                if( $file =~ m!^\.\.?$! ) { # skip . and .. but not other .something files
                    next;
                }
                push @children, "$fileName/$file";
            }
            closedir( DIR );

            foreach my $child ( @children ) {
                my $relative = $child;
                $relative = substr( $relative, length( $fileName ) + 1 );

                $ret &= ( $self->_addRecursive( $child, "$zipName/$relative" ) ? 1 : 0 );
            }
        } else {
            error( 'Could not read directory', $fileName, $! );
            $ret = 0;
        }

    } else {
        warning( 'Not a file or directory. Backup skipping:', $fileName, 'not a file or directory.' );
        # Probably not worth setting $ret = 0 -- could be a socket
    }

    return $ret;
}

##
# Determine the correct compression level for a file with this name
# $name: name of the file
# return: compression level
sub _compressionLevel {
    my $name = shift;

    my $lastPeriod = rindex( $name, '.' );
    if( $lastPeriod ) {
        my $ext = substr( $name, $lastPeriod+1 );
        if( $dontCompressExtensions{$ext} ) {
            return COMPRESSION_LEVEL_NONE;
        }
    }
    return COMPRESSION_LEVEL_DEFAULT;
}

1;
