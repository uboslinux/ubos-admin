#!/usr/bin/perl
#
# CGI script to merge webfinger content from one or more proxy URLs.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;
use utf8;

use CGI;
use JSON;
use LWP::Simple;
use UBOS::Utils;

my $q    = new CGI;
my $utf8 = 'utf-8';
$q->charset( $utf8 );

my $qUrl = $q->url( -query => 1 );
my $qm   = index( $qUrl, '?' );
my $args = $qm >= 0 ? substr( $qUrl, $qm+1 ) : '';

my $siteId          = $ENV{'SiteId'};
my $siteProxiesFile = "/ubos/http/webfinger-proxies/$siteId";
my $jsonResponse    = undef;

if( -e $siteProxiesFile ) {
    my $siteProxiesContent = UBOS::Utils::slurpFile( $siteProxiesFile );
    my @urls = grep { /^http/ } split( "\n", $siteProxiesContent );

    foreach my $url ( @urls ) {
        my $fullUrl = index( $url, '?' ) >= 0 ? "$url&$args" : "$url?$args";
        my $found   = get( $fullUrl );
        unless( $found ) {
            # something may be temporarily unavailable
            next;
        }

        my $foundJson = UBOS::Utils::readJsonFromString( $found );

        if( $jsonResponse ) {
            # merge
            if( exists( $foundJson->{subject} )) {
                if( exists( $jsonResponse->{subject} )) {
                    if( $foundJson->{subject} ne $jsonResponse->{subject} ) {
                        print STDERR "merge-webfingers.pl: subject different: $siteId " . $foundJson->{subject} . ' ' . $jsonResponse->{subject} . "\n";
                    }
                } else {
                    $jsonResponse->{subject} = $foundJson->{subject};
                }
            }
            foreach my $arrayKey ( qw( aliases links )) {
                if( exists( $foundJson->{$arrayKey} )) {
                    if( exists( $jsonResponse->{$arrayKey} )) {
                        push @{$jsonResponse->{$arrayKey}}, @{$foundJson->{$arrayKey}};
                    } else {
                        $jsonResponse->{$arrayKey} = $foundJson->{$arrayKey};
                    }
                }
            }
            if( exists( $foundJson->{properties} )) {
                if( exists( $jsonResponse->{properties} )) {
                    foreach my $propertyKey ( keys %{$foundJson->{properties}} ) {
                        if( exists( $jsonResponse->{properties}->{$propertyKey} )) {
                            print STDERR "merge-webfingers.pl: conflicting properties: $siteId " . $foundJson->{subject} . ' ' . $propertyKey . "\n";
                        } else {
                            $jsonResponse->{properties}->{$propertyKey} = $foundJson->{properties}->{$propertyKey};
                        }
                    }

                } else {
                    $jsonResponse->{properties} = $foundJson->{properties};
                }
            }

        } else {
            # first one
            $jsonResponse = $foundJson;
        }
    }
}

if( $jsonResponse ) {
    print $q->header( -status => 200, -type => 'application/json', -charset => $utf8 );
    UBOS::Utils::writeJsonToStdout( $jsonResponse );
} else {
    print $q->header( -status => 404 );
}

1;
