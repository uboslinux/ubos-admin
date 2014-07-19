#!/usr/bin/perl
#
# A variable substitution TemplateProcessor.
#
# This file is part of indiebox-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::TemplateProcessor::Varsubst;

use base qw( IndieBox::TemplateProcessor::TemplateProcessor );
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
# $config: the applicable Configuration object
# $rawFileName: the source of the $raw content
# return: the output content
sub process {
    my $self        = shift;
    my $raw         = shift;
    my $config      = shift;
    my $rawFileName = shift;

    my $ret = $config->replaceVariables( $raw );

    return $ret;
}

1;
