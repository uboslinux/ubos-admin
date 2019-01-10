#!/usr/bin/perl
#
# An AppConfiguration item that is a directory.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
# $role: the Role to which this item belongs to
# $appConfig: the AppConfiguration object that this item belongs to
# $installable: the Installable to which this item belongs to
# return: the created File object
sub new {
    my $self        = shift;
    my $json        = shift;
    my $role        = shift;
    my $appConfig   = shift;
    my $installable = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $json, $role, $appConfig, $installable );

    return $self;
}

##
# Install this item, or check that it is installable.
# $doIt: if 1, install; if 0, only check
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub deployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $ret   = 1;
    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }

    trace( 'Directory::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir, @$names );

    my $dirpermissions = $vars->replaceVariables( $self->{json}->{dirpermissions} || $self->{json}->{permissions} ); # upward compatible
    my $uname          = $vars->replaceVariables( $self->{json}->{uname} );
    my $gname          = $vars->replaceVariables( $self->{json}->{gname} );
    my $dirmode        = $self->permissionToMode( $dirpermissions, 0755 );

    foreach my $name ( @$names ) {
        my $fullName = $name;

        $fullName = $vars->replaceVariables( $fullName );

        unless( $fullName =~ m#^/# ) {
            $fullName = "$defaultToDir/$fullName";
        }

        if( $doIt ) {
            if( -e $fullName ) {
                error( 'Directory::deployOrCheck: exists already:', $fullName );
                # FIXME: chmod, chown

                $ret = 0;

            } elsif( UBOS::Utils::mkdir( $fullName, $dirmode, $uname, $gname ) != 1 ) {
                error( 'Directory::deployOrCheck: could not be created:', $fullName );
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
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub undeployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars         = shift;

    my $ret   = 1;
    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }

    trace( 'Directory::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir, @$names );

    foreach my $name ( reverse @$names ) {
        my $fullName = $name;

        $fullName = $vars->replaceVariables( $fullName );

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
# $vars: the Variables object that knows about symbolic names and variables
# $backupContext: the Backup Context object
# $filesToDelete: array of filenames of temporary files that need to be deleted after backup
# $compress: compression method to use, or undef
# return: success or fail
sub backup {
    my $self          = shift;
    my $dir           = shift;
    my $vars          = shift;
    my $backupContext = shift;
    my $filesToDelete = shift;
    my $compress      = shift;

    # Note: compress is currently not used; not sure it is useful here

    my $bucket = $self->{json}->{retentionbucket};
    my $names  = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }

    trace( 'Directory::backup', $bucket, @$names );

    if( @$names != 1 ) {
        error( 'Directory::backup: cannot backup item with more than one name:', @$names );
        return 0;
    }

    my $fullName = $vars->replaceVariables( $names->[0] );
    unless( $fullName =~ m#^/# ) {
        $fullName = "$dir/$fullName";
    }

    return $backupContext->addDirectoryHierarchy( $fullName, $bucket );
}

##
# Default implementation to restore this item from backup.
# $dir: the directory in which the app was installed
# $vars: the Variables object that knows about symbolic names and variables
# $backupContext: the Backup Context object
# return: success or fail
sub restore {
    my $self          = shift;
    my $dir           = shift;
    my $vars          = shift;
    my $backupContext = shift;

    my $bucket = $self->{json}->{retentionbucket};
    my $names  = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }

    trace( 'Directory::restore', $bucket, $names );

    if( @$names != 1 ) {
        error( 'Directory::restore: cannot restore item with more than one name:', @$names );
        return 0;
    }

    my $fullName = $vars->replaceVariables( $names->[0] );
    unless( $fullName =~ m#^/# ) {
        $fullName = "$dir/$fullName";
    }

    my $filepermissions = $vars->replaceVariables( $self->{json}->{filepermissions} );
    my $dirpermissions  = $vars->replaceVariables( $self->{json}->{dirpermissions} || $self->{json}->{permissions} ); # upward compatible
    my $uname           = $vars->replaceVariables( $self->{json}->{uname} );
    my $gname           = $vars->replaceVariables( $self->{json}->{gname} );
    my $uid             = UBOS::Utils::getUid( $uname );
    my $gid             = UBOS::Utils::getGid( $gname );
    my $filemode        = ( defined( $filepermissions ) && $filepermissions eq 'preserve' ) ? -1 : $self->permissionToMode( $filepermissions, 0644 );
    my $dirmode         = ( defined( $dirpermissions  ) && $dirpermissions  eq 'preserve' ) ? -1 : $self->permissionToMode( $dirpermissions, 0755 );

    my $ret = 1;
    unless( $backupContext->restoreRecursive( $bucket, $fullName )) {
        error( 'Cannot restore directory: bucket:', $bucket, 'fullName:', $fullName, 'context:', $backupContext->asString() );
        $ret = 0;
    }

    if( $filemode > -1 ) {
        my $asOct = sprintf( "%o", $filemode );
        UBOS::Utils::myexec( "find '$fullName' -type f -exec chmod $asOct {} \\;" ); # no -h on Linux
    }
    if( $dirmode > -1 ) {
        my $asOct = sprintf( "%o", $dirmode );
        UBOS::Utils::myexec( "find '$fullName' -type d -exec chmod $asOct {} \\;" ); # no -h on Linux
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
