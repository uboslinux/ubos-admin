#!/usr/bin/perl
#
# Functionality common to data transfer protocols.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AbstractDataTransferProtocol;

use fields qw( protocol location authority );

use UBOS::Logging;
use UBOS::Utils;

my $_transferProtocols = undef; # set as needed

##
# Obtain the available transfer protocols
sub availableDataTransferProtocols {

    unless( $_transferProtocols ) {
        $_transferProtocols = UBOS::Utils::findPerlShortModuleNamesInPackage( 'UBOS::DataTransferProtocols' );
    }
    return $_transferProtocols;
}

##
# Factory method for all the subclasses.
# $location: the location to parse
# @args: all other arguments
sub parseLocation {
    my $self     = shift;
    my $location = shift;
    my @args     = @_;

    my $transferProtocols = availableDataTransferProtocols();
    my $protocol          = undef;

    foreach my $shortPackageName ( sort keys %$transferProtocols ) {
        my $package  = $transferProtocols->{$shortPackageName};
        $protocol    = UBOS::Utils::invokeMethod( $package . '->parseLocation', $location, @args );
        if( $protocol ) {
            last;
        }
    }
    return $protocol;
}

##
# Constructor for subclasses.
# $location: the location
# $authority: the authority of the location
# $protocol: the protocol, for convenience
sub new {
    my $self      = shift;
    my $location  = shift;
    my $authority = shift;
    my $protocol  = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    $self->{location}  = $location;
    $self->{authority} = $authority;
    $self->{protocol}  = $protocol;

    return $self;
}

##
# Determine the location
# return: the location
sub location {
    my $self = shift;

    return $self->{location};
}

##
# Determine the authority section of the destination
# return 'example.com', or 'joe@example.com' or such
sub authority {
    my $self = shift;

    return $self->{authority};
}

##
# Send a local file to location via this protocol.
# $localFile: the local file
# $toFile: the ultimate destination as a file URL
# $config: configuration options
# return: success or fail
sub send {
    my $self      = shift;
    my $localFile = shift;
    my $toFile    = shift;
    my $config    = shift;

    fatal( 'Must be overridden:', ref( $self ));
}

##
# Static helper method to validate provided SSH options.
# This may be too strict; time will tell.
# $options: SSH options provided by the user
# Fatals if invalid.
sub validiateSshOptions {
    my $options = shift;

    $options =~ s!^\s+!!;
    $options =~ s!\s+$!!;
    my @options = split( /\s+/, $options );
    foreach my $option ( @options ) {
        unless( $option =~ m!^-o\s*[0-9a-zA-Z]+=[-+0-9a-zA-Z/,@.]+$! ) {
            fatal( 'Invalid SSH option value, provide options as -oXXX=YYY:', $option );
        }
    }
}

1;
