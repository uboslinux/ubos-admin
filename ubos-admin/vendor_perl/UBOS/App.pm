#!/usr/bin/perl
#
# Represents an App.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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
#

use strict;
use warnings;

package UBOS::App;

use base qw( UBOS::Installable );
use fields;

use UBOS::Host;

##
# Constructor.
# $packageName: unique identifier of the package
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# $manifestFileReader: pointer to a method that knows how to read the manifest file
sub new {
    my $self                 = shift;
    my $packageName          = shift;
    my $skipFilesystemChecks = shift;
    my $manifestFileReader   = shift || \&UBOS::Host::defaultManifestFileReader;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $packageName, $manifestFileReader );

    if( UBOS::Host::vars()->get( 'host.checkmanifest', 1 )) {
        $self->checkManifest( 'app', $skipFilesystemChecks );
    }

    return $self;
}

##
# If this app can only be run at a particular context path, return that context path
# return: context path
sub fixedContext {
    my $self = shift;

    if( exists( $self->{json}->{roles}->{apache2} ) && exists( $self->{json}->{roles}->{apache2}->{fixedcontext} )) {
        return $self->{json}->{roles}->{apache2}->{fixedcontext};
    } else {
        return undef;
    }
}

##
# If this app can be run at any context, return the default context path
# return: context path
sub defaultContext {
    my $self = shift;

    if( exists( $self->{json}->{roles}->{apache2} ) && exists( $self->{json}->{roles}->{apache2}->{defaultcontext} )) {
        return $self->{json}->{roles}->{apache2}->{defaultcontext};
    } else {
        return undef;
    }
}

##
# Return an array of paths relative to the AppConfiguration's context
# that shall be included in the "allow" section of the site's robots.txt file.
# return: array of paths
sub robotstxtAllow {
    my $self = shift;

    my @ret = ();
    if( exists( $self->{json}->{roles}->{apache2} )) {
        my $apache2Json = $self->{json}->{roles}->{apache2};
        if(    exists( $apache2Json->{wellknown} )
            && exists( $apache2Json->{wellknown}->{robotstxt} )
            && exists( $apache2Json->{wellknown}->{robotstxt}->{allow} ))
        {
            @ret = @{$apache2Json->{wellknown}->{robotstxt}->{allow}};
        }
    }
    return @ret;
}

##
# Return an array of paths relative to the AppConfiguration's context
# that shall be included in the "disallow" section of the site's robots.txt file.
# return: array of paths
sub robotstxtDisallow {
    my $self = shift;

    my @ret = ();
    if( exists( $self->{json}->{roles}->{apache2} )) {
        my $apache2Json = $self->{json}->{roles}->{apache2};
        if(    exists( $apache2Json->{wellknown} )
            && exists( $apache2Json->{wellknown}->{robotstxt} )
            && exists( $apache2Json->{wellknown}->{robotstxt}->{disallow} ))
        {
            @ret = @{$apache2Json->{wellknown}->{robotstxt}->{disallow}};
        }
    }
    return @ret;
}
            
1;
