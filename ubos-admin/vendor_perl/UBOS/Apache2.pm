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

my @minimumApacheModules = qw(
        alias
        authz_core
        authz_host
        cgi
        deflate
        dir
        env
        log_config
        mime mpm_prefork
        rewrite
        setenvif
        unixd ); # always need those
# http2 conflicts with prefork

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
# This is invoked by httpd.service
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

    if( -f $keyFile ) {
        # Upgrade to 2048 bits if needed
        my $regen = 0;
        my $out;
        UBOS::Utils::myexec( "openssl rsa -in '$keyFile' -text -noout", undef, \$out );
        if( $out =~ m!Private-Key:\s*\((\d+)\s*bit! ) {
            my $bits = $1;
            if( $bits < 2048 ) {
                $regen = 1;
            }
        } else {
            $regen = 1;
        }
        if( $regen ) {
            UBOS::Utils::deleteFile( $keyFile, $csrFile, $crtFile );
        }
    }

    unless( -f $keyFile ) {
        debugAndSuspend( 'Generate default Apache TLS key' );
        UBOS::Utils::myexec( "openssl genrsa -out '$keyFile' 2048" );
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
            my $content = UBOS::Utils::slurpFile( "$phpModulesConfDir/$module.ini" );
            my $newContent;
            my $found = 0;
            foreach my $line ( split /\n/, $content ) {
                unless( $found ) {
                    # There are versions with extension=foo and extension=foo.so
                    if( $line =~ m!^\s*extension\s*=\s*$module(\.so)?\s*$! ) {
                        $found = 1;
                    } elsif( $line =~ m!^\s*;\s*extension\s*=\s*$module*(\.so)?\s*$! ) {
                        $line = "extension=$module";
                        $found = 1;
                    }
                }
                $newContent .= $line . "\n";
            }
            if( $newContent ne $content ) {
                UBOS::Utils::saveFile( "$phpModulesConfDir/$module.ini", $newContent );
                ++$ret;
            }
        } else {
            unless( -e "$phpModulesDir/$module.so" ) {
                warning( 'Cannot find PHP module, not activating:', $module );
                next;
            }

            UBOS::Utils::saveFile( "$phpModulesConfDir/$module.ini", <<END );
extension=$module.so
END
            ++$ret;
        }
    }

    return $ret;
}

1;
