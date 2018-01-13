#!/usr/bin/perl
#
# An AppConfiguration item that is a symbolic link.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AppConfigurationItems::Symlink;

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
    my $source = $self->{json}->{source};

    trace( 'Symlink::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $source, @$names );

    my $uname        = $self->{json}->{uname};
    my $gname        = $self->{json}->{gname};

    foreach my $name ( @$names ) {
        my $localName  = $name;
        $localName =~ s!^.+/!!;

        my $fromName = $source;
        $fromName =~ s!\$1!$name!g;      # $1: name
        $fromName =~ s!\$2!$localName!g; # $2: just the name without directories

        $fromName = $vars->replaceVariables( $fromName );

        my $toName = $name;
        $toName = $vars->replaceVariables( $toName );

        unless( $fromName =~ m#^/# ) {
            $fromName = "$defaultFromDir/$fromName";
        }
        unless( $toName =~ m#^/# ) {
            $toName = "$defaultToDir/$toName";
        }
        if( -e $fromName ) {
            if( $doIt ) {
                unless( -e $toName ) {
                    # These names sound a little funny for symlinks. Think "copy" instead of "link"
                    # and they make sense. We keep the names for consistency with other items.
                    # $fromName: the destination of the link
                    # $toName: the source of the link
                    UBOS::Utils::symlink( $fromName, $toName, $uname, $gname );
                } else {
                    error( 'Symlink::deployOrCheck: Cannot create symlink:', $toName );
                    $ret = 0;
                }
            }

        } else {
            # Cannot produce error message here, because some AppConfigItem before this one
            # might have created it.
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
    my $source = $self->{json}->{source};

    trace( 'Symlink::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $source, @$names );

    foreach my $name ( @$names ) {
        my $toName = $name;
        $toName = $vars->replaceVariables( $toName );

        unless( $toName =~ m#^/# ) {
            $toName = "$defaultToDir/$toName";
        }

        if( $doIt ) {
            if( -e $toName ) {
                $ret &= UBOS::Utils::deleteFile( $toName );

            } else {
                error( 'Symlink::undeployOrCheck: file does not exist:', $toName );
                $ret = 0;
            }
        }
    }
    return $ret;
}

1;
