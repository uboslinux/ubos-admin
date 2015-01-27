# 
# Install UBOS on an SD Card for a Raspberry Pi.
#

use strict;
use warnings;

package UBOS::Install::Installers::Rpi;

use base qw( UBOS::Install::AbstractInstaller );
use fields;

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
        $self->{hostname} = 'ubos-raspberry-pi';
    }
    $self->SUPER::new( @args );

    return $self;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'armv6l';
}

##
# Parameterized the DiskLayout as appropriate for this Installer.
# $diskLayout: the DiskLayout
sub parameterizeDiskLayout {
    my $self       = shift;
    my $diskLayout = shift;

    $diskLayout->setBootParameters( 'vfat',  '100M' );
    $diskLayout->setRootParameters( 'btrfs' );

    return 0;
}

##
# Mount the disk(s) as appropriate for the provided DiskLayout
# $diskLayout: the DiskLayout
# $target: the directory to which to mount the disk(s)
sub mountDisks {
    my $self       = shift;
    my $diskLayout = shift;
    my $target     = shift;

    my $errors = 0;
    $errors += $diskLayout->mountRoot( 'brtfs' );
    $errors += $diskLayout->mountBootIfExists( 'vfat' );

    return $errors;
}

1;
