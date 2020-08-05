#!/usr/bin/perl
#
# A variable substitution TemplateProcessor.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::TemplateProcessor::Varsubst;

use base qw( UBOS::TemplateProcessor );
use fields;

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
# $rawFileName: the source of the $raw content
# return: the output content
sub process {
    my $self        = shift;
    my $raw         = shift;
    my $vars        = shift;
    my $rawFileName = shift;

    my $ret = $vars->replaceVariables( $raw );

    return $ret;
}

1;
