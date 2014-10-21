#!/usr/bin/perl
#
# A Backup Context for UpdateBackups
#
# This file is part of ubos-admin.
# (C) 2012-2014 Indie Computing Corp.
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

package UBOS::UpdateBackupContext;

use base qw( UBOS::AbstractBackupContext );
use fields qw( backup contextPathInBackup );

use UBOS::Logging;

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
    $self->{contextPathInBackup} = $contextPathInBackup;

    return $self;
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

    # keep attributes, and don't follow symlinks
    if( UBOS::Utils::myexec( "cp -pP '$fileToAdd' '" . $self->{contextPathInBackup} . "/$bucket'" )) {
        return 0;
    }

    return 1;
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

    UBOS::Utils::mkdir( $self->{contextPathInBackup} . "/$bucket", 0700 );
    
    unless( opendir( DIR, $dirToAdd )) {
        error( $! );
        return 0;
    }

    my $ret = 1;
    while( my $file = readdir( DIR )) {
        if( $file =~ m!^\.\.?$! ) { # skip . and .. but not other .something files
            next;
        }
        $ret &= move( "$dirToAdd/$file", $self->{contextPathInBackup} . "/$bucket/$file" );        
    }
    closedir( DIR );

    return $ret;
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

    # keep attributes, and don't follow symlinks
    if( UBOS::Utils::myexec( "mv '" . $self->{contextPathInBackup} . "/$bucket' '$fileName'" )) {
        return 0;
    }

    return 1;
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

    unless( opendir( DIR, $self->{contextPathInBackup} . "/$bucket" )) {
        error( $! );
        return 0;
    }

    my $ret = 1;
    while( my $file = readdir( DIR )) {
        if( $file =~ m!^\.\.?$! ) { # skip . and .. but not other .something files
            next;
        }
        $ret &= move( $self->{contextPathInBackup} . "/$bucket/$file", "$dirName/$file",  );        
    }
    closedir( DIR );

    $ret &= UBOS::Utils::deleteRecursively( $self->{contextPathInBackup} . "/$bucket" );

    return $ret;
}

##
# Private implementation of 'move'. File::Copy has a move method, but it
# seems to fail moving entire directory hierarchies across file systems,
# which is something we try to avoid but can happen.
# $from: source file or directory
# $to: destination file or directory
sub move {
    my $from = shift;
    my $to   = shift;

    if( $from =~ m!['\\]! ) {
        error( 'move from contains dangerous character, will likely fail', $from );
    }
    if( $to =~ m!['\\]! ) {
        error( 'move to contains dangerous character, will likely fail', $to );
    }

    my $exit = UBOS::Utils::myexec( "mv '$from' '$to'" );
    if( $exit ) {
        error( 'move failed:', $from, $to );
        return 0;
    }
    return 1;
}

1;
