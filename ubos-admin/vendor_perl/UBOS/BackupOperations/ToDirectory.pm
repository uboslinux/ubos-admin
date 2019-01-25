#!/usr/bin/perl

#
# A BackupOperation to a local or remote directory with a generated file name.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::BackupOperations::ToDirectory;

use base   qw( UBOS::BackupOperation );
use fields qw( toDirectory );

use UBOS::Logging;
use UBOS::Utils;

##
# Constructor
# $toDirectory: name of the destination directory
# $noTls: don't back up TLS information
# $noTorKey: don't back up Tor keys
# $encryptId: key identifier for encryption
# $dataTransferConfigFile: name of the data transfer config file provided by the user
# $ignoreDataTransferConfig: ignore data transfer config files for read and write
# @$argP: the remaining command-line arguments
# return: instance, or undef with $@ set
sub new {
    my $self                     = shift;
    my $toDirectory              = shift;
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
            $toDirectory,
            $self->{dataTransferConfiguration},
            $argP );

    unless( $dataTransferProtocol ) {
        fatal( 'Cannot determine the data transfer protocol from the arguments', $toDirectory || '-' );
    }

    $self->{toDirectory}          = $toDirectory;
    $self->{dataTransferProtocol} = $dataTransferProtocol;

    return $self;
}

##
# Define which files will be created, and check that they can be created.
# return: true or false
sub constructCheckPipeline {
    my $self = shift;

    my $encryptId = $self->{dataTransferConfiguration}->getValue( 'backup', 'encryptid' );
    my $uploadFile = constructFileName(
            $self->{toDirectory},
            $self->{sitesToBackup},
            $self->{appConfigsToBackup},
            $encryptId );

    $self->{uploadFile} = $uploadFile;

    return $self->SUPER::constructCheckPipeline();
}

##
# Construct a filename for the backup in a particular directory, given
# which items are supposed to be backed up, and given encryption.
# $backupToDirectory: the directory into which to back up
# %$sitesP: hash of Sites to back up
# %$appConfigsP: hash of AppConfigurations to back up
# $encryptId: optional identifier of the encryption key
# return: file name
sub constructFileName {
    my $backupToDirectory = shift;
    my $sitesP            = shift;
    my $appConfigsP       = shift;
    my $encryptId         = shift;

    my $backupToFile = $backupToDirectory;
    unless( $backupToFile =~ m!/$! ) {
        $backupToFile .= '/';
    }

    # generate local name
    my $name;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime( UBOS::Utils::now() );
    my $now = sprintf( "%04d%02d%02d%02d%02d%02d", $year+1900, $mon+1, $mday, $hour, $min, $sec );

    if( keys %$sitesP == 1 ) {
        my $siteId = ( keys %$sitesP )[0];
        $name = sprintf( "site-%s-%s.ubos-backup", $siteId, $now );

    } elsif( keys %$sitesP ) {
        my $hostId = lc( UBOS::Host::hostId());
        $name = sprintf( "site-multi-%s-%s.ubos-backup", $hostId, $now );

    } elsif( keys %$appConfigsP == 1 ) {
        my $appConfigId = ( keys %$appConfigsP )[0];
        $name = sprintf( "appconfig-%s-%s.ubos-backup", $appConfigId, $now );

    } else {
        my $hostId = lc( UBOS::Host::hostId());
        $name = sprintf( "appconfig-multi-%s-%s.ubos-backup", $hostId, $now );
    }
    $backupToFile .= $name;
    if( $encryptId ) {
        $backupToFile .= '.gpg';
    }

    trace( 'Generated new file name in directory:', $backupToDirectory, $backupToFile );

    return $backupToFile;
}

1;
