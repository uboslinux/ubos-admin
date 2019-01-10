#!/usr/bin/perl
#
# Command that displays information contained in a backup.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
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
use UBOS::Terminal;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $json          = 0;
    my $detail        = 0;
    my $brief         = 0;
    my $idsOnly       = 0;
    my $in            = undef;
    my $url           = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'         => \$verbose,
            'logConfig=s'      => \$logConfigFile,
            'debug'            => \$debug,
            'json'             => \$json,
            'detail'           => \$detail,
            'brief'            => \$brief,
            'ids-only|idsonly' => \$idsOnly,
            'in=s'             => \$in,
            'url=s'            => \$url );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( $json && ( $detail || $brief || $idsOnly ))
        || ( $detail && $brief )
        || ( $brief && $idsOnly )
        || ( $idsOnly && $detail )
        || @args
        || ( !$in && !$url )
        || ( $in && $url )
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $file;
    my $tmpFile;
    if( $in ) {
        unless( -r $in ) {
            fatal( 'Cannot read file', $in );
        }
        $file = $in;
    } else {
        my $tmpDir = UBOS::Host::vars()->getResolve( 'host.tmp', '/tmp' );
        $tmpFile = File::Temp->new( DIR => $tmpDir, UNLINK => 1 );
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

    my $jsonOutput;
    if( $json ) {
        $jsonOutput = {};
        $jsonOutput->{'type'}       = $backup->backupType;
        $jsonOutput->{'created'}    = $backup->startTimeString;
        $jsonOutput->{'sites'}      = {};
        $jsonOutput->{'appconfigs'} = {};

    } elsif( !$brief ) {
        colPrint( "Type:    " . $backup->backupType      . "\n" );
        colPrint( "Created: " . $backup->startTimeString . "\n" );
    }

    my $sites      = $backup->sites();
    my $appConfigs = $backup->appConfigs();
    my $seenAppConfigIds = {};

    foreach my $siteId ( sort keys %$sites ) {
        if( $json ) {
            $jsonOutput->{'sites'}->{$siteId} = $sites->{$siteId}->siteJson();

        } elsif( $idsOnly ) {
            foreach my $siteId ( sort keys %$sites ) {
                $sites->{$siteId}->printSiteId();
            }
        } elsif( $brief ) {
            foreach my $siteId ( sort keys %$sites ) {
                $sites->{$siteId}->printBrief();
            }
        } elsif( $detail ) {
            foreach my $siteId ( sort keys %$sites ) {
                $sites->{$siteId}->printDetail();
            }
        } else {
            foreach my $siteId ( sort keys %$sites ) {
                $sites->{$siteId}->print();
            }
        }

        map { $seenAppConfigIds->{ $_->appConfigId } = 1; } @{ $sites->{$siteId}->appConfigs };
    }

    my @unattachedAppConfigIds = sort grep { !$seenAppConfigIds->{$_} } keys %$appConfigs;
    if( @unattachedAppConfigIds ) {
        if( $json ) {
            foreach my $appConfigId ( @unattachedAppConfigIds ) {
                $jsonOutput->{'appconfigs'}->{$appConfigId} = $appConfigs->{$appConfigId}->appConfigurationJson();
            }
        } else {
            if( $brief ) {
                foreach my $appConfigId ( @unattachedAppConfigIds ) {
                    $appConfigs->{$appConfigId}->printAppConfigId();
                }

            } else {
                colPrint( "=== Unattached AppConfigurations ===\n" );

                foreach my $appConfigId ( @unattachedAppConfigIds ) {
                    $appConfigs->{$appConfigId}->print();
                }
            }
        }
    }
    if( $json ) {
        UBOS::Utils::writeJsonToStdout( $jsonOutput );
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Display information about a UBOS backup file.
SSS
        'cmds' => {
            <<SSS => <<HHH,
    --in <backupfile>
SSS
    Display information about the local backupfile <backupfile>.
HHH
            <<SSS => <<HHH,
   --url <backupurl>
SSS
    Retrieve the backup file from URL <backupurl>, and display
    information about the backup contained in the retrieved file.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--json' => <<HHH,
    Use JSON as the output format, instead of human-readable text.
HHH
            '--detail' => <<HHH,
    Show more detail.
HHH
            '--brief' => <<HHH,
    Show less detail.
HHH
            '--ids-only' => <<HHH
    Show Site and AppConfiguration ids only.
HHH
        }
    };
}

1;
