#!/usr/bin/perl
#
# A general-purpose superclass for TemplateProcessors.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::TemplateProcessor;

use fields;

use UBOS::Logging;
use UBOS::TemplateProcessor::Passthrough;
use UBOS::TemplateProcessor::Perlscript;
use UBOS::TemplateProcessor::Varsubst;

##
# Factory method to instantiate the right subclass of TemplateProcessor.
# return: instance of subclass of TemplateProcessor
sub create {
    my $templateLang = shift;
    my $ret;

    if( !defined( $templateLang )) {
        $ret = UBOS::TemplateProcessor::Passthrough->new();

    } elsif( 'varsubst' eq $templateLang ) {
        $ret = UBOS::TemplateProcessor::Varsubst->new();

    } elsif( 'perlscript' eq $templateLang ) {
        $ret = UBOS::TemplateProcessor::Perlscript->new();

    } else {
        error( 'Unknown templatelang:', $templateLang );
        $ret = UBOS::TemplateProcessor::Passthrough->new();
    }
    return $ret;
}


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
