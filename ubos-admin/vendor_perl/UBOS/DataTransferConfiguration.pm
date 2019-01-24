#!/usr/bin/perl
#
# Encapsulates data transfer options, and their management in a defaults
# file.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::DataTransferConfiguration;

use fields qw( config configChanged configFirstTime configFile noStoreConfig );

##
# Constructor.
# $defaultConfigFile: the name of the default configuration file
# $userConfigFile: name of the configuration file provided by the user
# $noStore: if true, do not read or write any configuration file
sub new {
    my $self              = shift;
    my $defaultConfigFile = shift;
    my $userConfigFile    = shift;
    my $noStoreConfig     = shift;

    my $config;
    my $configFile;
    my $configFirstTime = 1;
    my $configChanged   = 0;

    if( $userConfigFile ) {
        unless( -e $userConfigFile ) {
            fatal( 'Specified data transfer config file does not exist:', $userConfigFile );
        }
        $configFile = $userConfigFile;
    } else {
        $configFile = $defaultConfigFile;
    }

    if( !$noStoreConfig && -e $configFile ) {
        $config = UBOS::Utils::readJsonFromFile( $configFile );
        unless( $config ) {
            fatal( 'Failed to parse data transfer config file:', $configFile );
        }
        $configFirstTime = 0;
    } else {
        $config = {}; # by default we have nothing
    }

    unless( ref( $self )) {
        $self = fields::new( $self );
    }

    $self->{config}          = $config;
    $self->{configChanged}   = $configChanged;
    $self->{configFirstTime} = $configFirstTime;
    $self->{configFile}      = $configFile;
    $self->{noStoreConfig}   = $noStoreConfig;

    return $self;
}

##
# Obtain a configuration value
# $protocol: name of the protocol, for finding the right section
# $key: name of the setting within the protocol
# return the value
sub getValue {
    my $self     = shift;
    my $protocol = shift;
    my $key      = shift;

    my $config = $self->{config};
    my $value  = undef;

    if(    exists( $config->{$protocol} )
        && exists( $config->{$protocol}->{$key} ))
    {
        $value = $config->{$protocol}->{$key};
    }
    return $value;
}

##
# Set a new value
# $protocol: name of the protocol, for finding the right section
# $key: name of the setting within the protocol
# $value: the new value
# return true if the setting was changed
sub setValue {
    my $self     = shift;
    my $protocol = shift;
    my $key      = shift;
    my $value    = shift;

    my $config = $self->{config};

    if(    exists( $config->{$protocol} )
        && exists( $config->{$protocol}->{$key} ))
    {
        my $existingValue = $config->{$protocol}->{$key};

        if( defined( $value )) {
            if( defined( $existingValue )) {
                if( $config->{$protocol}->{$key} eq $value ) {
                    return 0;
                } # else continue
            } # else continue
        } else {
            if( !defined( $existingValue )) {
                return 0;
            } # else continue
        }
    }
    if( defined( $value )) {
        $config->{$protocol}->{$key} = $value;
        $self->{configChanged} = 1;
    }
    return 1;
}

##
# Unset a value
# $protocol: name of the protocol, for finding the right section
# $key: name of the setting within the protocol
sub removeValue {
    my $self     = shift;
    my $protocol = shift;
    my $key      = shift;

    my $config = $self->{config};
    my $value  = undef;

    if( exists( $config->{$protocol} )) {
        delete $config->{$protocol}->{$key};
    }
}

##
# Save the new values, if needed
# return: true if an actual save occurred
sub saveIfNeeded {
    my $self = shift;

    if( $self->{noStoreConfig} ) {
        return 0;
    }
    if( $self->{configChanged} ) {
        if( UBOS::Utils::writeJsonToFile( $self->{configFile}, $self->{config}, 0600 )) {
            if( $self->{firstTime} ) {
                info( 'Data transfer config saved as defaults for next time.' );
            } else {
                info( 'Data transfer config changed. Defaults were updated.' );
            }
        } else {
            warning( 'Failed to save data transfer config to:', $self->{configFile} );
        }

        return 1;
    }
    return 0;
}

1;

