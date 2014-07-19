#!/usr/bin/perl
#
# Tomcat7 abstraction.
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

package IndieBox::Tomcat7;

use IndieBox::Logging;

my $mainServerXmlFile    = '/etc/tomcat7/server.xml';
my $ourServerXmlTemplate = '/etc/tomcat7/server-indiebox.xml.tmpl';

##
# Ensure that Tomcat7 is running.
sub ensureRunning {
    trace( 'Tomcat7::ensureRunning' );

    debug( 'Installing tomcat7' );
    
    IndieBox::Host::installPackages( 'tomcat7', 'apr' );

    IndieBox::Utils::myexec( 'systemctl enable tomcat7' );
    IndieBox::Utils::myexec( 'systemctl restart tomcat7' );

    1;
}

##
# Reload configuration
sub reload {
    trace( 'Tomcat7::reload' );

    IndieBox::Utils::myexec( 'systemctl reload-or-restart tomcat7' );

    1;
}

##
# Restart configuration
sub restart {
    trace( 'Tomcat7::reload' );

    IndieBox::Utils::myexec( 'systemctl reload-or-restart tomcat7' );

    1;
}

##
# Update the server.xml file with a new hosts section
# $hostsSection: the section describing the Tomcat virtual hosts
sub updateServerXmlFile {
    my $hostsSection = shift;
    
    trace( 'Tomcat7::updateServerXmlFile' );

    my $content = IndieBox::Utils::slurpFile( $ourServerXmlTemplate );
    $content =~ s!INSERT-INDIE-BOX-SITES-HERE!$hostsSection!;

    IndieBox::Utils::saveFile( $mainServerXmlFile, $content, 0640 );
}

1;
