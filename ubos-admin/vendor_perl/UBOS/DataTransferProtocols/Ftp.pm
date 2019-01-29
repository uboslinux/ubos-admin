#!/usr/bin/perl
#
# The SFTP data transfer protocol.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::DataTransferProtocols::Ftp;

use base qw( UBOS::AbstractDataTransferProtocol );
use fields qw( passiveMode );

use File::Basename;
use File::Spec;
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
        fatal( 'Need to provide user info in the URL, e.g. ftp://joe@example.com/destination' );
    }

    my $passiveMode = undef;
    my $parseOk     = GetOptionsFromArray(
            $argsP,
            'passive' => \$passiveMode );
    if( !$parseOk || @$argsP ) {
        return undef;
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $location, protocol() );
    $self->{passiveMode} = $passiveMode ? 1 : 0;

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

    my $uri  = URI->new( $toFile ); # ftp://user@host/path

    my $cmd  = 'ftp -n';
    $cmd    .= ' ' . $uri->host();

    my $script  = 'quote user ' . $uri->userinfo() . "\n";
    $script    .= 'quote pass ' . $uri->userinfo() . "\n";
    $script    .= "binary\n";

    if( $self->{passiveMode} ) {
        $script .= "passive\n";
    }

    my( $localFilename, $localDir, $localSuffix ) = fileparse( File::Spec->rel2abs( $localFile ) );
    if( $localDir ) {
        $script .= "lcd $localDir\n";
    }
    my( $remoteFilename, $remoteDir, $remoteSuffix ) = fileparse( $uri->path() );
    if( $remoteDir ) {
        $script .= "cd $remoteDir\n";
    }

    $script .= "put $localFilename $remoteFilename\n";
    $script .= "quit\n";

    info( 'Uploading to', $toFile );

    my $out;
    if( UBOS::Utils::myexec( $cmd, $script, \$out, \$out )) {
        $@ = 'Upload failed to: ' . $toFile . ' : ' . $out;
        return 0;
    } elsif( $out =~ m!Permission denied! || $out =~ m!No such! ) {
        $@ = 'Upload failed to: ' . $toFile . ' : ' . $out;
        return 0;
    }
    return 1;
}

##
# The supported protocol.
# return: the protocol
sub protocol {
    return 'ftp';
}

##
# Description of this data transfer protocol, to be shown to the user.
# return: description
sub description {
    return <<TXT;
The FTP protocol. Options:
    --passive : use passive mode
TXT
}

1;
