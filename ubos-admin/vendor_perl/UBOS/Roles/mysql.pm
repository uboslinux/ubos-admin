#!/usr/bin/perl
#
# mysql role. The interface to MySQL is in MySqlDriver.pm
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Roles::mysql;

use base qw( UBOS::Role );
use fields;

##
# Constructor
sub new {
    my $self = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new();
    return $self;
}

##
# Name of this role
# return: name
sub name {
    my $self = shift;

    return 'mysql';
}

# === Manifest checking routines from here ===

##
# Check the part of an app or accessory manifest that deals with this role.
# $roleName: name of this role, passed for efficiency
# $installable: the installable whose manifest is being checked
# $jsonFragment: the JSON fragment that deals with this role
# $retentionBuckets: keep track of retention buckets, so there's no overlap
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# $vars: the Variables object that knows about symbolic names and variables
sub checkInstallableManifestForRole {
    my $self                 = shift;
    my $roleName             = shift;
    my $installable          = shift;
    my $jsonFragment         = shift;
    my $retentionBuckets     = shift;
    my $skipFilesystemChecks = shift;
    my $vars                 = shift;

    if( $jsonFragment->{depends} ) {
        $installable->myFatal( "roles section: role $roleName: depends not allowed here" );
    }

    my $databaseOrScript = {
        'database'   => 1,
        'perlscript' => 1,
        'sqlscript'  => 1,
        'exec'       => 1
    };
    my $perlOrSql = {
        'perlscript' => 1,
        'sqlscript'  => 1,
        'exec'       => 1
    };
    
    $self->SUPER::checkManifestForRoleGenericAppConfigItems( $roleName, $installable, $jsonFragment, $databaseOrScript, $retentionBuckets, $skipFilesystemChecks, $vars );
    $self->SUPER::checkManifestForRoleGenericInstallersEtc(  $roleName, $installable, $jsonFragment, $perlOrSql, $vars );
}

1;
