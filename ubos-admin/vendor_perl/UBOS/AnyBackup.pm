#!/usr/bin/perl
#
# Dispatcher to look at a file, determine which type of backup file it is, and
# instantiate the correct concrete class.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::AnyBackup;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use UBOS::Logging;
use UBOS::Utils;

# find supported backup types
my $backupTypes = UBOS::Utils::findPerlModuleNamesInPackage( 'UBOS::Backup', '.+Backup' );

##
# Instantiate the right Backup object from an archive file
# $archive: the archive file name
# return: the Backup object
sub readArchive {
    my $self    = shift;
    my $archive = shift;

    trace( 'AnyBackup::readArchive', $archive );

    my $ret = undef;
    foreach my $backupType ( sort values %$backupTypes ) {
        my $compressionType = UBOS::Utils::invokeMethod( $backupType . '::compression' );
        if( 'zip' eq $compressionType ) {
            my $zip = Archive::Zip->new();
            if( $zip->read( $archive ) == AZ_OK ) {
                $ret = UBOS::Utils::invokeMethod( $backupType . '::read', $archive, $zip );
                if( $ret ) {
                    return $ret;
                }
            }

        } else {
            fatal( 'Unknown compression type', $compressionType ); # internal error
        }
    }

    return $ret;
}

##
# Return an error message if the provided file cannot be parsed by any
# known Backup parser.
# $in: the file that was attempted to be parsed
# return: the error message
sub cannotParseArchiveErrorMessage {
    my $in = shift;

    my $ret = 'Cannot read backup file ' . $in . '.';
    if( keys %$backupTypes ) {
        $ret .= "\nSupported backup types are: ";
        $ret .= join( ', ', map { UBOS::Utils::invokeMethod( $_ . '::backupType' ); } sort values %$backupTypes );

    } else {
        $ret .= "\nNo backup types seem to be known on this device.";
    }

    return $ret;
}

1;
