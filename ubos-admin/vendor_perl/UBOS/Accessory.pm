#!/usr/bin/perl
#
# Represents an Accessory for an App.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Accessory;

use base qw( UBOS::Installable );
use fields;

use UBOS::Host;

##
# Constructor.
# $packageName: unique identifier of the package
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# $manifestFileReader: pointer to a method that knows how to read the manifest file
sub new {
    my $self                 = shift;
    my $packageName          = shift;
    my $skipFilesystemChecks = shift;
    my $manifestFileReader   = shift || \&UBOS::Host::defaultManifestFileReader;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $packageName, $manifestFileReader );

    if( UBOS::Host::vars()->get( 'host.checkmanifest', 1 )) {
        $self->checkManifest( 'accessory', $skipFilesystemChecks );
        $self->checkManifestAccessoryInfo();
    }

    my $accessoryId = exists( $self->{json}->{accessoryinfo}->{accessoryid} )
            ? $self->{json}->{accessoryinfo}->{accessoryid}
            : $packageName; # This is optional; always have a value

    $self->vars()->put(
                "package.name"                            => $packageName,
                "installable.accessoryinfo.appid"         => $self->{json}->{accessoryinfo}->{appid},
                "installable.accessoryinfo.accessoryid"   => $accessoryId,
                "installable.accessoryinfo.accessorytype" => $self->{json}->{accessoryinfo}->{accessorytype} );

    return $self;
}

##
# Obtain the app that this accessory belongs to
# return: the package name of the app
sub belongsToApp {
    my $self = shift;

    # always there
    return $self->{json}->{accessoryinfo}->{appid};
}

##
# Determine the set of other installables that must also be deployed at the
# same AppConfiguration.
# return: array (usually empty)
sub requires {
    my $self = shift;

    my $json = $self->{json};

    if( exists( $json->{accessoryinfo}->{requires} )) {
        return @{$json->{accessoryinfo}->{requires}};
    } else {
        return ();
    }
}

##
# Check validity of the manifest JSON's accessoryinfo section.
# return: 1 or exits with fatal error
sub checkManifestAccessoryInfo {
    my $self = shift;

    my $json = $self->{json};

    unless( defined( $json->{accessoryinfo} )) {
        $self->myFatal( "accessoryinfo section required for accessories" );
    }
    unless( ref( $json->{accessoryinfo} ) eq 'HASH' ) {
        $self->myFatal( "accessoryinfo is not a HASH" );
    }
    unless( defined( $json->{accessoryinfo}->{appid} )) {
        $self->myFatal( "accessoryinfo section: no appid given" );
    }
    if( ref( $json->{accessoryinfo}->{appid} ) || !$json->{accessoryinfo}->{appid} ) {
        $self->myFatal( "accessoryinfo section: appid must be a valid package name" );
    }
    if( exists( $json->{accessoryinfo}->{accessoryid} ) && ref( $json->{accessoryinfo}->{accessoryid} )) {
        $self->myFatal( "accessoryinfo section: accessoryid, if provided, must be a string" );
    }
    if( exists( $json->{accessoryinfo}->{accessorytype} ) && ref( $json->{accessoryinfo}->{accessorytype} )) {
        $self->myFatal( "accessoryinfo section: accessorytype, if provided, must be a string" );
    }
    if( exists( $json->{accessoryinfo}->{requires} )) {
        if( ref( $json->{accessoryinfo}->{requires} ) ne 'ARRAY' ) {
            $self->myFatal( "accessoryinfo section: requires, if provided, must be an array" );
        }
        foreach my $required ( @{$json->{accessoryinfo}->{requires}} ) {
            if( ref( $required ) || !$required ) {
            $self->myFatal( "accessoryinfo section: entries into requires must be strings" );
            }
        }
    }

    return 1;
}

1;
