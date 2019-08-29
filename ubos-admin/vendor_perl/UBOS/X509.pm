#!/usr/bin/perl
#
# Operations on certificates
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::X509;

use UBOS::Logging;
use UBOS::Utils;

##
# Determine certain information about this certificate. It is returned
# as key-value pairs.
# $crtFile: name of the file containing the certificate
# return: hash, or undef when error
sub crtInfo {
    my $crtFile = shift;

    my $out;
    if( UBOS::Utils::myexec( "openssl x509 -in '$crtFile' -dates -subject -noout", undef, \$out )) {
        error( 'Failed to run opeenssl x509 against:', $crtFile );
        return undef; # better return value?
    }

    my $ret = {};
    foreach my $line ( split( "\n", $out )) {
        my( $key, $value ) = split( /\s*=\s*/, $line, 2 );
        $ret->{$key} = $value;
    }
    return $ret;
}

1;
