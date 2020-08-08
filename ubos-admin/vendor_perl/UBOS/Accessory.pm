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
    unless( $self->SUPER::new( $packageName, $manifestFileReader )) {
        return undef;
    }

    if( UBOS::Host::vars()->getResolve( 'host.checkmanifest', 1 )) {
        $self->checkManifest( 'accessory', $skipFilesystemChecks );
        $self->checkManifestAccessoryInfo();
    }

    return $self;
}

##
# Add to the hierarchical map for obtainInstallableAtAppconfigVars.
# $appConfig: the AppConfiguration
sub _createHierarchicalMapAtAppconfigVars {
    my $self      = shift;
    my $appConfig = shift;

    my $hierarchicalMap = $self->SUPER::_createHierarchicalMapAtAppconfigVars( $appConfig );

    my $accessoryId = exists( $self->{json}->{accessoryinfo}->{accessoryid} )
            ? $self->{json}->{accessoryinfo}->{accessoryid}
            : $self->packageName; # This is optional; always have a value

    $hierarchicalMap->{installable}->{accessoryinfo} = {
            'appid'         => $self->{json}->{accessoryinfo}->{appid},
            'accessoryid'   => $accessoryId,
            'accessorytype' => $self->{json}->{accessoryinfo}->{accessorytype}
    };

    return $hierarchicalMap;
}

##
# Obtain the app or apps that this accessory can be used with
sub getApps {
    my $self = shift;

    if( exists( $self->{json}->{accessoryinfo}->{appid} )) {
        return [ $self->{json}->{accessoryinfo}->{appid} ];
    } else {
        return @{$self->{json}->{accessoryinfo}->{appids}};
    }
}

##
# Determine whether this accessory can be used with the given app
# $app: the candidate app
# return: 1 if it can
sub canBeUsedWithApp {
    my $self = shift;
    my $app  = shift;

    # always there

    if( exists( $self->{json}->{accessoryinfo}->{appid} )) {
        return $app eq $self->{json}->{accessoryinfo}->{appid};
    } else {
        foreach my $id ( @{$self->{json}->{accessoryinfo}->{appids}} ) {
            if( $app eq $id ) {
                return 1;
            }
        }
        return 0;
    }
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
    if( exists( $json->{accessoryinfo}->{appid} )) {
        if( !$json->{accessoryinfo}->{appid} || ref( $json->{accessoryinfo}->{appid} ) ) {
            $self->myFatal( "accessoryinfo section: appid must be a valid package name" );
        }
    } elsif( exists( $json->{accessoryinfo}->{appids} )) {
        if( ref( $json->{accessoryinfo}->{appids} ) ne 'ARRAY' ) {
            $self->myFatal( "accessoryinfo section: appids must be an array" );
        } elsif( @{$json->{accessoryinfo}->{appids}} == 0 ) {
            $self->myFatal( "accessoryinfo section: appids must contain at least one app" );
        } else {
            foreach my $id ( @{$json->{accessoryinfo}->{appids}} ) {
                if( !$id || ref( $id ) ) {
                    $self->myFatal( "accessoryinfo section: members of appids must be valid package names" );
                }
            }
        }
    } else {
        $self->myFatal( "accessoryinfo section: no appid given" );
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
        my %requireds = ();
        foreach my $required ( @{$json->{accessoryinfo}->{requires}} ) {
            if( ref( $required ) || !$required ) {
                $self->myFatal( "accessoryinfo section: entries into requires must be strings" );
            }
            if( exists( $requireds{$required} )) {
                $self->myFatal( "accessoryinfo section: no duplicates allowed" );
            }
            $requireds{$required} = 1;
        }
    }

    return 1;
}

1;
