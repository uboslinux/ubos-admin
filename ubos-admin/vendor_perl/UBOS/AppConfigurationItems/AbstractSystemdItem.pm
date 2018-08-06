#!/usr/bin/perl
#
# Factors out common functionality of AppConfiguration items that
# configure systemd.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AppConfigurationItems::AbstractSystemdItem;

use base qw( UBOS::AppConfigurationItems::AppConfigurationItem );
use fields qw( suffix );

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
    my $suffix      = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $json, $role, $appConfig, $installable );

    $self->{suffix} = $suffix;

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

    trace( 'AbstractSystemdItem::deployOrCheck', $doIt, $defaultFromDir, $defaultToDir );

    my $ret = 1;
    if( $self->_runAtDeployUndeploy()) {
        $ret = $self->_switchOn( $vars );
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

    trace( 'AbstractSystemdItem::undeployOrCheck', $doIt, $defaultFromDir, $defaultToDir );

    my $ret = 1;
    if( $self->_runAtDeployUndeploy()) {
        $ret = $self->_switchOff( $vars );
    }
    return $ret;
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

    trace( 'AbstractSystemdItem::suspend', $defaultFromDir, $defaultToDir );

    my $ret = 1;
    unless( $self->_runAtDeployUndeploy()) {
        $ret = $self->_switchOff( $vars );
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

    trace( 'AbstractSystemdItem::resume', $defaultFromDir, $defaultToDir );

    my $ret    = 1;
    unless( $self->_runAtDeployUndeploy()) {
        $ret = $self->_switchOn( $vars );
    }

    return $ret;
}

##
# Evaluate whether to switch this item during the deploy/undeploy phase or
# during the suspend/resume phase.
sub _runAtDeployUndeploy {
    my $self = shift;

    if( exists( $self->{json}->{phase} ) &&  'suspendresume' eq $self->{json}->{phase} ) {
        return 0;

    } else {
        return 1;
    }
}

##
# Turn the item off
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub _switchOff {
    my $self = shift;
    my $vars = shift;

    my $ret    = 1;
    my $name   = $self->{json}->{name};
    my $suffix = $self->{suffix};

    $name = $vars->replaceVariables( $name );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "systemctl disable --now '$name.$suffix'", undef, \$out, \$err )) {
        error( 'AbstractSystemdItem::_switchOff: failed to disable', "$name.$suffix:", $out, $err );
        $ret = 0;
    }

    return $ret;
}

##
# Turn the item on
# $vars: the Variables object that knows about symbolic names and variables
# return: success or fail
sub _switchOn {
    my $self = shift;
    my $vars = shift;

    my $ret    = 1;
    my $name   = $self->{json}->{name};
    my $suffix = $self->{suffix};

    $name = $vars->replaceVariables( $name );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "systemctl enable --now '$name.$suffix'", undef, \$out, \$err )) {
        error( 'AbstractSystemdItem::_switchOn: failed to enable', "$name.$suffix:", $out, $err );
        $ret = 0;
    }

    return $ret;
}

1;
