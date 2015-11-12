# 
# Install UBOS for a Linux container running on a PC.
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
                                                  
package UBOS::Install::Installers::ContainerX86_64;

use base qw( UBOS::Install::AbstractContainerInstaller );
use fields;

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'x86_64';
}

1;
