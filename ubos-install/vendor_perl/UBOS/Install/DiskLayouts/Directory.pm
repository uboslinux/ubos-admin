#
# A directory into which to install.
# 
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
