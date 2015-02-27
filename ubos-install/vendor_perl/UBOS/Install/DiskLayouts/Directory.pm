#
# A directory into which to install.
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

use strict;
use warnings;

package UBOS::Install::DiskLayouts::Directory;

use base qw( UBOS::Install::AbstractDiskLayout );
use fields qw( directory );

use UBOS::Install::AbstractDiskLayout;
use UBOS::Logging;

##
# Constructor
# $directory: the directory to install into
sub new {
    my $self      = shift;
    my $directory = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    $self->SUPER::new( {} );
    
    $self->{directory} = $directory;

    return $self;
}

##
# Format the configured disks.
sub createDisks {
    my $self = shift;

    # noop
    return 0;
}

##
# Unmount the previous mounts. Override because we need to take care of the
# loopback devices.
# $target: the target directory
sub umountDisks {
    my $self   = shift;
    my $target = shift;

    # noop
    return 0;
}

##
# Determine the boot loader device for this DiskLayout
sub determineBootLoaderDevice {
    my $self = shift;

    return undef;
}

1;
