#
# Abstract superclass for volumes in a disk layout.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Install::AbstractVolume;

use fields qw( name deviceNames mountPoint fs partedFs size mkfsflags );

use UBOS::Logging;

##
# Constructor for subclasses only
# $name: name of the volume to set as partition label if possible
# $fs: filesystem type, for mkfs
# $partedFs: filesystem type, for parted
# $size: size in bytes, or undef

sub new {
    my $self     = shift;
    my %pars = @_;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    foreach my $key ( keys %pars ) {
        $self->{$key} = $pars{$key}; # will produce errors if not exists
    }

    foreach my $key ( keys %$self ) {
        unless( $self->{$key} ) {
            error( 'Value not set for', ref( $self ), ':', $key );
        }
    }

    trace( 'Created volume', ref( $self ));

    return $self;
}

##
# Obtain the device name(s) for this volume
# return: array
sub getDeviceNames {
    my $self = shift;

    return @{$self->{deviceNames}};
}

##
# Obtain the mount point for this device, if any
# return: the mount point, if any
sub getMountPoint {
    my $self = shift;

    return $self->{mountPoint};
}

##
# Obtain the name of the filesystem, if any
# return: name of the file system, if any
sub getFs {
    my $self = shift;

    return $self->{fs};
}

##
# Determine whether this volume has a filesystem.
# return: 1 or 0
sub hasFs {
    my $self = shift;

    return 'none' eq $self->{fs};
}

##
# Is this a btrfs volume?
# return: 1 or 0
sub isBtrfs {
    my $self = shift;

    if( defined( $self->{fs} ) && 'btrfs' eq $self->{btrfs} ) {
        return 1;
    }
    return 0;
}

##
# Is this a root volume?
# return: 1 or 0
sub isRoot {
    my $self = shift;

    return 0; # override in subclasses
}

##
# Format this volume
# return: number of errors
sub formatVolume {
    my $self = shift;

    unless( $self->hasFs() ) {
        return 0;
    }

    my $fs     = $self->getFs();
    my $errors = 0;

    debugAndSuspend( 'Format file system for', @{$self->{deviceNames}}, 'with', $fs );

    if( $self->isBtrfs() ) {
        my $cmd = 'mkfs.btrfs -f';
        if( @{$self->{deviceNames}} > 1 ) {
            $cmd .= ' -m raid1 -d raid1';
        }
        if( exists( $self->{mkfsflags} )) {
            $cmd .= ' ' . $self->{mkfsflags};
        }
        if( exists( $self->{label} )) {
            $cmd .= " --label '" . $self->{label} . "'";
        }
        $cmd .= ' ' . join( ' ', @{$self->{devices}} );

        my $out;
        my $err;
        if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
            error( "$cmd error:", $err );
            ++$errors;
        }

    } elsif( 'swap' eq $fs ) {
        foreach my $dev ( @{$self->{deviceNames}} ) {
            my $out;
            my $err;
            my $cmd = "mkswap '$dev'";

            if( exists( $self->{label} )) {
                $cmd .= " --label '" . $self->{label} . "'";
            }

            if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
                error( "$cmd error:", $err );
                ++$errors;
            }
        }

    } else {
        foreach my $dev ( @{$self->{deviceNames}} ) {
            my $cmd = "mkfs.$fs";
            if( exists( $self->{mkfsflags} )) {
                $cmd .= ' ' . $self->{mkfsflags};
            }
            if( exists( $self->{label} )) {
                if( $fs eq 'vfat' ) {
                    $cmd .= " -n '" . $self->{label} . "'";
                } elsif( $fs eq 'ext4' ) {
                    $cmd .= " -L '" . $self->{label} . "'";
                } else {
                    warning( "Don't know how to label filesystem of type:", $fs );
                }
            }
            $cmd .= " '$dev'";

            my $out;
            my $err;
            if( UBOS::Utils::myexec( $cmd, undef, \$out, \$err )) {
                error( "$cmd error:", $err );
                ++$errors;
            }
        }
    }
    return $errors;
}

1;
