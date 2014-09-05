#!/usr/bin/perl
#
# Apache2 abstraction.
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

package UBOS::Apache2;

use Fcntl qw( SEEK_END SEEK_SET );
use UBOS::Logging;
use UBOS::Utils;
use Time::HiRes qw( gettimeofday );

my $modsAvailableDir  = '/etc/httpd/ubos/mods-available';
my $modsEnabledDir    = '/etc/httpd/ubos/mods-enabled';
my $phpModulesDir     = '/usr/lib/php/modules';
my $phpModulesConfDir = '/etc/php/conf.d';

my $logFile  = '/var/log/httpd/error_log';

my @minimumApacheModules = qw( alias authz_core authz_host cgi deflate dir env log_config mime mpm_prefork setenvif unixd ); # always need those

##
# Reload configuration
sub reload {
    _syncApacheCtl( 'reload' );

    1;
}

##
# Restart configuration
sub restart {
    _syncApacheCtl( 'restart' );

    1;
}

##
# Helper method to restart or reload Apache, and wait until it is ready to accept
# requests again. Because apachectl is asynchronous, this keeps reading the system
# log until it appears that the operation is complete. For good measure, we wait a
# little bit longer.
# Note that open connections will not necessarily be closed forcefully.
# $command: the Apache systemd command, such as 'restart' or 'reload'
# $max: maximum seconds to wait until returning from this method
# $poll: seconds (may be fraction) between subsequent reads of the log
# return: 0: success, 1: timeout
sub _syncApacheCtl {
    my $command = shift;
    my $max     = shift || 15;
    my $poll    = shift || 0.2;

    unless( open( FH, '<', $logFile )) {
        error( 'Cannot open', $logFile );
        return;
    }
    my $lastPos = sysseek( FH, 0, SEEK_END );
    close( FH );

    UBOS::Utils::myexec( "systemctl $command ubos-httpd" );
    
    my( $seconds, $microseconds ) = gettimeofday;
    my $until = $seconds + 0.000001 * $microseconds + $max;
    
    while( 1 ) {
        select( undef, undef, undef, $poll ); # apparently a tricky way of sleeping for $poll seconds that works with fractions        

        unless( open( FH, '<', $logFile )) {
            error( 'Cannot open', $logFile );
            return;
        }
        my $pos = sysseek( FH, 0, SEEK_END );
        
        my $written = '';
        if( $pos != $lastPos ) {
            sysseek( FH, $lastPos, SEEK_SET );
            sysread( FH, $written, $pos - $lastPos, 0 );
        }
        close( FH );
        $lastPos = $pos;
        
        ( $seconds, $microseconds ) = gettimeofday;
        my $delta = $seconds + 0.000001 * $microseconds - $until;
        
        if( $written =~ /resuming normal operations/ ) {
            sleep( 2 ); # two more seconds
            debug( 'Detected Apache restart after ', $delta + $max, 'seconds' );
            return 0;
        }
        
        if( $delta >= $max ) {
            warning( 'Apache command', $command, 'not finished within', $max, 'seconds' );
            return 1;
        }
    }
}

##
# Make the changes to Apache configuration files are in place that are needed by UBOS.
sub ensureConfigFiles {
    debug( 'Apache2::ensureConfigFiles' );

    activateApacheModules( @minimumApacheModules );

    # Make sure we have default SSL keys and a self-signed cert

    my $sslDir  = '/etc/httpd/conf';
    my $crtFile = "$sslDir/server.crt";
    my $keyFile = "$sslDir/server.key";
    my $csrFile = "$sslDir/server.csr";
    
    my $uid = 0;  # avoid overwrite by http
    my $gid = UBOS::Utils::getGid( 'http' );

    unless( -f $keyFile ) {
        UBOS::Utils::myexec( "openssl genrsa -out '$keyFile' 4096" );
        chmod 0040, $keyFile;
        chown $uid, $gid, $keyFile;
    }
    unless( -f $crtFile ) {
        UBOS::Utils::myexec(
                "openssl req -new -key '$keyFile' -out '$csrFile'"
                . ' -subj "/CN=localhost.localdomain"' );

        UBOS::Utils::myexec( "openssl x509 -req -days 3650 -in '$csrFile' -signkey '$keyFile' -out '$crtFile'" );
        chmod 0040, $crtFile;
        chown $uid, $gid, $crtFile;
    }
}

##
# Activate one ore more Apache modules
# @modules: list of module names
sub activateApacheModules {
    my @modules = @_;

    my $ret = 0;
    foreach my $module ( @modules ) {
        if( -e "$modsEnabledDir/$module.load" ) {
            next;
        }
        unless( -e "$modsAvailableDir/$module.load" ) {
            warning( 'Cannot find Apache2 module, not activating:', $module );
            next;
        }
        debug( 'Activating Apache2 module:', $module );

        UBOS::Utils::symlink( "$modsAvailableDir/$module.load", "$modsEnabledDir/$module.load" );
        ++$ret;
    }

    return $ret;
}

##
# Activate one or more PHP modules
# @modules: list of module names
sub activatePhpModules {
    my @modules = @_;

    my $ret = 0;
    foreach my $module ( @modules ) {
        if( -e "$phpModulesConfDir/$module.ini" ) {
            next;
        }
        unless( -e "$phpModulesDir/$module.so" ) {
            warning( 'Cannot find PHP module, not activating:', $module );
            next;
        }
        debug( 'Activating PHP module:', $module );

        UBOS::Utils::saveFile( "$phpModulesConfDir/$module.ini", <<END );
extension=$module.so
END
        ++$ret;
    }

    return $ret;
}

1;
