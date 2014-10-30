#!/usr/bin/perl
#
# A Backup Context for ZipFileBackups
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

package UBOS::Backup::ZipFileBackupContext;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );

use base qw( UBOS::AbstractBackupContext );
use fields qw( backup contextPathInBackup );

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
# Callback by which an AppConfigurationItem can add a file to a Backup
# $fileToAdd: the name of the file to add in the file system
# $bucket: the name of the bucket to which the file shall be added
# return: success or fail
sub addFile {
    my $self      = shift;
    my $fileToAdd = shift;
    my $bucket    = shift;

    if( $self->{backup}->{zip}->addFile( $fileToAdd, $self->{contextPathInBackup} . $bucket )) {
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

    my $member = $self->{backup}->{zip}->memberNamed( $self->{contextPathInBackup} . $bucket );
    unless( $member ) {
        return 0;
    }
    if( $self->{backup}->{zip}->extractMember( $member, $fileName )) {
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
        $ret &= ( $self->{backup}->{zip}->addFile( $fileName, $zipName ) ? 1 : 0 );

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
        # Probably not worth settin $ret = 0 -- could be a socket
    }

    return $ret;
}

1;
