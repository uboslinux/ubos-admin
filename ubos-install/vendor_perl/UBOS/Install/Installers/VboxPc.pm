# 
# Install UBOS for a PC emulated in VirtualBox.
# 
# This file is part of ubos-install.
# (C) 2012-2015 Indie Computing Corp.
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

# Device-specific notes:
# * random number generator: haveged for artificial entropy. VirtualBox does not
#   currently have any support for (virtual) hardware random devices:
#   https://www.virtualbox.org/pipermail/vbox-dev/2015-March/012909.html

use strict;
use warnings;
                                                  
package UBOS::Install::Installers::VboxPc;

use base qw( UBOS::Install::Installers::Pc );
use fields;

use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Install::AbstractDiskLayout;
use UBOS::Install::DiskLayouts::DiskBlockDevices;
use UBOS::Install::DiskLayouts::DiskImage;
use UBOS::Install::DiskLayouts::PartitionBlockDevices;
use UBOS::Install::DiskLayouts::PartitionBlockDevicesWithBootSector;
use UBOS::Logging;
use UBOS::Utils;

##
# Constructor
sub new {
    my $self = shift;
    my @args = @_;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    unless( $self->{hostname} ) {
        $self->{hostname} = 'ubos-' . $self->deviceClass();
    }
    $self->{kernelpackage} = 'linux';
    unless( $self->{devicepackages} ) {
        $self->{devicepackages} = [ qw( mkinitcpio virtualbox-guest ) ];
    }
    unless( $self->{deviceservices} ) {
        $self->{deviceservices} = [ qw( haveged vboxservice ubos-networking-client ) ];
    }
    $self->SUPER::new( @args );

    push @{$self->{packagedbs}}, 'virt';

    return $self;
}

##
# Returns the device class
sub deviceClass {
    my $self = shift;

    return 'vbox-pc';
}

1;
