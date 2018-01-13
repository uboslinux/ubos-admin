#!/usr/bin/perl
#
# An AppConfiguration item that is the running of a systemd service.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AppConfigurationItems::SystemdService;

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
# Suspend this item.
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub suspend {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $ret  = 1;
    my $name = $self->{json}->{name};

    trace( 'SystemdService::suspend', $defaultFromDir, $defaultToDir, $name );

    $name = $vars->replaceVariables( $name );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "systemctl disable '$name.service'", undef, \$out, \$err )) {
        error( 'SystemdService::suspend: failed to disable systemd service', "$name.service:", $out, $err );
        $ret = 0;
    }
    # stop even if disable failed
    if( UBOS::Utils::myexec( "systemctl stop '$name.service'", undef, \$out, \$err )) {
        error( 'SystemdService::suspend: failed to stop systemd service', "$name.service:", $out, $err );
        $ret = 0;
    }

    return $ret;
}

##
# Resume this item.
# $defaultFromDir: the directory to which "source" paths are relative to
# $defaultToDir: the directory to which "destination" paths are relative to
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub resume {
    my $self           = shift;
    my $defaultFromDir = shift;
    my $defaultToDir   = shift;
    my $vars           = shift;

    my $ret  = 1;
    my $name = $self->{json}->{name};

    trace( 'SystemdService::resume', $defaultFromDir, $defaultToDir, $name );

    $name = $vars->replaceVariables( $name );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "systemctl start '$name.service'", undef, \$out, \$err )) {
        error( 'SystemdService::resume: failed to start systemd service', "$name.service:", $out, $err );
        $ret = 0;

    # only enable if start succeeded
    } elsif( UBOS::Utils::myexec( "systemctl enable '$name.service'", undef, \$out, \$err )) {
        error( 'SystemdService::resume: failed to enable systemd service', "$name.service:", $out, $err );
        $ret = 0;
    }

    return $ret;
}

1;
