#
# Utilities.
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

package UBOS::Install::PartitionUtils;

use UBOS::Logging;

##
# Create an fdisk script fragment to change a partition type
# $mbrparttype: MBR partitiontype
# $i: partition number
sub appendFdiskChangePartitionType {
    my $mbrparttype = shift;
    my $i           = shift;

    unless( $mbrparttype ) {
        return 0;
    }

    my $script = '';
    if( $i > 1 ) {
        $script .= <<END;
t
$i
$mbrparttype
END
    } else {
        $script .= <<END;
t
$mbrparttype
END
    }
    return $script;
}

##
# Change the partition type of a GPT partition
# $gptparttype: GPT partitiontype
# $i: partition number
# $target: image or device
sub changeGptPartitionType {
    my $gptparttype = shift;
    my $i           = shift;
    my $target      = shift;

    unless( $gptparttype ) {
        return 0;
    }

    my $out;
    if( UBOS::Utils::myexec( "sgdisk '--typecode=$i:$gptparttype' '$target'", undef, \$out, \$out )) {
        error( "sgdisk --typecode=$i:$gptparttype $target :", $out );
        return 1;
    }
    return 0;
}

1;

