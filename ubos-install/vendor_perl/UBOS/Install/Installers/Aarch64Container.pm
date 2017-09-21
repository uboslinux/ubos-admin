#
# Install UBOS for a Linux container running on an aarch64 device.
#
# This file is part of ubos-install.
# (C) 2012-2017 Indie Computing Corp.
#
# ubos-install is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-install is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-install.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Install::Installers::Aarch64Container;

use base qw( UBOS::Install::AbstractContainerInstaller );
use fields;

##
# Constructor. Add keyring, as on arm (unlike x86), pacman does not depend on it
sub new {
    my $self = shift;
    my @args = @_;

    unless( ref $self ) {
        $self = fields::new( $self );

    }
    $self->SUPER::new( @args );

    push @{$self->{devicepackages}}, 'archlinuxarm-keyring';

    return $self;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'aarch64';
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'container';
}

##
# Help text
sub help {
    return 'Linux container on aarch64';
}

1;
