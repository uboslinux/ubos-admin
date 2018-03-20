#!/usr/bin/perl
#
# Renders an appicon, or a default.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

use CGI;
use File::Copy;

my $q = new CGI;
my $u = $q->url( -absolute => 1 );
my $filename;
my $mime;

# This regex must be consistent with the one in the Apache config file
if( $u =~ m!/_appicons/([-a-z0-9]+)/([0-9]+x[0-9]+|license)\.(png|txt)$! ) {
    my $dir   = $1;
    my $file  = $2;
    my $ext   = $3;

    $filename = "/ubos/http/_appicons/$dir/$file.$ext";
    unless( -r $filename ) {
        $filename = "/srv/http/_appicons/$dir/$file.$ext";
    }
    unless( -r $filename ) {
        $filename = "/srv/http/_appicons/default/$file.$ext";
    }
    if( $ext eq 'txt' ) {
        $mime = 'text/plain';
    } elsif( $ext eq 'png' ) {
        $mime = 'image/png';
    } else {
        $filename = undef; # we don't know what that is, so we don't return it
    }
}

if( $filename ) {
    print $q->header( -type => $mime );

    unless( $mime =~ m!^text/! ) {
       binmode STDOUT;
    }
    copy $filename, \*STDOUT;
    
} else {
    print $q->header( -status => 404 );

}
exit 0;
