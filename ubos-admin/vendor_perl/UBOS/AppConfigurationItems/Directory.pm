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
# return: success or fail
sub installOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $ret   = 1;
    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }

    my $dirpermissions = $config->replaceVariables( $self->{json}->{dirpermissions} || $self->{json}->{permissions} ); # upward compatible
    my $uname          = $config->replaceVariables( $self->{json}->{uname} );
    my $gname          = $config->replaceVariables( $self->{json}->{gname} );
    my $dirmode        = $self->permissionToMode( $dirpermissions, 0755 );

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

                $ret = 0;

            } elsif( UBOS::Utils::mkdir( $fullName, $dirmode, $uname, $gname ) != 1 ) {
                error( 'Directory could not be created:', $fullName );
                $ret = 0;
            }
        }
    }
    return $ret;
}

##
# Uninstall this item, or check that it is uninstallable.
# $doIt: if 1, uninstall; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $config: the Configuration object that knows about symbolic names and variables
# return: success or fail
sub uninstallOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $ret   = 1;
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
            $ret &= UBOS::Utils::deleteRecursively( $fullName );
            # Delete recursively, in case there's more stuff in it than we put in.
            # If that stuff needs preserving, the retention should take care of that.
        }
    }
    return $ret;
}

##
# Back this item up.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $backupContext: the Backup Context object
# $filesToDelete: array of filenames of temporary files that need to be deleted after backup
# return: success or fail
sub backup {
    my $self          = shift;
    my $dir           = shift;
    my $config        = shift;
    my $backupContext = shift;
    my $filesToDelete = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    if( @$names != 1 ) {
        error( 'Cannot backup item with more than one name:', @$names );
        return 0;
    }

    my $fullName = $config->replaceVariables( $names->[0] );
    unless( $fullName =~ m#^/# ) {
        $fullName = "$dir/$fullName";
    }

    my $bucket = $self->{json}->{retentionbucket};

    return $backupContext->addDirectoryHierarchy( $fullName, $bucket );
}

##
# Default implementation to restore this item from backup.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $backupContext: the Backup Context object
# return: success or fail
sub restore {
    my $self          = shift;
    my $dir           = shift;
    my $config        = shift;
    my $backupContext = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    if( @$names != 1 ) {
        error( 'Cannot restore item with more than one name:', @$names );
        return 0;
    }

    my $fullName = $config->replaceVariables( $names->[0] );
    unless( $fullName =~ m#^/# ) {
        $fullName = "$dir/$fullName";
    }

    my $bucket = $self->{json}->{retentionbucket};

    my $filepermissions = $config->replaceVariables( $self->{json}->{filepermissions} );
    my $dirpermissions  = $config->replaceVariables( $self->{json}->{dirpermissions} || $self->{json}->{permissions} ); # upward compatible
    my $uname           = $config->replaceVariables( $self->{json}->{uname} );
    my $gname           = $config->replaceVariables( $self->{json}->{gname} );
    my $uid             = UBOS::Utils::getUid( $uname );
    my $gid             = UBOS::Utils::getGid( $gname );
    my $filemode        = ( defined( $filepermissions ) && $filepermissions eq 'preserve' ) ? -1 : $self->permissionToMode( $filepermissions, 0644 );
    my $dirmode         = ( defined( $dirpermissions  ) && $dirpermissions  eq 'preserve' ) ? -1 : $self->permissionToMode( $dirpermissions, 0755 );

    my $ret = $backupContext->restoreRecursive( $bucket, $fullName );

    if( $filemode > -1 ) {
        my $asOct = sprintf( "%o", $filemode );
        UBOS::Utils::myexec( "find '$fullName' -type f -exec chmod $asOct {}\;" ); # no -h on Linux
    }
    if( $dirmode > -1 ) {
        my $asOct = sprintf( "%o", $dirmode );
        UBOS::Utils::myexec( "find '$fullName' -type d -exec chmod $asOct {}\;" ); # no -h on Linux
    }

    if( defined( $uid )) {
        UBOS::Utils::myexec( 'chown -R -h ' . ( 0 + $uid ) . " $fullName" );
    }
    if( defined( $gid )) {
        UBOS::Utils::myexec( 'chgrp -R -h ' . ( 0 + $gid ) . " $fullName" );
    }
    return $ret;
}

1;

