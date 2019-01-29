#!/usr/bin/perl
#
# The secure-copy data transfer protocol.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::DataTransferProtocols::Scp;

use base qw( UBOS::AbstractDataTransferProtocol );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
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
    if( !$uri->userinfo()) {
        fatal( 'Need to provide user info in the URL, e.g. scp://joe@example.com/destination' );
    }

    my $idfile = undef;
    my $limit  = undef;
    my $parseOk = GetOptionsFromArray(
            $argsP,
            'idfile|i=s' => \$idfile,
            'limit=s'    => \$limit );
    if( !$parseOk || @$argsP ) {
        return undef;
    }

    if( $idfile ) {
        unless( -r $idfile ) {
            fatal( 'File cannot be read:', $idfile );
        }
        $dataTransferConfig->setValue( 'scp', 'idfile', $idfile );
    }
    if( $limit ) {
        unless( $limit =~ m!^\d+$! ) {
            fatal( 'Limit must be a positive integer:', $limit );
        }
        $dataTransferConfig->setValue( 'scp', 'limit', $limit );
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

    my $idfile = $dataTransferConfig->getValue( 'scp', 'idfile' );
    my $limit  = $dataTransferConfig->getValue( 'scp', 'limit' );

    my $cmd = 'scp';
    $cmd .= ' -B'; # batch mode
    $cmd .= ' -C'; # compression
    $cmd .= ' -p'; # preserve timestamps etc
    $cmd .= ' -q'; # quiet mode

    if( $idfile ) {
        $cmd .= " -i '$idfile'"; # private key
    }
    if( $limit ) {
        $cmd .= " -l '$limit'"; # $data transfer limit
    }

    $cmd .=  "'$localFile'";

    my $uri  = URI->new( $toFile ); # scp://user@host/path -> user@host:path
    my $dest = $uri->userinfo();    # we know it's there
    $dest .= '@' . $uri->authority();
    $dest .= ':' . $uri->path();

    info( 'Uploading to', $dest );

    $cmd .= " '$dest'";

    my $err;
    if( UBOS::Utils::myexec( $cmd, undef, undef, \$err )) {
        error( 'Upload failed to:', $dest, $err );
        return 0;
    }
    return 1;
}

##
# The supported protocol.
# return: the protocol
sub protocol {
    return 'scp';
}

##
# Description of this data transfer protocol, to be shown to the user.
# return: description
sub description {
    return <<TXT;
The scp protocol. Options:
    --limit <limit>   : limits the used bandwidth, specified in Kbit/s.
    --idfile <idfile> : selects the file from which the identity (private key)
                        for public key authentication is read.
TXT
}

1;
