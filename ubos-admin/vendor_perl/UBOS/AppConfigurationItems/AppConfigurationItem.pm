#!/usr/bin/perl
#
# A general-purpose superclass for AppConfiguration items.
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

package UBOS::AppConfigurationItems::AppConfigurationItem;

use fields qw( json appConfig installable );

use UBOS::Logging;
use UBOS::TemplateProcessor::Passthrough;
use UBOS::TemplateProcessor::Perlscript;
use UBOS::TemplateProcessor::Varsubst;

##
# Constructor
# $json: the JSON fragment from the manifest JSON
# $appConfig: the AppConfiguration object that this item belongs to
# $installable: the Installable to which this item belongs to
sub new {
    my $self      = shift;
    my $json      = shift;
    my $appConfig = shift;
    my $installable = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{json}        = $json;
    $self->{appConfig}   = $appConfig;
    $self->{installable} = $installable;

    return $self;
}

##
# Run a post-deploy Perl script. May be overridden.
# $methodName: the type of post-install
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $config: the Configuration object that knows about symbolic names and variables
sub runPostDeployScript {
    my $self           = shift;
    my $methodName     = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    if( 'install' eq $methodName ) {
        $self->runInstallScript( $defaultFromDir, $defaultToDir, $config );

    } elsif( 'uninstall' eq $methodName ) {
        $self->runUninstallScript( $defaultFromDir, $defaultToDir, $config );

    } elsif( 'upgrade' eq $methodName ) {
        $self->runUpgradeScript( $defaultFromDir, $defaultToDir, $config );

    } else {
        error( 'Cannot perform runPostDeployScript( $methodName ) on', $self );
    }
}

##
# Run a post-deploy Perl install script. May be overridden.
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $config: the Configuration object that knows about symbolic names and variables
sub runInstallScript {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    error( 'Cannot perform runInstallScript on', $self );
}

##
# Run a pre-undeploy Perl uninstall script. May be overridden.
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $config: the Configuration object that knows about symbolic names and variables
sub runUninstallScript {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    error( 'Cannot perform runUninstallScript on', $self );
}

##
# Run a post-deploy Perl upgrade script. May be overridden.
# $defaultFromDir: the package directory
# $defaultToDir: the directory in which the installable was installed
# $config: the Configuration object that knows about symbolic names and variables
sub runUpgradeScript {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $config         = shift;

    error( 'Cannot perform runUpgradeScript on', $self );
}

##
# Default implementation to back this item up.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $backupContext: the Backup Context object
# $filesToDelete: array of filenames of temporary files that need to be deleted after backup
sub backup {
    my $self          = shift;
    my $dir           = shift;
    my $config        = shift;
    my $backupContext = shift;
    my $filesToDelete = shift;

    error( 'Cannot perform backup() on', $self );
}

##
# Default implementation to restore this item from backup.
# $dir: the directory in which the app was installed
# $config: the Configuration object that knows about symbolic names and variables
# $backupContext: the Backup Context object
sub restore {
    my $self          = shift;
    my $dir           = shift;
    my $config        = shift;
    my $backupContext = shift;

    error( 'Cannot perform restore() on', $self );
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
        $ret = new UBOS::TemplateProcessor::Passthrough();

    } elsif( 'varsubst' eq $templateLang ) {
        $ret = new UBOS::TemplateProcessor::Varsubst();

    } elsif( 'perlscript' eq $templateLang ) {
        $ret = new UBOS::TemplateProcessor::Perlscript();

    } else {
        error( 'Unknown templatelang:', $templateLang );
        $ret = new UBOS::TemplateProcessor::Passthrough();
    }
    return $ret;
}

1;
