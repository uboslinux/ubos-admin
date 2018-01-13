#
# Utilities for partitioning.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
        return '';
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

