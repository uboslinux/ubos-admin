#!/usr/bin/perl
#
# Represents an Accessory for an App.
#
# This file is part of indiebox-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Accessory;

use base qw( IndieBox::Installable );
use fields;

use IndieBox::Configuration;
use IndieBox::Logging;
use IndieBox::Utils;
use JSON;

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

    if( $self->{config}->get( 'indiebox.checkmanifest', 1 )) {
		$self->checkManifest( 'accessory' );
    }
    trace( 'Created accessory', $packageName );

    return $self;
}

1;
