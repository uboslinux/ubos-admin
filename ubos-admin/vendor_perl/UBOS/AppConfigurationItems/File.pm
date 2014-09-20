#!/usr/bin/perl
#
# An AppConfiguration item that is a file.
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

package UBOS::AppConfigurationItems::File;

use base qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields;

use UBOS::Logging;
use UBOS::Utils qw( saveFile slurpFile );

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

    my $sourceOrTemplate = $self->{json}->{template};
    unless( $sourceOrTemplate ) {
        $sourceOrTemplate = $self->{json}->{source};
    }

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
                    error( 'Writing file failed:', $toName );
                }
            }

        } else {
            error( 'File does not exist:', $fromName );
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
            UBOS::Utils::deleteFile( $toName );
        }
    }
}

##
# Back this item up.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $backup: the Backup object
# $contextPathInBackup: the directory, in the Backup, into which this item will be backed up
# $filesToDelete: array of filenames of temporary files that need to be deleted after backup
sub backup {
    my $self                = shift;
    my $dir                 = shift;
    my $config              = shift;
    my $backup              = shift;
    my $contextPathInBackup = shift;
    my $filesToDelete       = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    if( @$names != 1 ) {
        fatal( 'Cannot backup item with more than one name:', @$names );
    }

    my $toName = $names->[0];
    $toName = $config->replaceVariables( $toName );
    unless( $toName =~ m#^/# ) {
        $toName = "$dir/$toName";
    }

    my $bucket = $self->{json}->{retentionbucket};

    $backup->addFile( $toName, "$contextPathInBackup/$bucket" );
}

##
# Default implementation to restore this item from backup.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $backup: the Backup object
# $contextPathInBackup: the directory, in the Backup, into which this item will be backed up
sub restore {
    my $self                = shift;
    my $dir                 = shift;
    my $config              = shift;
    my $backup              = shift;
    my $contextPathInBackup = shift;

    my $names = $self->{json}->{names};
    unless( $names ) {
        $names = [ $self->{json}->{name} ];
    }
    if( @$names != 1 ) {
        error( 'Cannot restore item with more than one name:', @$names );
    }

    my $toName = $names->[0];
    $toName = $config->replaceVariables( $toName );
    unless( $toName =~ m#^/# ) {
        $toName = "$dir/$toName";
    }

    my $bucket       = $self->{json}->{retentionbucket};
    my $permissions = $config->replaceVariables( $self->{json}->{permissions} );
    my $uname       = $config->replaceVariables( $self->{json}->{uname} );
    my $gname       = $config->replaceVariables( $self->{json}->{gname} );
    my $mode        = $self->permissionToMode( $permissions, 0644 );

    if( $backup->restore( "$contextPathInBackup/$bucket", $toName )) {
        # There's actually a file by that name in the Backup

        if( defined( $mode )) {
            chmod $mode, $toName;
        }

        my $uid = UBOS::Utils::getUid( $uname );
        my $gid = UBOS::Utils::getGid( $gname );

        if( $uid >= 0 || $gid >= 0 ) {
            chown $uid, $gid, $toName;
        }
    }
    return 1;
}        

1;
