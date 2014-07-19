#!/usr/bin/perl
#
# Logging facilities.
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

package IndieBox::Logging;

use Exporter qw( import );
use Log::Log4perl qw( :easy );
use Log::Log4perl::Level;

our @EXPORT = qw( trace debug info warn error fatal );
my $log;

BEGIN {
    my $confFile;
    if( $> ) { # we love perl -- this is non-root
        $confFile = '/etc/indiebox/log-user.conf';

    } else { # user is root
        $confFile = '/etc/indiebox/log.conf';
    }

    if( -r $confFile ) {
        Log::Log4perl->init( $confFile );

    } else {
        my $config = q(
log4perl.rootLogger=WARN,CONSOLE

log4perl.appender.CONSOLE=Log::Log4perl::Appender::Screen
log4perl.appender.CONSOLE.stderr=1
log4perl.appender.CONSOLE.layout=PatternLayout
log4perl.appender.CONSOLE.layout.ConversionPattern=%-5p: %m%n
log4perl.appender.CONSOLE.Threshold=WARN
);
        Log::Log4perl->init( \$config );
    }

    $log = Log::Log4perl->get_logger( __FILE__ );
    $log->trace( 'Initialized log4perl' );
}

##
# Avoid console output.
sub setQuiet {
    my $consoleAppender = Log::Log4perl->appenders()->{'CONSOLE'};

    if( $consoleAppender ) {
        $consoleAppender->threshold( $ERROR );
    }
}

##
# Verbose output
sub setVerbose {
    my $level = shift;

    my $consoleAppender = Log::Log4perl->appenders()->{'CONSOLE'};

    if( $consoleAppender ) {
        if( $level >= 3 ) {
            $consoleAppender->threshold( $TRACE );
        } elsif( $level >= 2 ) {
            $consoleAppender->threshold( $DEBUG );
        } else {
            $consoleAppender->threshold( $INFO );
        }
    }
}
    
##
# Emit a trace message.
# @msg: the message or message components
sub trace {
    my @msg = @_;

    if( $log->is_trace()) {
        $log->trace( join( ' ', @msg ));
    }
}

##
# Emit a debug message.
# @msg: the message or message components
sub debug {
    my @msg = @_;

    if( $log->is_debug()) {
        $log->debug( join( ' ', @msg ));
    }
}

##
# Emit an info message.
# @msg: the message or message components
sub info {
    my @msg = @_;

    if( $log->is_info()) {
        $log->info( join( ' ', @msg ));
    }
}

##
# Emit a warning message.
# @msg: the message or message components
sub warn {
    my @msg = @_;

    if( $log->is_warn()) {
        $log->warn( join( ' ', @msg ));
    }
}

##
# Emit an error message.
# @msg: the message or message components
sub error {
    my @msg = @_;

    if( $log->is_error()) {
        $log->error( join( ' ', @msg ));
    }
}

##
# Emit a fatal error message and exit with code 1.
# @msg: the message or message components
sub fatal {
    my @msg = @_;

	if( @msg ) {
		if( $log->is_fatal()) {
			$log->fatal( join( ' ', @msg ));
		}
    }

    exit 1;
}

1;
