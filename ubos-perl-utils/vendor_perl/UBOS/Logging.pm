#!/usr/bin/perl
#
# Logging facilities.
#
# This file is part of ubos-perl-utils.
# (C) 2012-2014 Indie Computing Corp.
#
# ubos-perl-utils is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-perl-utils is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-perl-utils. If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Logging;

use Cwd 'abs_path';
use Exporter qw( import );
use Log::Log4perl qw( :easy );
use Log::Log4perl::Level;

our @EXPORT = qw( debug info notice warning error fatal );
my $log;

# Initialize with something in case there's an error before logging is initialized
BEGIN {
    unless( Log::Log4perl::initialized ) {
        Log::Log4perl::Logger::create_custom_level( "NOTICE", "WARN", 2, 2 );

        my $config = q(
log4perl.rootLogger=WARN,CONSOLE

log4perl.appender.CONSOLE=Log::Log4perl::Appender::Screen
log4perl.appender.CONSOLE.stderr=1
log4perl.appender.CONSOLE.layout=PatternLayout
log4perl.appender.CONSOLE.layout.ConversionPattern=%-5p: %m%n
);
        Log::Log4perl->init( \$config );
        $log = Log::Log4perl->get_logger( $0);
    }
}

##
# Invoked at the beginning of a script, this initializes logging.
sub initialize {
    my $moduleName  = shift;
    my $scriptName  = shift || $moduleName;
    my $verbosity   = shift || 0;
    my $logConfFile = shift;

    if( $verbosity ) {
        if( $logConfFile ) {
            fatal( 'Specify --verbose or --logConfFile, not both' );
        }
        $logConfFile = "/etc/ubos/log-default-v$verbosity.conf";

    } elsif( !$logConfFile ) {
        $logConfFile = '/etc/ubos/log-default.conf';
    }

    unless( -r $logConfFile ) {
        fatal( 'Logging configuration file not found:', $logConfFile );
    }

    Log::Log4perl->init( $logConfFile );

    Log::Log4perl::MDC->put( 'SYSLOG_IDENTIFIER', $moduleName );
    $log = Log::Log4perl->get_logger( $scriptName );
}

##
# Emit a debug message.
# @msg: the message or message components
sub debug {
    my @msg = @_;

    if( $log->is_debug()) {
        $log->debug( _constructMsg( @msg ));
    }
}

##
# Is debug logging on?
# return: 1 or 0
sub isDebugActive {
    return $log->is_debug();
}

##
# Emit an info message.
# @msg: the message or message components
sub info {
    my @msg = @_;

    if( $log->is_info()) {
        $log->info( _constructMsg( @msg ));
    }
}

##
# Is info logging on?
# return: 1 or 0
sub isInfoActive {
    return $log->is_info();
}

##
# Emit a notice message.
# @msg: the message or message components
sub notice {
    my @msg = @_;

    if( $log->is_notice()) {
        $log->notice( _constructMsg( @msg ));
    }
}

##
# Is notice logging on?
# return: 1 or 0
sub isNoticeActive {
    return $log->is_notice();
}

##
# Emit a warning message. This is called 'warning' instead of 'warn'
# so it won't conflict with Perl's built-in 'warn'.
# @msg: the message or message components
sub warning {
    my @msg = @_;

    if( $log->is_warn()) {
        $log->warn( _constructMsg( @msg ));
    }
}

##
# Is warning logging on?
# return: 1 or 0
sub isWarningActive {
    return $log->is_warn();
}


##
# Emit an error message.
# @msg: the message or message components
sub error {
    my @msg = @_;

    if( $log->is_error()) {
        $log->error( _constructMsg( @msg ));
    }
}

##
# Is error logging on?
# return: 1 or 0
sub isErrorActive {
    return $log->is_error();
}

##
# Emit a fatal error message and exit with code 1.
# @msg: the message or message components
sub fatal {
    my @msg = @_;

	if( @msg ) {
		if( $log->is_error()) {
			$log->error( 'FATAL: ' . _constructMsg( @msg ));
		}
    }

    exit 1;
}

##
# Is fatal logging on?
# return: 1 or 0
sub isFatalActive {
    return $log->is_error();
}

##
# Construct a message from these arguments.
# @msg: the message or message components
# return: string message
sub _constructMsg {
    my @args = @_;

    my @args2 = map { my $a = $_; ref( $a ) eq 'CODE' ? $a->() : $a; } @args;
    
    my $ret = join( ' ', @args2 );
    return $ret;
}

1;
