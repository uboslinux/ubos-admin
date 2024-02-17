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
use HTTP::Request;
use JSON;
use LWP::UserAgent;
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
    my @lines = grep { /^http/ } split( "\n", $siteProxiesContent );

    my $lwp = LWP::UserAgent->new;
    # support self-signed certificates. We are only talking to ourselves
    # so this does not reduce security; everything from the outside world
    # is unaffected by this
    $lwp->ssl_opts(
        SSL_verify_mode => 0,
        verify_hostname => 0
    );

    foreach my $line ( @lines ) {
        my @words = split( " +", $line );

        my $fullUrl = shift @words;
        if( $args ) {
            $fullUrl .= index( $fullUrl, '?' ) >= 0 ? "&$args" : "?$args";
        }

        # Need to set JSON content-type
        my $req = HTTP::Request->new( 'GET', $fullUrl );
        $req->header( 'Content-Type' => 'application/json' );
        foreach my $word ( @words ) {
            my( $name, $value ) = split( '=', $word );
            if( $name && $value ) {
                $req->header( $name => $value );
            }
        }

        my $response = $lwp->request( $req );
        unless( $response->is_success ) {
            # something may be temporarily unavailable
            next;
        }

        my $foundJson = UBOS::Utils::readJsonFromString( $response->decoded_content );

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
