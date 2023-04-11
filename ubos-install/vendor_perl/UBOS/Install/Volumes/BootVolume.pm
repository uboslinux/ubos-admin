#
# A boot volume.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Volumes::BootVolume;

use base qw( UBOS::Install::AbstractVolume );
use fields;

use UBOS::Logging;

##
# Constructor
# %pars: parameters with the same names as member variables
sub new {
    my $self = shift;
    my %pars = @_;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    # set defaults for this class here
    $self->{label}       = 'boot';
    $self->{mountPoint}  = '/boot';
    $self->{fs}          = 'vfat';
    $self->{mkfsFlags}   = '-F32';
    $self->{partedFs}    = 'fat32';
    $self->{partedFlags} = [ qw( boot ) ];
    $self->{size}        = 512 * 1024 * 1024; # 512 M

    $self->SUPER::new( %pars );

    return $self;
}

1;
