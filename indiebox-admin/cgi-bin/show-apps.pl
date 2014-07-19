#!/usr/bin/perl
#
# CGI script to show the apps installed at this site. Typically run
# at the root of the site.
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

use CGI;
use IndieBox::Host;
use IndieBox::Site;

my $siteId = $ENV{'SiteId'};
my $site   = IndieBox::Host::findSiteById( $siteId );
my $q      = new CGI;

if( $site ) {
    my $hostName = $site->hostName;
    print $q->header( -type => 'text/html' );
    print <<HTML;
<html>
 <head>
  <title>Indie Box: Installed Apps</title>
  <link rel="stylesheet" type="text/css" href="/_common/css/default.css" />
  <meta name="ROBOTS" content="NOINDEX, NOFOLLOW" />
 </head>
 <body>
  <div class="page">
   <div class="logo"><a href="http://indiebox.net/"><img src="/_common/images/indiebox-logo-horizontal-142x41.png" /></a></div>
   <div class="content">
    <h1>$hostName</h1>
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
            my $appId       = $appConfig->app->packageName();
            my $appName    = $appConfig->app->name();
            my $appTagline = $appConfig->app->tagline();
            my $context    = $appConfig->context;

            if( defined( $context )) {
                print <<HTML;
     <a class="appconfig" href="$context/" title="$appTagline">
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
    <p>&copy; 2012-2014 Indie Computing Corp. To learn more, visit <a href="http://indiebox.net/">indiebox.net</a>.</p>
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
  <title>Indie Box: 404 Site Not Found</title>
  <link rel="stylesheet" type="text/css" href="/_common/css/default.css" />
  <meta name="ROBOTS" content="NOINDEX, NOFOLLOW" />
 </head>
 <body>
  <div class="page">
   <div class="logo"><a href="http://indiebox.net/"><img src="/_common/images/indiebox-logo-horizontal-142x41.png" /></a></div>
   <div class="content">
    <h1 class="error">404 Site not found</h1>
    <p>A site with siteid $siteId could not be found. Perhaps you want to try again later.</p>
   </div>
   <div class="footer">
    <p>&copy; 2012-2014 Indie Computing Corp. To learn more, visit <a href="http://indiebox.net/">indiebox.net</a>.</p>
   </div>
  </div>
 </body>
</html>
HTML
}

exit 0;
