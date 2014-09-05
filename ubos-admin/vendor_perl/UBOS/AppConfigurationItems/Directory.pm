#!/usr/bin/perl
#
# An AppConfiguration item that is a directory.
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

package UBOS::AppConfigurationItems::Directory;

use base qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields;

use UBOS::Logging;

##
# Constructor
# $json: the JSON fragment from the manifest JSON
# $appConfig: the AppConfiguration object that this item belongs to
# $installable: the Installable to which this item belongs to
# return: the created File object
sub new {
    my $self        = shift;
    my $json        = shift;
    my $appConfig   = shift;
    my $installable = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $json, $appConfig, $installable );

    return $self;
}

##
# Install this item, or check that it is installable.
# $doIt: if 1, install; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $config: the Configuration object that knows about symbolic names and variables
sub installOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }

    my $permissions = $config->replaceVariables( $self->{json}->{permissions} );
    my $uname       = $config->replaceVariables( $self->{json}->{uname} );
    my $gname       = $config->replaceVariables( $self->{json}->{gname} );
    my $mode        = $self->permissionToMode( $permissions, 0755 );

    foreach my $name ( @$names ) {
        my $fullName = $name;

        $fullName = $config->replaceVariables( $fullName );

        unless( $fullName =~ m#^/# ) {
            $fullName = "$defaultToDir/$fullName";
        }

        if( $doIt ) {
            if( -e $fullName ) {
                error( 'Directory exists already:', $fullName );
                # FIXME: chmod, chown

            } elsif( UBOS::Utils::mkdir( $fullName, $mode, $uname, $gname ) != 1 ) {
                error( 'Directory could not be created:', $fullName );
            }
        }
    }
}

##
# Uninstall this item, or check that it is uninstallable.
# $doIt: if 1, uninstall; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $config: the Configuration object that knows about symbolic names and variables
sub uninstallOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }

    foreach my $name ( reverse @$names ) {
        my $fullName = $name;

        $fullName = $config->replaceVariables( $fullName );

        unless( $fullName =~ m#^/# ) {
            $fullName = "$defaultToDir/$fullName";
        }
        if( $doIt ) {
            UBOS::Utils::deleteRecursively( $fullName );
            # Delete recursively, in case there's more stuff in it than we put in.
            # If that stuff needs preserving, the retentionpolicy should take care of that.
        }
    }
}

##
# Back this item up.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $zip: the ZIP object
# $contextPathInZip: the directory, in the ZIP file, into which this item will be backed up
# $filesToDelete: array of filenames of temporary files that need to be deleted after backup
sub backup {
    my $self             = shift;
    my $dir              = shift;
    my $config           = shift;
    my $zip              = shift;
    my $contextPathInZip = shift;
    my $filesToDelete    = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    if( @$names != 1 ) {
        error( 'Cannot backup item with more than one name:', @$names );
    }

    my $fullName = $config->replaceVariables( $names->[0] );
    unless( $fullName =~ m#^/# ) {
        $fullName = "$dir/$fullName";
    }

    my $bucket = $self->{json}->{retentionbucket};

    $self->_addRecursive( $zip, $fullName, "$contextPathInZip/$bucket" );
}

##
# Default implementation to restore this item from backup.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $zip: the ZIP object
# $contextPathInZip: the directory, in the ZIP file, into which this item will be backed up
sub restore {
    my $self             = shift;
    my $dir              = shift;
    my $config           = shift;
    my $zip              = shift;
    my $contextPathInZip = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    if( @$names != 1 ) {
        error( 'Cannot restore item with more than one name:', @$names );
    }

    my $fullName = $config->replaceVariables( $names->[0] );
    unless( $fullName =~ m#^/# ) {
        $fullName = "$dir/$fullName";
    }

    my $bucket = $self->{json}->{retentionbucket};

    my $permissions = $config->replaceVariables( $self->{json}->{permissions} );
    my $uname       = $config->replaceVariables( $self->{json}->{uname} );
    my $gname       = $config->replaceVariables( $self->{json}->{gname} );
    my $mode        = $self->permissionToMode( $permissions, 0755 );

    my $uid = UBOS::Utils::getUid( $uname );
    my $gid = UBOS::Utils::getGid( $gname );

    # Contrary to the docs, Archive::Zip seems to restore ../foobar if
    # argument ../foo is given, so we need to append a slash
    $self->_restoreRecursive( $zip, "$contextPathInZip/$bucket/", "$fullName/", $mode, $uid, $gid );
}

1;

