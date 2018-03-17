#!/usr/bin/perl
#
# Tomcat8 abstraction.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Tomcat8;

use UBOS::Logging;

my $mainServerXmlFile    = '/etc/tomcat8/server.xml';
my $ourServerXmlTemplate = '/etc/tomcat8/server.xml.tmpl';

my $running = 0;

##
# Ensure that Tomcat8 is running.
sub ensureRunning {

    trace( 'Tomcat8::ensureRunning' );

    if( $running ) {
        return 1;
    }

    if( UBOS::Host::ensurePackages( [ 'tomcat8', 'tomcat-native' ] ) < 0 ) {
        warning( $@ );
    }

    my $out;
    my $err;
    debugAndSuspend( 'Check that tomcat8.service is running' );
    UBOS::Utils::myexec( 'systemctl enable tomcat8',  undef, \$out, \$err );
    UBOS::Utils::myexec( 'systemctl restart tomcat8', undef, \$out, \$err );

    $running = 1;

    1;
}

##
# Reload configuration
sub reload {
    ensureRunning();

    debugAndSuspend( 'Reload or restart tomcat8' );
    UBOS::Utils::myexec( 'systemctl reload-or-restart tomcat8' );

    1;
}

##
# Restart configuration
sub restart {
    ensureRunning();

    debugAndSuspend( 'Reload or restart tomcat8' );
    UBOS::Utils::myexec( 'systemctl reload-or-restart tomcat8' );

    1;
}

##
# Update the server.xml file with a new hosts section
# $hostsSection: the section describing the Tomcat virtual hosts
sub updateServerXmlFile {
    my $hostsSection = shift;

    ensureRunning();

    my $content = UBOS::Utils::slurpFile( $ourServerXmlTemplate );
    $content =~ s!INSERT-UBOS-SITES-HERE!$hostsSection!;

    UBOS::Utils::saveFile( $mainServerXmlFile, $content, 0640, 'root', 'tomcat8' );
}

1;
