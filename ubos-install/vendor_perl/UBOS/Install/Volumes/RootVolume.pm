#
# A root volume.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::Volumes::RootVolume;

use base qw( UBOS::Install::AbstractVolume );
use fields qw();

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
    $self->{label}       = 'root';
    $self->{mountPoint}  = '/';
    $self->{fs}          = 'btrfs';
    $self->{mkfsFlags}   = '';
    $self->{partedFs}    = 'btrfs';
    $self->{partedFlags} = [];
    $self->{size}        = ''; # set but no value, so it takes up the remaining space

    $self->SUPER::new( %pars );

    return $self;
}

##
# Is this a root volume?
# return: 1 or 0
sub isRoot {
    my $self = shift;

    return 1;
}

1;
