#
# A directory into which to install.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::VolumeLayouts::Directory;

use base qw( UBOS::Install::AbstractVolumeLayout );
use fields qw( directory );

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
    $self->SUPER::new();

    $self->{directory} = $directory;

    return $self;
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

1;
