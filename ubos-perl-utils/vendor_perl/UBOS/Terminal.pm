#!/usr/bin/perl
#
# Centralizes terminal-related functionality
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Terminal;

use Exporter qw( import );
use Term::ANSIColor;

our @EXPORT = qw( colPrint
                  colPrintTrace colPrintInfo colPrintDebug colPrintWarning colPrintError colPrintFatal
                  colPrintAskSection colPrintAsk );

unless( -t STDOUT ) {
    $ENV{ANSI_COLORS_DISABLED}++ ;
}

##
# Print normal text
# $c: the text
sub colPrint {
    my $c = shift;

    print( $c );
}

##
# Print an error
# $c: the text
sub colPrintTrace {
    my $c = shift;

    print( colored( $c, 'white' ));
}

##
# Print a debug message
# $c: the text
sub colPrintDebug {
    my $c = shift;

    print( colored( $c, 'yellow' ));
}

##
# Print a warning
# $c: the text
sub colPrintWarning {
    my $c = shift;

    print( colored( $c, 'cyan' ));
}

##
# Print an error
# $c: the text
sub colPrintInfo {
    my $c = shift;

    print( colored( $c, 'white' ));
}

##
# Print an error
# $c: the text
sub colPrintError {
    my $c = shift;

    print( colored( $c, 'red' ));
}

##
# Print a fatal
# $c: the text
sub colPrintFatal {
    my $c = shift;

    print( colored( $c, 'red' ));
}

##
# Print a question during an interactive session
# $c: the text
sub colPrintAsk {
    my $c = shift;

    print( colored( $c, 'yellow' ));
}

##
# Print a section heading during an interactive session
# $c: the text
sub colPrintAskSection {
    my $c = shift;

    print( colored( $c, 'green' ));
}

1;
