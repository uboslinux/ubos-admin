#!/usr/bin/perl
#
# The HTTPS data transfer protocol.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::DataTransferProtocols::Https;

use base qw( UBOS::AbstractDataTransferProtocol );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;
use URI;

##
# Factory method.
# If successful, return instance. If not, return undef.
# $location: the location to parse
# $dataTransferConfig: data transfer configuration options
# $argsP: array of remaining command-line arguments
# return: instance or undef
sub parseLocation {
    my $self               = shift;
    my $location           = shift;
    my $dataTransferConfig = shift;
    my $argsP              = shift;

    my $uri = URI->new( $location );
    if( !$uri->scheme() || $uri->scheme() ne protocol() ) {
        return undef;
    }

    my $method   = undef;
    my @resolve  = ();
    my $insecure = 0;
    my $parseOk = GetOptionsFromArray(
            $argsP,
            'method'    => \$method,
            'resolve=s' => \@resolve,
            'insecure'  => \$insecure );
    if( !$parseOk || @$argsP ) {
        return undef;
    }

    if( $method ) {
        $method = uc( $method );
        if( $method ne 'PUT' && $method ne 'POST' ) {
            fatal( 'HTTPS methods may only be PUT or POST, not:', $method );
        }
        $dataTransferConfig->setValue( 'https', $uri->authority(), 'method', $method );
    }
    if( @resolve ) {
        foreach my $resolve ( @resolve ) {
            if( $resolve !~ m!^(.+):(\d+):(.+)$! || !UBOS::Utils::isValidHostname( $1 ) || !UBOS::Utils::isValidHostname( $3 )) {
                fatal( 'Invalid --resolve specification:', $resolve );
            }
        }
        $dataTransferConfig->setValue( 'https', $uri->authority(), 'resolve', \@resolve );
    }
    if( $insecure ) {
        $dataTransferConfig->setValue( 'https', $uri->authority(), 'insecure', 1 );
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $location, protocol() );

    return $self;
}

##
# Is this a local destination?
# return: true or false
sub isLocal {
    my $self = shift;

    return 0;
}

##
# Is this a valid destination?
# $toFile: the candidate destination
# return: true or false
sub isValidToFile {
    my $self   = shift;
    my $toFile = shift;

    return 1;
}

##
# Send a local file to location via this protocol.
# $localFile: the local file
# $toFile: the ultimate destination as a file URL
# $dataTransferConfig: data transfer configuration options
# return: success or fail
sub send {
    my $self               = shift;
    my $localFile          = shift;
    my $toFile             = shift;
    my $dataTransferConfig = shift;

    my $uri = URI->new( $toFile );

    my $cmd = "curl -T '$localFile'";
    my $method   = $dataTransferConfig->getValue( 'https', $uri->authority(), 'method' );
    my $resolveP = $dataTransferConfig->getValue( 'https', $uri->authority(), 'resolve' );
    my $insecure = $dataTransferConfig->getValue( 'https', $uri->authority(), 'insecure' );
    if( $method ) {
        $cmd .= " -X $method";
    }
    if( $resolveP && @$resolveP ) {
        $cmd .= join( '', map { " --resolve '$_'" } @$resolveP );
    }
    if( $insecure ) {
        $cmd .= ' --insecure';
    }

    $cmd .= " '$toFile'";

    info( 'Uploading to', $toFile );

    my $err;
    if( UBOS::Utils::myexec( $cmd, undef, undef, \$err )) {
        $@ = "Upload failed to: $toFile : $err";
        return 0;
    }
    return 1;
}

##
# The supported protocol.
# return: the protocol
sub protocol {
    return 'https';
}

##
# Description of this data transfer protocol, to be shown to the user.
# return: description
sub description {
    return <<TXT;
The HTTPS protocol (HTTP over SSL/TLS). Options:
    --method <method> : use the HTTP method <method>.
    --resolve <spec>  : add one or more --resolve arguments to the CURL invocation.
    --insecure        : do not check TLS certificates.
TXT
}

1;
