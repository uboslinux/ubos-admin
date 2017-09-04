#!/usr/bin/perl
#
# An AppConfiguration item that is a file.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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

package UBOS::AppConfigurationItems::File;

use base qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields;

use UBOS::Logging;
use UBOS::Utils qw( saveFile slurpFile );

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
# $config: the Configuration object that knows about symbolic names and variables
# return: success or fail
sub deployOrCheck {
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

    my $sourceOrTemplate = $self->{json}->{template};
    unless( $sourceOrTemplate ) {
        $sourceOrTemplate = $self->{json}->{source};
    }

    trace( 'File::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $sourceOrTemplate, @$names );

    my $templateLang = $self->{json}->{templatelang};
    my $permissions  = $config->replaceVariables( $self->{json}->{permissions} );
    my $uname        = $config->replaceVariables( $self->{json}->{uname} );
    my $gname        = $config->replaceVariables( $self->{json}->{gname} );
    my $mode         = $self->permissionToMode( $permissions, 0644 );

    foreach my $name ( @$names ) {
        my $localName  = $name;
        $localName =~ s!^.+/!!;

        my $fromName = $sourceOrTemplate;
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
        if( -r $fromName ) {
            my $content           = slurpFile( $fromName );
            my $templateProcessor = $self->_instantiateTemplateProcessor( $templateLang );

            my $contentToSave = $templateProcessor->process( $content, $config, $sourceOrTemplate );

            if( $doIt ) {
                unless( saveFile( $toName, $contentToSave, $mode, $uname, $gname )) {
                    error( 'File::deployOrCheck: writing file failed:', $toName );
                    $ret = 0;
                }
            }

        } else {
            error( 'File::deployOrCheck: does not exist:', $fromName );
            $ret = 0;
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
sub undeployOrCheck {
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

    trace( 'File::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir, @$names );

    foreach my $name ( reverse @$names ) {
        my $toName = $name;
        $toName = $config->replaceVariables( $toName );

        unless( $toName =~ m#^/# ) {
            $toName = "$defaultToDir/$toName";
        }
        if( $doIt ) {
            $ret &= UBOS::Utils::deleteFile( $toName );
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

    my $bucket = $self->{json}->{retentionbucket};
    my $names  = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    trace( 'File::backup', $bucket, @$names );

    if( @$names != 1 ) {
        error( 'File::backup: cannot backup item with more than one name:', @$names );
        return 0;
    }

    my $toName = $names->[0];
    $toName = $config->replaceVariables( $toName );
    unless( $toName =~ m#^/# ) {
        $toName = "$dir/$toName";
    }

    return $backupContext->addFile( $toName, $bucket );
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

    my $bucket = $self->{json}->{retentionbucket};
    my $names  = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    trace( 'File::restore', $bucket, $names );

    if( @$names != 1 ) {
        error( 'File::restore: cannot restore item with more than one name:', @$names );
        return 0;
    }

    my $toName = $names->[0];
    $toName = $config->replaceVariables( $toName );
    unless( $toName =~ m#^/# ) {
        $toName = "$dir/$toName";
    }

    my $permissions = $config->replaceVariables( $self->{json}->{permissions} );
    my $uname       = $config->replaceVariables( $self->{json}->{uname} );
    my $gname       = $config->replaceVariables( $self->{json}->{gname} );
    my $mode        = $self->permissionToMode( $permissions, 0644 );

    my $ret = 1;
    unless( $backupContext->restore( $bucket, $toName )) {
        error( 'Cannot restore file: bucket:', $bucket, 'toName:', $toName, 'context:', $backupContext->asString() );
        $ret = 0;
        return $ret;
    }
    if( defined( $mode )) {
        chmod $mode, $toName;
    }

    my $uid = UBOS::Utils::getUid( $uname );
    my $gid = UBOS::Utils::getGid( $gname );

    if( $uid >= 0 || $gid >= 0 ) {
        chown $uid, $gid, $toName;
    }

    return $ret;
}

1;
