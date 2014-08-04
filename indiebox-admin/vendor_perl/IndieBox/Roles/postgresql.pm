#!/usr/bin/perl
#
# postgresql role. The interface to PostgreSql is in PostgreSqlDriver.pm
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

package IndieBox::Roles::postgresql;

use base qw( IndieBox::Role );
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

    return 'postgresql';
}

# === Manifest checking routines from here ===

##
# Check the part of an app or accessory manifest that deals with this role.
# $roleName: name of this role, passed for efficiency
# $installable: the installable whose manifest is being checked
# $jsonFragment: the JSON fragment that deals with this role
# $retentionBuckets: keep track of retention buckets, so there's no overlap
# $config: the Configuration object to use
sub checkInstallableManifestForRole {
    my $self             = shift;
    my $roleName         = shift;
    my $installable      = shift;
    my $jsonFragment     = shift;
    my $retentionBuckets = shift;
    my $config           = shift;

    if( $jsonFragment->{depends} ) {
        $installable->myFatal( "roles section: role $roleName: depends not allowed here" );
    }

    my $databaseOrScript = {
        'postgresql-database' => 1,
        'perlscript'          => 1,
        'sqlscript'           => 1
    };
    my $perlOrSql = {
        'perlscript' => 1,
        'sqlscript'  => 1
    };
    
    $self->SUPER::checkManifestForRoleGenericAppConfigItems(   $roleName, $installable, $jsonFragment, $databaseOrScript, $retentionBuckets, $config );
    $self->SUPER::checkManifestForRoleGenericTriggersActivate( $roleName, $installable, $jsonFragment, $config );
    $self->SUPER::checkManifestForRoleGenericInstallersEtc(    $roleName, $installable, $jsonFragment, $perlOrSql, $config );
}

1;
