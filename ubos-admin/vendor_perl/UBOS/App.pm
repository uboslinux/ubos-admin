#!/usr/bin/perl
#
# Represents an App.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::App;

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

    if( UBOS::Host::vars()->getResolve( 'host.checkmanifest', 1 )) {
        $self->checkManifest( 'app', $skipFilesystemChecks );
    }

    return $self;
}

##
# If this app can only be run at a particular context path, return that context path
# return: context path
sub fixedContext {
    my $self = shift;

    if( exists( $self->{json}->{roles}->{apache2} ) && exists( $self->{json}->{roles}->{apache2}->{fixedcontext} )) {
        return $self->{json}->{roles}->{apache2}->{fixedcontext};
    } else {
        return undef;
    }
}

##
# If this app can be run at any context, return the default context path
# return: context path
sub defaultContext {
    my $self = shift;

    if( exists( $self->{json}->{roles}->{apache2} ) && exists( $self->{json}->{roles}->{apache2}->{defaultcontext} )) {
        return $self->{json}->{roles}->{apache2}->{defaultcontext};
    } else {
        return undef;
    }
}

##
# Return the well-known JSON defined by this App, if any
# return: JSON hash, or undef
sub wellknownJson {
    my $self = shift;

    if( exists( $self->{json}->{roles}->{apache2} )) {
        my $apache2Json = $self->{json}->{roles}->{apache2};
        if( exists( $apache2Json->{wellknown} )) {
            return $apache2Json->{wellknown};
        }
    }
    return undef;
}

1;
