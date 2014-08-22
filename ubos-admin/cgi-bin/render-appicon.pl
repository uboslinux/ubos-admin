#!/usr/bin/perl
#
# Renders an appicon, or a default.
#
# This file is part of ubos-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# ubos-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.

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
    $filename = "/srv/http/_appicons/$1/$2.$3";
    my $ext   = $3;

    unless( -r $filename ) {
        $filename = "/srv/http/_appicons/default/$2.$3";
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
