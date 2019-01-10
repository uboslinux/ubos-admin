#!/usr/bin/perl
#
# A general-purpose superclass for AppConfiguration items.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AppConfigurationItems::AppConfigurationItem;

use fields qw( json role appConfig installable );

use UBOS::Logging;
use UBOS::TemplateProcessor::Passthrough;
use UBOS::TemplateProcessor::Perlscript;
use UBOS::TemplateProcessor::Varsubst;

##
# Constructor
# $json: the JSON fragment from the manifest JSON
# $appConfig: the AppConfiguration object that this item belongs to
# $role: the Role to which this item belongs to
# $installable: the Installable to which this item belongs to
sub new {
    my $self        = shift;
    my $json        = shift;
    my $role        = shift;
    my $appConfig   = shift;
    my $installable = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{json}        = $json;
    $self->{role}        = $role;
    $self->{appConfig}   = $appConfig;
    $self->{installable} = $installable;

    return $self;
}

##
# Run a post-deploy Perl script. May be overridden.
# $methodName: the type of post-install
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub runPostDeployScript {
    my $self           = shift;
    my $methodName     = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $ret = 1;
    if( 'install' eq $methodName ) {
        $ret &= $self->runInstallScript( $defaultFromDir, $defaultToDir, $vars );

    } elsif( 'uninstall' eq $methodName ) {
        $ret &= $self->runUninstallScript( $defaultFromDir, $defaultToDir, $vars );

    } elsif( 'upgrade' eq $methodName ) {
        $ret &= $self->runUpgradeScript( $defaultFromDir, $defaultToDir, $vars );

    } else {
        error( 'AppConfigurationItem::runPostDeployScript: cannot perform', $methodName, 'on', $self );
        $ret = 0;
    }
    return $ret;
}

##
# Run a post-deploy Perl install script. May be overridden.
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub runInstallScript {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    error( 'AppConfigurationItem::runInstallScript: cannot perform', $self );

    return 0;
}

##
# Run a pre-undeploy Perl uninstall script. May be overridden.
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub runUninstallScript {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    error( 'AppConfigurationItem::runUninstallScript: cannot perform', $self );

    return 0;
}

##
# Run a post-deploy Perl upgrade script. May be overridden.
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub runUpgradeScript {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    error( 'AppConfigurationItem::runUpgradeScript: cannot perform', $self );

    return 0;
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

    return 1; # nothing on this level
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

    return 1; # nothing on this level
}

##
# Default implementation to suspend this item.
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub suspend {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    return 1; # nothing on this level
}

##
# Default implementation to resume this item.
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub resume {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    return 1; # nothing on this level
}

##
# Default implementation to back this item up.
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

    error( 'AppConfigurationItem::backup: cannot perform', $self );

    return 0;
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

    error( 'AppConfigurationItem::restore: cannot perform', $self );

    return 0;
}

##
# Convert a permission attribute given as string into octal
# $s: permission attribute as string
# $default: octal mode if $s is undef
# return: octal
sub permissionToMode {
    my $self       = shift;
    my $permission = shift;
    my $default    = shift;

    if( $permission ) {
        return oct( $permission );
    } else {
        return $default;
    }
}

##
# Internal helper to instantiate the right subclass of TemplateProcessor.
# return: instance of subclass of TemplateProcessor
sub _instantiateTemplateProcessor {
    my $self         = shift;
    my $templateLang = shift;
    my $ret;

    if( !defined( $templateLang )) {
        $ret = UBOS::TemplateProcessor::Passthrough->new();

    } elsif( 'varsubst' eq $templateLang ) {
        $ret = UBOS::TemplateProcessor::Varsubst->new();

    } elsif( 'perlscript' eq $templateLang ) {
        $ret = UBOS::TemplateProcessor::Perlscript->new();

    } else {
        error( 'Unknown templatelang:', $templateLang );
        $ret = UBOS::TemplateProcessor::Passthrough->new();
    }
    return $ret;
}

1;
