#!/usr/bin/perl
#
# mysql role. The interface to MySQL is in MySqlDriver.pm
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

package IndieBox::Roles::mysql;

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

    return 'mysql';
}

# === Manifest checking routines from here ===

##
# Check the part of an app or accessory manifest that deals with this role.
# $roleName: name of this role, passed for efficiency
# $packageName: name of the package whose manifest is being checked
# $jsonFragment: the JSON fragment that deals with this role
# $retentionBuckets: keep track of retention buckets, so there's no overlap
# $config: the Configuration object to use
# $myFatal: method to be invoked if an error has been found
sub checkInstallableManifestForRole {
    my $self             = shift;
    my $roleName         = shift;
    my $packageName      = shift;
    my $jsonFragment     = shift;
    my $retentionBuckets = shift;
    my $config           = shift;
    my $myFatal          = shift;

    if( $jsonFragment->{depends} ) {
        $myFatal->( $packageName, "roles section: role $roleName: depends not allowed here" );
    }

    my $databaseOrScript = {
        'mysql-database' => 1,
        'perlscript'     => 1,
        'sqlscript'      => 1
    };
    my $perlOrSql = {
        'perlscript' => 1,
        'sqlscript'  => 1
    };
    
    $self->SUPER::checkManifestForRoleGenericAppConfigItems(   $roleName, $packageName, $jsonFragment, $databaseOrScript, $retentionBuckets, $config, $myFatal );
    $self->SUPER::checkManifestForRoleGenericTriggersActivate( $roleName, $packageName, $jsonFragment, $config, $myFatal );
    $self->SUPER::checkManifestForRoleGenericInstallersEtc(    $roleName, $packageName, $jsonFragment, $perlOrSql, $config, $myFatal );
}

1;
