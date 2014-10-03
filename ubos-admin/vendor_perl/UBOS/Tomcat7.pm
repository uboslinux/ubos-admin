#!/usr/bin/perl
#
# Tomcat7 abstraction.
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

package UBOS::Tomcat7;

use UBOS::Logging;

my $mainServerXmlFile    = '/etc/tomcat7/server.xml';
my $ourServerXmlTemplate = '/etc/tomcat7/server-ubos.xml.tmpl';

##
# Ensure that Tomcat7 is running.
sub ensureRunning {
    UBOS::Host::ensurePackages( 'tomcat7', 'apr' );

    UBOS::Utils::myexec( 'systemctl enable tomcat7' );
    UBOS::Utils::myexec( 'systemctl restart tomcat7' );

    1;
}

##
# Reload configuration
sub reload {
    UBOS::Utils::myexec( 'systemctl reload-or-restart tomcat7' );

    1;
}

##
# Restart configuration
sub restart {
    UBOS::Utils::myexec( 'systemctl reload-or-restart tomcat7' );

    1;
}

##
# Update the server.xml file with a new hosts section
# $hostsSection: the section describing the Tomcat virtual hosts
sub updateServerXmlFile {
    my $hostsSection = shift;
    
    my $content = UBOS::Utils::slurpFile( $ourServerXmlTemplate );
    $content =~ s!INSERT-UBOS-SITES-HERE!$hostsSection!;

    UBOS::Utils::saveFile( $mainServerXmlFile, $content, 0640 );
}

1;
