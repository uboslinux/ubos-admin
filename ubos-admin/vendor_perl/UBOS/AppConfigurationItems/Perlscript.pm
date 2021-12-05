#!/usr/bin/perl
#
# An AppConfiguration item that is a Perl script to be run.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub deployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $source = $self->{json}->{source};

    trace( 'Perlscript::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $source );

    my $script = $source;
    unless( $script =~ m#^/# ) {
        $script = "$defaultFromDir/$script";
    }

    unless( -r $script ) {
        error( 'Perlscript::deployOrCheck: file to run does not exist:', $script );
        return 0;
    }

    if( $doIt ) {
        my $scriptcontent = slurpFile( $script );
        my $operation = 'deploy';

        my $config = $vars; # for backwards compatibility

        trace( 'Perlscript::deployOrCheck: running eval', $script, $operation );

        unless( eval $scriptcontent ) {
            error( 'Perlscript::deployOrCheck: running eval', $script, $operation, 'failed:', $@ );
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
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub undeployOrCheck {
    my $self           = shift;
    my $doIt           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $source = $self->{json}->{source};

    trace( 'Perlscript::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir, $source );

    my $script = $source;
    $script = $vars->replaceVariables( $script );

    unless( $script =~ m#^/# ) {
        $script = "$defaultFromDir/$script";
    }

    unless( -r $script ) {
        error( 'Perlscript::undeployOrCheck: file to run does not exist:', $script );
        return 0;
    }

    if( $doIt ) {
        my $scriptcontent = slurpFile( $script );
        my $operation = 'undeploy';

        my $config = $vars; # for backwards compatibility

        trace( 'Perlscript::undeployOrCheck: running eval', $script, $operation );

        unless( eval $scriptcontent ) {
            error( 'Perlscript::undeployOrCheck: running eval', $script, $operation, 'failed:', $@ );
            return 0;
        }
    }
    return 1;
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

    my $source = $self->{json}->{source};

    my $script = $source;
    unless( $script =~ m#^/# ) {
        $script = "$defaultFromDir/$script";
    }

    unless( -r $script ) {
        error( 'Perlscript::runPostDeployScript: file to run does not exist:', $script );
        return 0;
    }

    if( $afterResume ) {
        if( !exists( $self->{json}->{phase} ) || $self->{json}->{phase} ne 'resume' ) {
            return 1;
        }
    } else {
        if( exists( $self->{json}->{phase} ) && $self->{json}->{phase} eq 'resume' ) {
            return 1;
        }
    }

    my $scriptcontent = slurpFile( $script );
    my $operation     = $methodName;

    my $config = $vars; # for backwards compatibility

    trace( 'Perlscript::runPostDeployScript: running eval', $script, $operation );

    unless( eval $scriptcontent ) {
        error( 'Perlscript::runPostDeployScript: running eval', $script, $operation, 'failed:', $@ );
        return 0;
    }
    return 1;
}

1;
