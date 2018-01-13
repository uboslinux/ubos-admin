#!/usr/bin/perl
#
# A general-purpose superclass for TemplateProcessors.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::TemplateProcessor::TemplateProcessor;

use fields;

##
# Constructor
# return: the created TemplateProcessor object
sub new {
    my $self = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }

    return $self;
}

1;



