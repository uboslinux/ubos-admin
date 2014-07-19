#!/usr/bin/perl
#
# An AppConfiguration item that is a symbolic link
#
# This file is part of indiebox-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::AppConfigurationItems::Symlink;

use base qw( IndieBox::AppConfigurationItems::AppConfigurationItem );
use fields;

use IndieBox::Logging;

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

    my $permissions  = $self->{json}->{permissions};
    my $uname        = $self->{json}->{uname};
    my $gname        = $self->{json}->{gname};
    my $mode         = $self->permissionToMode( $permissions, 0644 );

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
        if( -r $fromName ) {
            if( $doIt ) {
                unless( -e $toName ) {
                    # These names sound a little funny for symlinks. Think "copy" instead of "link"
                    # and they make sense. We keep the names for consistency with other items.
                    # $fromName: the destination of the link
                    # $toName: the source of the link
                    IndieBox::Utils::symlink( $fromName, $toName, $mode, $uname, $gname );
                } else {
                    error( 'Cannot create symlink:', $toName );
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

    my $source = $self->{json}->{source};

    foreach my $name ( @$names ) {
        my $toName = $name;
        $toName = $config->replaceVariables( $toName );

        unless( $toName =~ m#^/# ) {
            $toName = "$defaultToDir/$toName";
        }

        if( $doIt ) {
            if( -e $toName ) {
                IndieBox::Utils::deleteFile( $toName );
            } else {
                error( 'File does not exist:', $toName );
            }
        }
    }
}

1;
