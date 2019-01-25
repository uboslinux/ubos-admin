#!/usr/bin/perl
#
# A BackupOperation to a local or remote file name.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::BackupOperations::ToFile;

use base qw( UBOS::BackupOperation );
use fields qw();

use UBOS::AbstractDataTransferProtocol;
use UBOS::Logging;
use UBOS::Utils;

##
# Constructor
# $toFile: name of the destination file
# $noTls: don't back up TLS information
# $noTorKey: don't back up Tor keys
# $encryptId: key identifier for encryption
# $dataTransferConfigFile: name of the data transfer config file provided by the user
# $ignoreDataTransferConfig: ignore data transfer config files for read and write
# @$argP: the remaining command-line arguments
# return: instance, or undef with $@ set
sub new {
    my $self                     = shift;
    my $toFile                   = shift;
    my $noTls                    = shift;
    my $noTorKey                 = shift;
    my $encryptId                = shift;
    my $dataTransferConfigFile   = shift;
    my $ignoreDataTransferConfig = shift;
    my $argP                     = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self = $self->SUPER::new( $noTls, $noTorKey, $encryptId, $dataTransferConfigFile, $ignoreDataTransferConfig );
    unless( $self ) {
        return undef;
    }

    my $dataTransferProtocol = UBOS::AbstractDataTransferProtocol->parseLocation(
            $toFile,
            $self->{dataTransferConfiguration},
            $argP );

    unless( $dataTransferProtocol ) {
        fatal( 'Cannot determine the data transfer protocol from the arguments', $toFile || '-' );
    }

    $self->{uploadFile}           = $toFile;
    $self->{dataTransferProtocol} = $dataTransferProtocol;

    return $self;
}

1;
