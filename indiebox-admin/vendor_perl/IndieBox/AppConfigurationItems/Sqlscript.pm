#!/usr/bin/perl
#
# An AppConfiguration item that is a SQL script to be run
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

# FIXME: This currently only works with MySQL

use strict;
use warnings;

package IndieBox::AppConfigurationItems::Sqlscript;

use base qw( IndieBox::AppConfigurationItems::AppConfigurationItem );
use fields;

use IndieBox::Databases::MySqlDriver;
use IndieBox::Logging;
use IndieBox::Utils qw( saveFile slurpFile );

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

    error( 'Cannot perform install on', $self );
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

    error( 'Cannot perform install on', $self );
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

    my $sourceOrTemplate = $self->{json}->{template};
    unless( $sourceOrTemplate ) {
        $sourceOrTemplate = $self->{json}->{source};
    }
    my $templateLang = $self->{json}->{templatelang};
    my $delimiter    = $self->{json}->{delimiter};
    my $name         = $self->{json}->{name};

    unless( $sourceOrTemplate =~ m#^/# ) {
        $sourceOrTemplate = "$defaultFromDir/$sourceOrTemplate";
    }

    if( -r $sourceOrTemplate ) {
        my $content           = slurpFile( $sourceOrTemplate );
        my $templateProcessor = $self->_instantiateTemplateProcessor( $templateLang );

        my $sql = $templateProcessor->process( $content, $config, $sourceOrTemplate );

        my( $rootUser, $rootPass ) = IndieBox::Databases::MySqlDriver::findRootUserPass();

        my( $dbName, $dbHost, $dbPort, $dbUserLid, $dbUserLidCredential, $dbUserLidCredType )
                = IndieBox::ResourceManager::getDatabase(
                        'mysql',
                        $self->{appConfig}->appConfigId,
                        $self->{installable}->packageName,
                        $name );

        # from the command-line; that way we don't have to deal with messy statement splitting
        my $cmd = "mysql '--host=$dbHost' '--port=$dbPort'";
        $cmd .= " '--user=$rootUser' '--password=$rootPass'";
        if( $delimiter ) {
            $cmd .= " '--delimiter=$delimiter'";
        }
        $cmd .= " '$dbName'";

        IndieBox::Utils::myexec( $cmd, $sql );

    } else {
        error( 'File does not exist:', $sourceOrTemplate );
    }
}

1;
