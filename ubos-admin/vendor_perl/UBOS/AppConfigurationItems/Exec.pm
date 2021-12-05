#!/usr/bin/perl
#
# An AppConfiguration item that an external executable to be run.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AppConfigurationItems::Exec;

use base qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields;

use UBOS::Logging;
use UBOS::Utils qw( myexec );

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

    trace( 'Exec::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir );

    return $self->_runIt( $doIt, 'deploy', $defaultFromDir, $defaultToDir, $vars );
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

    # do nothing

    trace( 'Exec::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir );

    return $self->_runIt( $doIt, 'undeploy', $defaultFromDir, $defaultToDir, $vars );
}

##
# Run a post-deploy Perl script. May be overridden.
# $methodName: the type of post-install
# $afterResume: 0 or 1. If 0, it's the run before the Site resumes; if 1, after
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub runPostDeployScript {
    my $self           = shift;
    my $methodName     = shift;
    my $afterResume    = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    if( $afterResume ) {
        if( !exists( $self->{json}->{phase} ) || $self->{json}->{phase} ne 'resume' ) {
            return 1;
        }
    } else {
        if( exists( $self->{json}->{phase} ) && $self->{json}->{phase} eq 'resume' ) {
            return 1;
        }
    }
    return $self->_runIt( 1, $methodName, $defaultFromDir, $defaultToDir, $vars );
}

##
# Factored out run method
sub _runIt {
    my $self           = shift;
    my $doIt           = shift;
    my $operation      = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $ret    = 1;
    my $source = $self->{json}->{source};

    unless( $source =~ m#^/# ) {
        $source = "$defaultFromDir/$source";
    }

    unless( -r $source ) {
        error( 'Exec::_runIt: file to run does not exist:', $source );
        return 0;
    }

    if( $doIt ) {
        my $tmpDir  = UBOS::Host::tmpdir();
        my $parFile = File::Temp->new( UNLINK => 1, DIR => $tmpDir );

        my $json = $vars->asJson();

        print $parFile UBOS::Utils::writeJsonToString( $json );
        close $parFile;

        my $cmd = "$source $operation $parFile";

        if( myexec( $cmd )) {
            error( 'Exec::_runIt: running', $source, $operation, 'failed' );
            $ret = 0;
        } else {
            trace( 'Exec::_runIt: running', $source, $operation, 'succeeded' );
        }
    }
    return $ret;
}

1;
