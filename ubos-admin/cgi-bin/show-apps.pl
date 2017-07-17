#!/usr/bin/perl
#
# CGI script to show the apps installed at this site. Typically run
# at the root of the site.
#
# This file is part of ubos-admin.
# (C) 2012-2017 Indie Computing Corp.
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
    print $q->header( -type => 'text/html' );
    print <<HTML;
<html>
 <head>
  <title>Installed Apps</title>
  <link rel="stylesheet" type="text/css" href="/_common/css/default.css" />
  <meta name="ROBOTS" content="NOINDEX, NOFOLLOW" />
 </head>
 <body>
  <div class="page">
   <div class="logo"><a href="http://ubos.net/"><img src="/_common/images/ubos-logo-128x41.png"/></a></div>
   <div class="content">
    <h1>$hostname</h1>
HTML

    my $appConfigs = $site->appConfigs;
    if( @$appConfigs ) {
        print <<HTML;
    <div class="apps">
HTML
        @$appConfigs    = sort { $a->context cmp $b->context } @$appConfigs; # consistent ordering
        my %apps        = (); # show contexts for duplicate apps
        my $showContext = 0;
        foreach my $appConfig ( @$appConfigs ) {
            my $appId   = $appConfig->app->packageName();
            if( ++$apps{$appId} > 1 ) {
                $showContext = 1;
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
            if( $showContext ) {
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
    <p>&copy; 2017 Indie Computing Corp.<br/>
    UBOS, and the UBOS logo are trademarks or registered trademarks of <a href="http://indiecomputing.com/">Indie Computing Corp.</a></p>
   </div>
  </div>
 </body>
</html>
HTML
} else {
    print $q->header( -type => 'text/html', -status => 404 );
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
    <p>&copy; 2016 Indie Computing Corp.<br/>
    UBOS, and the UBOS logo are trademarks or registered trademarks of <a href="http://indiecomputing.com/">Indie Computing Corp.</a></p>
   </div>
  </div>
 </body>
</html>
HTML
}

exit 0;
