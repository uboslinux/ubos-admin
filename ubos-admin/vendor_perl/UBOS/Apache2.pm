#!/usr/bin/perl
#
# Apache2 abstraction.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Apache2;

use Fcntl qw( SEEK_END SEEK_SET );
use UBOS::Logging;
use UBOS::Utils;
use Time::HiRes qw( gettimeofday );

my $modsAvailableDir  = '/etc/httpd/mods-available';
my $modsEnabledDir    = '/etc/httpd/mods-enabled';
my $phpModulesDir     = '/usr/lib/php/modules';
my $phpModulesConfDir = '/etc/php/conf.d';

my $logFile  = '/var/log/httpd/error_log';

my @minimumApacheModules = qw( alias authz_core authz_host cgi deflate dir env log_config mime mpm_prefork rewrite setenvif unixd ); # always need those

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
# return: 0: success, 1: timeout or other failure
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

    my $out;
    if( UBOS::Utils::myexec( "systemctl $command httpd.service", undef, \$out, \$out )) {
        error( 'httpd.service', $command, 'failed:', $out );
        if( $out =~ m!is not active, cannot reload! ) {
            if( UBOS::Utils::myexec( "systemctl restart httpd.service", undef, \$out, \$out )) {
                error( 'httpd.service restart failed:', $out );
                return 1;
            }
        } else {
            return 1;
        }
    }

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
            trace( 'Detected Apache restart after ', $delta + $max, 'seconds' );
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
    trace( 'Apache2::ensureConfigFiles' );

    activateApacheModules( @minimumApacheModules );

    # Make sure we have default SSL keys and a self-signed cert

    my $sslDir  = '/etc/httpd/conf';
    my $crtFile = "$sslDir/server.crt";
    my $keyFile = "$sslDir/server.key";
    my $csrFile = "$sslDir/server.csr";

    my $uid = 0;  # avoid overwrite by http
    my $gid = UBOS::Utils::getGid( 'http' );

    unless( -f $keyFile ) {
        debugAndSuspend( 'Generate default Apache TLS key' );
        UBOS::Utils::myexec( "openssl genrsa -out '$keyFile' 1024" );
        chmod 0040, $keyFile;
        chown $uid, $gid, $keyFile;
    }
    unless( -f $crtFile ) {
        debugAndSuspend( 'Generate default Apache TLS certificate' );
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
# return: number of activated modules
sub activateApacheModules {
    my @modules = @_;

    trace( 'Activating Apache modules:', @modules );

    my $ret = 0;
    foreach my $module ( @modules ) {
        if( -e "$modsEnabledDir/$module.load" ) {
            next;
        }
        unless( -e "$modsAvailableDir/$module.load" ) {
            warning( 'Cannot find Apache2 module, not activating:', $module );
            next;
        }

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

    trace( 'Activating PHP modules:', @modules );

    my $ret = 0;
    foreach my $module ( @modules ) {
        if( -e "$phpModulesConfDir/$module.ini" ) {
            next;
        }
        unless( -e "$phpModulesDir/$module.so" ) {
            warning( 'Cannot find PHP module, not activating:', $module );
            next;
        }

        UBOS::Utils::saveFile( "$phpModulesConfDir/$module.ini", <<END );
extension=$module.so
END
        ++$ret;
    }

    return $ret;
}

##
# Save the TLS-related info contained in this Site to the right place, or
# remove it if none.
# $site: the Site
sub updateSiteTls {
    my $site = shift;

    my $group  = $site->vars()->getResolve( 'apache2.gname' );
    my $sslDir = $site->vars()->getResolve( 'apache2.ssldir' );
    my $siteId = $site->siteId();

    _saveOrDeleteTlsData( "$sslDir/$siteId.key",   $site->tlsKey(),    $group );
    _saveOrDeleteTlsData( "$sslDir/$siteId.crt",   $site->tlsCert(),   $group );
    _saveOrDeleteTlsData( "$sslDir/$siteId.cacrt", $site->tlsCaCert(), $group );
}

##
# Helper to save or delete a TLS-related file.
# $file: the file name
# $data: the data to save if it exists
# $group user group that owns the file
sub _saveOrDeleteTlsData {
    my $file  = shift;
    my $data  = shift;
    my $group = shift;

    if( $data ) {
        UBOS::Utils::saveFile( $file, $data, 0440, 'root', $group ); # avoid overwrite by apache
    } elsif( -f $file ) {
        UBOS::Utils::deleteFile( $file );
    }
}

1;
