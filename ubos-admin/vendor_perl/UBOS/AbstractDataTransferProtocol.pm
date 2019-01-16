#!/usr/bin/perl
#
# Functionality common to data transfer protocols.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AbstractDataTransferProtocol;

use fields qw( protocol location );

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
# $protocol: the protocol, for convenience
sub new {
    my $self     = shift;
    my $location = shift;
    my $protocol = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    $self->{location} = $location;
    $self->{protocol} = $protocol;

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
# Send a local file to location via this protocol.
# $localFile: the local file
# return: success or fail
sub send {
    my $self      = shift;
    my $localFile = shift;

    fatal( 'Must be overridden:', ref( $self ));
}

##
# Helper method to override a value in the config hash and report
# whether a change occurred.
# $config: the config hash
# $protocol: name of the protocol, for finding the right section
# $key: name of the setting within the protocol
# $value: the new value
# return true if the setting was changed
sub overrideConfigValue {
    my $config   = shift;
    my $protocol = shift;
    my $key      = shift;
    my $value    = shift;

    if(    exists( $config->{$protocol} )
        && exists( $config->{$protocol}->{$key} ))
    {
        my $existingValue = $config->{$protocol}->{$key};

        if( defined( $value )) {
            if( defined( $existingValue )) {
                if( $config->{$protocol}->{$key} eq $value ) {
                    return 0;
                } # else continue
            } # else continue
        } else {
            if( !defined( $existingValue )) {
                return 0;
            } # else continue
        }
    }
    if( defined( $value )) {
        $config->{$protocol}->{$key} = $value;
    }
    return 1;
}

1;
