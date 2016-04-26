#!/usr/bin/perl
#
# Command that displays information contained in a backup.
#
# This file is part of ubos-admin.
# (C) 2012-2016 Indie Computing Corp.
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

package UBOS::Commands::Backupinfo;

use Cwd;
use File::Temp;
use Getopt::Long qw( GetOptionsFromArray );
use Storable qw( dclone );
use UBOS::AnyBackup;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $in            = undef;
    my $url           = undef;
    my $brief         = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'      => \$verbose,
            'logConfig=s'   => \$logConfigFile,
            'in=s'          => \$in,
            'url=s'         => \$url,
            'brief'         => \$brief );

    UBOS::Logging::initialize( 'ubos-admin', 'backupinfo', $verbose, $logConfigFile );

    if(    !$parseOk
        || @args
        || ( !$in && !$url )
        || ( $in && $url )
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation: backupinfo', @_, '(add --help for help)' );
    }

    my $file;
    my $tmpFile;
    if( $in ) {
        unless( -r $in ) {
            fatal( 'Cannot read file', $in );
        }
        $file = $in;
    } else {
        $tmpFile = File::Temp->new( UNLINK => 1 );
        close $tmpFile;
        $file = $tmpFile->filename();

        my $stdout;
        my $stderr;
        if( UBOS::Utils::myexec( "curl -L -v -o '$file' '$url'", undef, \$stdout, \$stderr )) {
            fatal( 'Failed to download', $url );
        }
        if( $stderr =~ m!HTTP/1\.[01] (\d+)! ) {
            my $status = $1;
            unless( $status eq '200' ) {
                fatal( 'Failed to access', $url, 'with status', $status );
            }
        } # else it might have been a protocol other than http
    }

    my $backup = UBOS::AnyBackup->readArchive( $file );
    unless( $backup ) {
        fatal( UBOS::AnyBackup::cannotParseArchiveErrorMessage( $in || $url ));
    }

    unless( $brief ) {
        print "Type:    " . $backup->backupType      . "\n";
        print "Created: " . $backup->startTimeString . "\n";
    }

    my $sites      = $backup->sites();
    my $appConfigs = $backup->appConfigs();
    my $seenAppConfigIds = {};
    
    foreach my $siteId ( sort keys %$sites ) {
        $sites->{$siteId}->print( $brief ? 1 : 2 );

        map { $seenAppConfigIds->{ $_->appConfigId } = 1; } @{ $sites->{$siteId}->appConfigs };
    }

    my @unattachedAppConfigIds = sort grep { !$seenAppConfigIds->{$_} } keys %$appConfigs;
    if( @unattachedAppConfigIds ) {
        print "=== Unattached AppConfigurations ===\n";

        foreach my $appConfigId ( @unattachedAppConfigIds ) {
            $appConfigs->{$appConfigId}->print( $brief ? 1 : 2 );
        }
    }
    
    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--brief] ( --in <backupfile> | --url <backupurl> )
SSS
    Display the content of <backupfile>.
    Alternatively, a URL may be specified from where to retrieve the
    backupfile.
    --brief: only show the site ids.
HHH
    };
}

1;
