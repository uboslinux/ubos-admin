#!/usr/bin/perl
#
# A script-based TemplateProcessor.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::TemplateProcessor::Perlscript;

use base qw( UBOS::TemplateProcessor );
use fields;
use UBOS::Logging;

##
# Constructor
# return: the created File object
sub new {
    my $self = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->SUPER::new();

    return $self;
}

##
# Process content
# $raw: the input content
# $vars: the Variables object that knows about symbolic names and variables
# $rawSourceLabel: the source of the $raw content, for error messages
# return: the output content
sub process {
    my $self           = shift;
    my $raw            = shift;
    my $vars           = shift;
    my $rawSourceLabel = shift;

    my $config = $vars; # for backwards compatibility

    my $ret = eval $raw;
    unless( $ret ) {
        error( "Error when attempting to eval $rawSourceLabel:", $@ );
    }

    return $ret;
}

1;
