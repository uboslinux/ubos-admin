#!/usr/bin/perl
#
# Command that backs up data on this device to a local file.
#
# This file is part of ubos-admin.
# (C) 2012-2015 Indie Computing Corp.
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

package UBOS::Commands::Backup;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::BackupUtils;
use UBOS::Backup::ZipFileBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $out           = undef;
    my @siteIds       = ();
    my @hosts         = ();
    my @appConfigIds  = ();
    my $noTls         = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'out=s',        => \$out,
            'siteid=s'      => \@siteIds,
            'hostname=s'    => \@hosts,
            'appconfigid=s' => \@appConfigIds,
            'notls'         => \$noTls );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if( !$parseOk || @args || !$out || ( $verbose && $logConfigFile ) ) {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    foreach my $host ( @hosts ) {
        my $site = UBOS::Host::findSiteByHostname( $host );
        push @siteIds, $site->siteId;
    }

    # May not be interrupted, bad things may happen if it is
    UBOS::Host::preventInterruptions();

    my $backup = UBOS::Backup::ZipFileBackup->new();
    my $ret = UBOS::BackupUtils::performBackup( $backup, $out, \@siteIds, \@appConfigIds, $noTls );

    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--notls] --siteid <siteid> --out <backupfile>
SSS
    Back up all data from all apps and accessories installed at a currently
    deployed site with siteid to backupfile. More than one siteid may be
    specified.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--notls] --hostname <hostname> --out <backupfile>
SSS
    Back up all data from all apps and accessories installed at a currently
    deployed site with the given hostname to backupfile. More than one hostname may be
    specified.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--notls] --appconfigid <appconfigid> --out <backupfile>
SSS
    Back up all data from the currently deployed app and its accessories at
    AppConfiguration appconfigid to backupfile. More than one appconfigid
    may be specified.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--notls] --out <backupfile>
SSS
    Back up all data from all currently deployed apps and accessories at all
    deployed sites to backupfile.
HHH
    };
}

1;
