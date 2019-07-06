#!/usr/bin/perl
#
# CGI script to show the apps installed at this site. Typically run
# at the root of the site.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;
use utf8;

use CGI;
use UBOS::Host;
use UBOS::Site;

my $siteId = $ENV{'SiteId'};
my $site   = UBOS::Host::findSiteById( $siteId );
my $q      = new CGI;
my $locale = 'en_US'; # for now

if( $site ) {
    my $hostname = $site->hostname;
    if( '*' eq $hostname ) {
        $hostname = $q->virtual_host() || $q->server_name();
    }
    print $q->header( -type => 'text/html', -charset=>'utf-8' );
    print <<HTML;
<html>
 <head>
  <title>Installed Apps</title>
  <link rel="stylesheet" type="text/css" href="/_common/css/default.css" />
  <meta name="ROBOTS" content="NOINDEX, NOFOLLOW" />
 </head>
 <body>
  <div class="page">
   <div class="logo"><a href="http://ubos.net/"><img src="/_common/images/ubos-logo.png"/></a></div>
   <div class="content">
    <h1>$hostname</h1>
HTML

    my $appConfigs = $site->appConfigs;
    if( @$appConfigs ) {
        print <<HTML;
    <div class="apps">
HTML
        @$appConfigs = sort {
            ( defined( $a->context ) && defined( $b->context ))
            ? ( $a->context cmp $b->context )
            : ( $a->app->packageName() cmp $b->app->packageName() )
        } @$appConfigs; # consistent ordering

        my %apps        = (); # show contexts for duplicate apps
        my $showContext = 0;
        foreach my $appConfig ( @$appConfigs ) {
            my $context = $appConfig->context;
            if( defined( $context )) {
                my $appId = $appConfig->app->packageName();
                if( ++$apps{$appId} > 1 ) {
                    $showContext = 1;
                }
            }
        }

        foreach my $appConfig ( @$appConfigs ) {
            my $appId      = $appConfig->app->packageName();
            my $appName    = $appConfig->app->name( $locale );
            my $appTagline = $appConfig->app->tagline( $locale );
            my $context    = $appConfig->context;

            if( defined( $context )) {
                if( $appTagline ) {
                    print <<HTML;
     <a class="appconfig" href="$context/" title="$appTagline">
HTML
                } else {
                    print <<HTML;
     <a class="appconfig" href="$context/">
HTML
                }
            } else {
                # need equivalent element to attach CSS to
                print <<HTML;
     <span>
HTML
            }
            print <<HTML;
      <div class="app">
       <div class="icon" style="background-image: url(/_appicons/$appId/72x72.png)"></div>
       <p class="name">$appName</p>
HTML
            if( defined( $context ) && $showContext ) {
                print <<HTML;
       <p class="context">$context</p>
HTML
            }
            print <<HTML;
      </div>
HTML
            if( defined( $context )) {
                print <<HTML;
     </a>
HTML
            } else {
                print <<HTML;
     </span>
HTML
            }
        }
        print <<HTML;
    </div>
HTML
    } else {
        print <<HTML;
    <p>No apps have been deployed to this site.</p>
HTML
    }

    print <<HTML;
   </div>
   <div class="footer">
    <p>&copy; Indie Computing Corp.<br/>
    UBOS, and the UBOS logo are trademarks or registered trademarks of <a href="http://indiecomputing.com/">Indie Computing Corp.</a></p>
   </div>
  </div>
 </body>
</html>
HTML
} else {
    print $q->header( -type => 'text/html', -status => 404, -charset=>'utf-8' );
    print <<HTML;
<html>
 <head>
  <title>404 Site Not Found</title>
  <link rel="stylesheet" type="text/css" href="/_common/css/default.css" />
  <meta name="ROBOTS" content="NOINDEX, NOFOLLOW" />
 </head>
 <body>
  <div class="page">
   <div class="logo"><a href="http://ubos.net/"><img src="/_common/images/ubos-logo-128x41.png" /></a></div>
   <div class="content">
    <h1 class="error">404 Site not found</h1>
    <p>A site with siteid $siteId could not be found. Perhaps you want to try again later.</p>
   </div>
   <div class="footer">
    <p>&copy; Indie Computing Corp.<br/>
    UBOS, and the UBOS logo are trademarks or registered trademarks of <a href="http://indiecomputing.com/">Indie Computing Corp.</a></p>
   </div>
  </div>
 </body>
</html>
HTML
}

exit 0;
