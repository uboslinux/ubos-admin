#!/usr/bin/perl
#
# An AppConfiguration item that is a file.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AppConfigurationItems::File;

use base qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields;

use UBOS::Logging;
use UBOS::TemplateProcessor;
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

    my $sourceOrTemplate = $self->{json}->{template};
    unless( $sourceOrTemplate ) {
        $sourceOrTemplate = $self->{json}->{source};
    }

    trace( 'File::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $sourceOrTemplate, @$names );

    my $templateLang = exists( $self->{json}->{templatelang} ) ? $self->{json}->{templatelang} : undef;
    my $permissions  = $vars->replaceVariables( $self->{json}->{permissions} );
    my $uname        = $vars->replaceVariables( $self->{json}->{uname} );
    my $gname        = $vars->replaceVariables( $self->{json}->{gname} );
    my $mode         = $self->permissionToMode( $permissions, 0644 );

    foreach my $name ( @$names ) {
        my $localName  = $name;
        $localName =~ s!^.+/!!;

        my $fromName = $sourceOrTemplate;
        $fromName =~ s!\$1!$name!g;      # $1: name
        $fromName =~ s!\$2!$localName!g; # $2: just the name without directories
        $fromName = $vars->replaceVariables( $fromName );

        my $toName = $name;
        $toName = $vars->replaceVariables( $toName );

        unless( $fromName =~ m#^/# ) {
            $fromName = "$defaultFromDir/$fromName";
        }
        unless( $toName =~ m#^/# ) {
            if( !$doIt && !$defaultToDir ) {
                error( 'File::deployOrCheck: no default "to" dir in this role' );
                $ret = 0;
            }
            $toName = "$defaultToDir/$toName";
        }
        if( -r $fromName ) {
            my $content           = slurpFile( $fromName );
            my $templateProcessor = UBOS::TemplateProcessor::create( $templateLang );

            my $contentToSave = $templateProcessor->process( $content, $vars, "file $sourceOrTemplate" );

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
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub undeployOrCheck {
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

    trace( 'File::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir, @$names );

    foreach my $name ( reverse @$names ) {
        my $toName = $name;
        $toName = $vars->replaceVariables( $toName );

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
    trace( 'File::backup', $bucket, @$names );

    if( @$names != 1 ) {
        error( 'File::backup: cannot backup item with more than one name:', @$names );
        return 0;
    }

    my $toName = $names->[0];
    $toName = $vars->replaceVariables( $toName );
    unless( $toName =~ m#^/# ) {
        $toName = "$dir/$toName";
    }

    return $backupContext->addFile( $toName, $bucket );
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
    trace( 'File::restore', $bucket, $names );

    if( @$names != 1 ) {
        error( 'File::restore: cannot restore item with more than one name:', @$names );
        return 0;
    }

    my $toName = $names->[0];
    $toName = $vars->replaceVariables( $toName );
    unless( $toName =~ m#^/# ) {
        $toName = "$dir/$toName";
    }

    my $permissions = $vars->replaceVariables( $self->{json}->{permissions} );
    my $uname       = $vars->replaceVariables( $self->{json}->{uname} );
    my $gname       = $vars->replaceVariables( $self->{json}->{gname} );
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
