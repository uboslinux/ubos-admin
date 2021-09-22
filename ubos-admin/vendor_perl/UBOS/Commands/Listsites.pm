#!/usr/bin/perl
#
# Command that lists the currently deployed sites.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Listsites;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::AnyBackup;
use UBOS::Host;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    unless( UBOS::Lock::acquire() ) {
        colPrintError( "$@\n" );
        exit -2;
    }

    my $verbose           = 0;
    my $logConfigFile     = undef;
    my $debug             = undef;
    my $json              = 0;
    my $detail            = 0;
    my $brief             = 0;
    my $idsOnly           = 0;
    my $hostnamesOnly     = 0;
    my $html              = 0;
    my $privateCustPoints = 0;
    my $adminUser         = 0;
    my $withInstallable   = undef;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'                       => \$verbose,
            'logConfig=s'                    => \$logConfigFile,
            'debug'                          => \$debug,
            'json'                           => \$json,
            'details'                        => \$detail,
            'brief'                          => \$brief,
            'ids-only|idsonly'               => \$idsOnly,
            'hostnames-only|hostnamesonly'   => \$hostnamesOnly,
            'html'                           => \$html,
            'privatecustomizationpoints'     => \$privateCustPoints,
            'adminuser'                      => \$adminUser,
            'with-installable=s'             => \$withInstallable );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    my $nDetail = 0;
    if( $detail ) {
        ++$nDetail;
    }
    if( $brief ) {
        ++$nDetail;
    }
    if( $idsOnly ) {
        ++$nDetail;
    }
    if( $hostnamesOnly ) {
        ++$nDetail;
    }
    if(    !$parseOk
        || ( $json && $nDetail )
        || ( $json && $html )
        || ( $json && $privateCustPoints )
        || ( $json && $adminUser )
        || ( $adminUser && $nDetail )
        || ( $html && ( $idsOnly || $hostnamesOnly ))
        || ( $nDetail > 1 )
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $privateCustPoints && $< != 0 ) {
        fatal( 'Must be root to see values of private customizationpoints.' );
    }

    my $sites = UBOS::Host::sites();
    if( $withInstallable ) {
        $sites = _filterByInstallable( $withInstallable, $sites );
    }

    if( $json ) {
        my $sitesJson = {};
        foreach my $siteId ( keys %$sites ) {
            $sitesJson->{$siteId} = $sites->{$siteId}->siteJson;
        }
        UBOS::Utils::writeJsonToStdout( $sitesJson );

    } elsif( $html ) {
        print( <<HTML );
<!DOCTYPE html>
<html lang="en">
 <head>
  <title>Sites</title>
 </head>
 <body>
  <h1>Sites</h1>
HTML
        if( keys %$sites ) {
            print( <<HTML );
  <ul>
HTML
            foreach my $siteId ( sort keys %$sites ) {
                print( <<HTML );
   <li>
HTML
                if( $detail ) {
                    $sites->{$siteId}->printHtmlDetail( $privateCustPoints );
                } elsif( $brief ) {
                    $sites->{$siteId}->printHtmlBrief();
                } else {
                    $sites->{$siteId}->printHtml( $privateCustPoints );
                }
                print( <<HTML );
   </li>
HTML
            }
            print( <<HTML );
  </ul>
HTML
        } else {
            print( <<HTML );
  <p>No sites</p>
HTML
        }
        print( <<HTML );
 </body>
</html>
HTML


    } elsif( $detail ) {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->printDetail( $privateCustPoints );
        }
    } elsif( $brief ) {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->printBrief();
        }
    } elsif( $idsOnly ) {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->printSiteId();
            foreach my $appConfig ( sort @{$sites->{$siteId}->appConfigs()} ) {
                print( '    ' );
                $appConfig->printAppConfigId();
            }
        }
    } elsif( $hostnamesOnly ) {
        print join( '', map { "$_\n" } sort map { $_->hostname() } values %$sites );

    } elsif( $adminUser ) {
        foreach my $siteId ( sort keys %$sites ) {
            print( 'Site: ' . $sites->{$siteId}->hostname() . "\n" );
            $sites->{$siteId}->printAdminUser( 1 );
        }

    } else {
        foreach my $siteId ( sort keys %$sites ) {
            $sites->{$siteId}->print( $privateCustPoints );
        }
    }

    return 1;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Show information about the sites currently deployed on this device.
SSS
        'detail' => <<DDD,
    If invoked as root, more information may be shown than when invoked
    as a different user (e.g. credentials, keys, values for
    customization points marked as "private").
DDD
        'cmds' => {
            '' => <<HHH
    Show information about the sites currently deployed on this device.
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
            '--ids-only' => <<HHH,
    Show Site and AppConfiguration ids only.
HHH
            '--hostnames-only' => <<HHH,
    Show the hostnames only.
HHH
            '--html' => <<HHH,
    Show in HTML format.
HHH
            '--privatecustomizationpoints' => <<HHH,
    Do not mask the values for private customizationpoints.
HHH
            '--adminuser' => <<HHH,
    Show information about the Site administrator.
HHH
            '--with-installable <installable>' => <<HHH
    Only list sites that run app or accessory <installable>.
HHH
        }
    };
}

###
# Helper method to filter a hash of Sites by the existence of an App or
# Accessory at a Site.
# $packageName: the identifier of the App or Accessory to filter by
# $sites: the sites
# return: filtered sites
sub _filterByInstallable {
    my $packageName = shift;
    my $sites       = shift;

    my %ret = ();

    foreach my $site ( values %$sites ) {
        my $found = 0;

        MIDDLE: foreach my $appConfig ( @{$site->appConfigs} ) {
            foreach my $installable ( $appConfig->installables() ) {
                if( $packageName eq $installable->packageName() ) {
                    $found = 1;
                    last MIDDLE;
                }
            }
        }

        if( $found ) {
            $ret{$site->siteId} = $site;
        }
    }

    return \%ret;
}
1;
