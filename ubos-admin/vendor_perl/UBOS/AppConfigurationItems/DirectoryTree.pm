#!/usr/bin/perl
#
# An AppConfiguration item that is a directory tree.
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

package UBOS::AppConfigurationItems::DirectoryTree;

use base qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields;

use File::Find;
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

    my $source = $self->{json}->{source};
    my $filepermissions = $config->replaceVariables( $self->{json}->{filepermissions} );
    my $dirpermissions  = $config->replaceVariables( $self->{json}->{dirpermissions} );
    my $uname           = $config->replaceVariables( $self->{json}->{uname} );
    my $gname           = $config->replaceVariables( $self->{json}->{gname} );
    my $uid             = UBOS::Utils::getUid( $uname );
    my $gid             = UBOS::Utils::getGid( $gname );
    my $filemode        = ( defined( $filepermissions ) && $filepermissions eq 'preserve' ) ? -1 : $self->permissionToMode( $filepermissions, 0644 );
    my $dirmode         = ( defined( $dirpermissions  ) && $dirpermissions  eq 'preserve' ) ? -1 : $self->permissionToMode( $dirpermissions, 0755 );

    foreach my $name ( @$names ) {
        my $localName  = $name;
        $localName =~ s!^.+/!!;

        my $fromName = $source;
        $fromName =~ s!\$1!$name!g;      # $1: name
        $fromName =~ s!\$2!$localName!g; # $2: just the name without directories
        $fromName = $config->replaceVariables( $fromName );

        my $toName = $name;
        $toName = $config->replaceVariables( $toName );

        unless( $fromName =~ m#^/# ) {
            $fromName = "$defaultFromDir/$fromName";
        }
        unless( $toName =~ m#^/# ) {
            $toName = "$defaultToDir/$toName";
        }

        if( $doIt ) {
            UBOS::Utils::copyRecursively( $fromName, $toName );

            if( $uid || $gid || ( defined( $filemode ) && $filemode != -1 ) || ( defined( $dirmode ) && $dirmode != -1 )) {
                find(   sub {
                            if( $uid || $gid ) {
                                chown $uid, $gid, $File::Find::name;
                            }
                            if( -d $File::Find::name ) {
                                if( defined( $dirmode ) && $dirmode != -1 ) {
                                    chmod $dirmode, $File::Find::name;
                                }
                            } else {
                                if( defined( $filemode ) && $filemode != -1 ) {
                                    chmod $filemode, $File::Find::name;
                                }
                            }
                        },
                        $toName );
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
        my $toName = $name;

        $toName = $config->replaceVariables( $toName );

        unless( $toName =~ m#^/# ) {
            $toName = "$defaultToDir/$toName";
        }
        if( $doIt ) {
            UBOS::Utils::deleteRecursively( $toName );
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
        fatal( 'Cannot restore item with more than one name:', @$names );
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
