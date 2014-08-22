#!/usr/bin/perl
#
# A script-based TemplateProcessor.
#
# This file is part of ubos-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# ubos-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::TemplateProcessor::Perlscript;

use base qw( UBOS::TemplateProcessor::TemplateProcessor );
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
# $config: the applicable Configuration object
# $rawFileName: the source of the $raw content
# return: the output content
sub process {
    my $self        = shift;
    my $raw         = shift;
    my $config      = shift;
    my $rawFileName = shift;

    my $ret = eval $raw;
    unless( $ret ) {
        error( "Error when attempting to eval file $rawFileName:", $@ );
    }

    return $ret;
}

1;
