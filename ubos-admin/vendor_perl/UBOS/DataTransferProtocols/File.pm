#!/usr/bin/perl
#
# A transfer protocol to/from a local file.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::DataTransferProtocols::File;

use base qw( UBOS::AbstractDataTransferProtocol );
use fields qw( force );

use Cwd 'abs_path';
use File::Basename;
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
    if( $uri->scheme() && $uri->scheme() ne protocol() ) {
        return undef;
    }

    my $force = undef; # let's not put this into the config store
    my $parseOk = GetOptionsFromArray(
            $argsP,
            'force', => \$force );
    if( !$parseOk || @$argsP ) {
        return undef;
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $location, protocol() );
    $self->{force} = $force;

    return $self;
}

##
# Is this a local destination?
# return: true or false
sub isLocal {
    my $self = shift;

    return 1;
}

##
# Is this a valid destination?
# $toFile: the candidate destination
# return: true or false
sub isValidToFile {
    my $self   = shift;
    my $toFile = shift;

    my $uri = URI->new( $toFile );
    $toFile = $uri->path();

    if( -e $toFile ) {
        if( -d $toFile ) {
            fatal( 'Specified output file is a directory:', $toFile );

        } elsif( !$self->{force} ) {
            fatal( 'Output file exists already. Use --force to overwrite.' );
        }
    }

    my $parent = dirname( $toFile );
    unless( -d $parent ) {
        fatal( 'Parent directory does not exist for:', $toFile );
    }

    return 1;
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

    my $uri = URI->new( $toFile );
    $toFile = $uri->path();

    if( abs_path( $localFile ) eq abs_path( $toFile )) {
        trace( 'No need to copy file:', $localFile );
        return 1; # nothing to do
    }

    my $cmd = "cp --reflink=auto '$localFile' '" . $toFile . "'";
    my $err;
    if( UBOS::Utils::myexec( $cmd, undef, undef, \$err ) && $err !~ m!are the same file! ) {
        error( 'Copy failed to:', $self->{path}, ':', $err );
        return 0;
    }
    return 1;
}

##
# The supported protocol.
# return: the protocol
sub protocol {
    return 'file';
}

##
# Description of this data transfer protocol, to be shown to the user.
# return: description
sub description {
    return <<TXT;
Local file copy. Options:
    --force : overwrite an already-existing file.
TXT
}

1;
