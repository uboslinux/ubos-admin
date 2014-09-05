#!/usr/bin/perl
#
# Represents an App.
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
#

use strict;
use warnings;

package UBOS::App;

use base qw( UBOS::Installable );
use fields;

##
# Constructor.
# $packageName: unique identifier of the package
sub new {
    my $self        = shift;
    my $packageName = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( $packageName );

    if( $self->{config}->get( 'ubos.checkmanifest', 1 )) {
        $self->checkManifest( 'app' );
    }

    return $self;
}

##
# If this app can only be run at a particular context path, return that context path
# return: context path
sub fixedContext {
    my $self = shift;

    return $self->{json}->{roles}->{apache2}->{fixedcontext};
}

##
# If this app can be run at any context, return the default context path
# return: context path
sub defaultContext {
    my $self = shift;

    return $self->{json}->{roles}->{apache2}->{defaultcontext};
}

1;
