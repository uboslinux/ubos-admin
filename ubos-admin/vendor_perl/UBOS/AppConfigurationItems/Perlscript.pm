#!/usr/bin/perl
#
# An AppConfiguration item that is a Perl script to be run.
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

package UBOS::AppConfigurationItems::Perlscript;

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
sub installOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $source = $self->{json}->{source};

    my $script = $source;
    unless( $script =~ m#^/# ) {
        $script = "$defaultFromDir/$script";
    }

    unless( -r $script ) {
        error( 'File to run does not exist:', $script );
        return 0;
    }

    if( $doIt ) {
        my $scriptcontent = slurpFile( $script );
        my $operation = 'install';

        debug( 'Running eval', $script, $operation );

        unless( eval $scriptcontent ) {
            error( 'Running eval', $script, $operation, 'failed:', $@ );
            return 0;
        }
    }
    return 1;
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

    my $name = $self->{json}->{name};

    my $source = $self->{json}->{source};

    my $script = $source;
    $script = $config->replaceVariables( $script );

    unless( $script =~ m#^/# ) {
        $script = "$defaultFromDir/$script";
    }

    unless( -r $script ) {
        error( 'File to run does not exist:', $script );
        return 0;
    }

    if( $doIt ) {
        my $scriptcontent = slurpFile( $script );
        my $operation = 'uninstall';

        debug( 'Running eval', $script, $operation );

        unless( eval $scriptcontent ) {
            error( 'Running eval', $script, $operation, 'failed:', $@ );
            return 0;
        }
    }
    return 1;
}

##
# Run a post-deploy Perl script. May be overridden.
# $methodName: the type of post-install
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $config: the Configuration object that knows about symbolic names and variables
# return: success or fail
sub runPostDeployScript {
    my $self           = shift;
    my $methodName     = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    my $source = $self->{json}->{source};

    my $script = $source;
    unless( $script =~ m#^/# ) {
        $script = "$defaultFromDir/$script";
    }

    unless( -r $script ) {
        error( 'File to run does not exist:', $script );
        return 0;
    }

    my $scriptcontent = slurpFile( $script );
    my $operation     = $methodName;

    debug( 'Running eval', $script, $operation );

    unless( eval $scriptcontent ) {
        error( 'Running eval', $script, $operation, 'failed:', $@ );
        return 0;
    }
    return 1;
}

1;
