# 
# Install UBOS for a PC.
#

use strict;
use warnings;

package UBOS::Install::Installers::Pc;

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
        $self->{hostname} = 'ubos-pc';
    }
    $self->SUPER::new( @args );

    return $self;
}

##
# Returns the arch for this device.
# return: the arch
sub arch {
    my $self = shift;

    return 'x86_64';
}

##
# Parameterized the DiskLayout as appropriate for this Installer.
# $diskLayout: the DiskLayout
sub parameterizeDiskLayout {
    my $self       = shift;
    my $diskLayout = shift;

    $diskLayout->setBootParameters( 'ext4',  '100M' );
    $diskLayout->setRootParameters( 'btrfs', '100G' );
    $diskLayout->setVarParameters(  'btrfs' );

    return 0;
}

##
# Format the disks as appropriate for the provided DiskLayout
# $diskLayout: the DiskLayout
sub formatDisks {
    my $self       = shift;
    my $diskLayout = shift;

    my $errors = 0;
    $errors += $diskLayout->formatRoot( 'btrfs' );
    $errors += $diskLayout->formatVarIfExists( 'brtfs' );
    $errors += $diskLayout->formatBootIfExists( 'ext4' );

    return $errors;
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
    $errors += $diskLayout->mountBootIfExists( 'ext4' );
    $errors += $diskLayout->mountVarIfExists( 'brtfs' );
}


1;
