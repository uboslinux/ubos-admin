#!/usr/bin/perl
#
# Write the HTML summary page onto the Staff
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::StaffCallbacks::WriteHtml;

use UBOS::Live::UbosLiveHtmlConstants;
use UBOS::Logging;
use UBOS::Utils;

# name of the file to write
my $htmlFile = 'UBOS-STAFF.html';

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'WriteHtml::performAtLoad', $staffRootDir, $isActualStaffDevice );

    # no op
    return 0;
}

##
# Writing-to-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtSave {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'WriteHtml::performAtSave', $staffRootDir, $isActualStaffDevice );

    unless( $isActualStaffDevice ) {
        return 0;
    }

    my $devicesDir  = "$staffRootDir/flock";
    my $devicesDirs = {};

    if( -d $devicesDir ) {
        if( opendir( DIR, $devicesDir )) {
            while( my $file = readdir( DIR )) {
                if( $file !~ m!^[0-9a-f]+$! ) {
                    next;
                }
                $devicesDirs->{$file} = "$staffRootDir/flock/$file";
            }
            closedir( DIR );
        }
    }

    my $devicesInfo = {};
    foreach my $deviceId ( keys %$devicesDirs ) {
        my $deviceFile   = $devicesDirs->{$deviceId} . '/device-info/device.json';
        my $sitesFile    = $devicesDirs->{$deviceId} . '/device-info/sites.json';
        my $ubosLiveFile = $devicesDirs->{$deviceId} . '/device-info/ubos-live.json';

        my $deviceJson;
        my $sitesJson;
        my $ubosLiveJson;
        if( -r $deviceFile ) {
            $deviceJson = UBOS::Utils::readJsonFromFile( $deviceFile );
        } else {
            $deviceJson = {};
        }
        if( -r $sitesFile ) {
            $sitesJson = UBOS::Utils::readJsonFromFile( $sitesFile );
        } else {
            $sitesJson = {};
        }
        if( -r $ubosLiveFile ) {
            $ubosLiveJson = UBOS::Utils::readJsonFromFile( $ubosLiveFile );
        } else {
            $ubosLiveJson = {};
        }

        my $oldestlastupdated = '';
        if( exists( $deviceJson->{lastupdated} )) {
            $oldestlastupdated = _earlierOf( $oldestlastupdated, $deviceJson->{lastupdated} );
        }
        if( exists( $sitesJson->{lastupdated} )) {
            $oldestlastupdated = _earlierOf( $oldestlastupdated, $sitesJson->{lastupdated} );
        }
        if( exists( $ubosLiveJson->{lastupdated} )) {
            $oldestlastupdated = _earlierOf( $oldestlastupdated, $ubosLiveJson->{lastupdated} );
        }
        $deviceJson->{oldestlastupdated} = $oldestlastupdated;

        $devicesInfo->{$deviceId}->{'device'}      = $deviceJson;
        $devicesInfo->{$deviceId}->{'sites'}       = $sitesJson;
        $devicesInfo->{$deviceId}->{'ubos-live'}   = $ubosLiveJson;
    }

    return writeHtml( $staffRootDir, $devicesInfo );
}

##
# Write the HTML summary.
# $staffRootDir: the root directory of the Staff
# $devicesInfo: info about the devices the Staff knows of
# return: number of errors
sub writeHtml {
    my $staffRootDir = shift;
    my $devicesInfo  = shift;

    my $errors = 0;

    my @deviceJsonList = sort { $b->{lastupdated} cmp $a->{lastupdated} } # Show most recently updated first
                         grep { exists( $_->{hostname} ) } # Skip incomplete info on old Staffs
                         map { $_->{device} } values %$devicesInfo;

    my $html   = <<'HTML';
<!DOCTYPE html>
<html lang="en">
 <head>
  <meta charset="utf-8" />
  <style>
HTML
    $html .= $UBOS::Live::UbosLiveHtmlConstants::css;
    $html .= <<'HTML';
  </style>
  <script>
HTML
    $html .= $UBOS::Live::UbosLiveHtmlConstants::javascript;

    # add the timeUpdated invocations
    $html .= <<'HTML';
function run() {
HTML
    foreach my $deviceJson ( @deviceJsonList ) {
        my $hostId            = $deviceJson->{hostid};
        my $oldestLastUpdated = exists( $deviceJson->{oldestlastupdated} ) ? $deviceJson->{oldestlastupdated} : '';
        my $deviceLastUpdated = exists( $deviceJson->{lastupdated} ) ? $deviceJson->{lastupdated} : $oldestLastUpdated;

        $html .= <<HTML;
    calculateTimeUpdated( '$oldestLastUpdated', 'oldestlastupdated-$hostId' );
    calculateTimeUpdated( '$deviceLastUpdated', 'lastupdated-$hostId' );

HTML

        if( exists( $devicesInfo->{$hostId} ) && exists( $devicesInfo->{$hostId}->{sites} )) {
            my @sites = values %{$devicesInfo->{$hostId}->{sites}};
            foreach my $site ( @sites ) {
                my $siteId          = $site->{siteid};
                my $siteLastUpdated = exists( $site->{lastupdated} ) ? $site->{lastupdated} : '';
        $html .= <<HTML;
    calculateTimeUpdated( '$siteLastUpdated', 'lastupdated-$siteId' );
HTML
            }
        }
    }

    $html .= <<'HTML';
}
  </script>
  <title>UBOS Staff</title>
 </head>
 <body onload="run()">
  <div class="content">
   <div class="staff-icon">
    <a href="https://ubos.net/staff">
HTML
    $html .= $UBOS::Live::UbosLiveHtmlConstants::staffImage . "\n";
    $html .= <<'HTML';
    </a>
   </div>
   <h1>UBOS Staff
       <span style="margin-left: 30px">
        <a href="https://ubos.net/staff">
HTML
    $html .= $UBOS::Live::UbosLiveHtmlConstants::helpImage . "\n";
    $html .= <<'HTML';
        </a>
       </span>
   </h1>
   <p><span class="note">Note: </span>
      If you have updated your device(s) since you last updated this Staff,
      this information may be out of date.</p>
   <div class="devices">
HTML

    foreach my $deviceJson ( @deviceJsonList ) {
        my $hostId      = $deviceJson->{hostid};
        my $hostName    = $deviceJson->{hostname};
        my $arch        = $deviceJson->{arch};
        my $deviceClass = $deviceJson->{deviceclass};

        $html .= <<'HTML';
    <div class="device">
     <div class="managed">
HTML
        if(    exists( $deviceJson->{'ubos-live'} )
            && exists( $deviceJson->{'ubos-live'}->{token} ))
        {
            my $registrationToken = $deviceJson->{'ubos-live'}->{token};
            $html .= <<HTML;
      Not managed by UBOS Live. <a href="https://live.ubos.net/register?token=$registrationToken">Register...</a>
HTML
        } elsif(    exists( $deviceJson->{'ubos-live'} )
                 && exists( $deviceJson->{'ubos-live'}->{managed} )
                 && $deviceJson->{'ubos-live'}->{managed} )
        {
            $html .= <<HTML;
      Managed by UBOS Live. <a href="https://live.ubos.net/device/$hostId">Status...</a>
HTML
        } else {
            $html .= <<'HTML';
      Not managed by UBOS Live.
HTML
        }
        $html .= <<HTML;
     </div>

     <h2>Device: $hostName
        <span id="oldestlastupdated-$hostId" class="hide sidenote"></span>
        <span class="device-details-$hostId-reveal reveal sidenote">
         <a href="javascript:toggle('device-details-$hostId');">Show details</a>
        </span>
        <span class="device-details-$hostId-hide hide sidenote">
         <a href="javascript:toggle('device-details-$hostId');">Hide details</a>
        </span>
     </h2>
     <div id="device-details-$hostId" class="device-details hide">
      <h3>Device details
          <span id="lastupdated-$hostId" class="hide sidenote"></span>
      </h3>
      <dl class="device-details">
       <dt>Arch:</dt>
       <dd>$arch</dd>
       <dt>Device class:</dt>
       <dd>$deviceClass</dd>
       <dt>Host ID:</dt>
       <dd>$hostId</dd>
      </dl>
      <table class="network">
       <thead>
        <tr>
         <th>Network interface</th>
         <th>Status</th>
         <th>Type</th>
         <th>Mac address</th>
         <th>Address family</th>
         <th>Network address</th>
        </tr>
       </thead>
HTML
        my $appIpAddress;
        if( exists( $deviceJson->{nics} )) {
            foreach my $nicName ( sort keys %{$deviceJson->{nics}} ) {
                my $nicInfo = $deviceJson->{nics}->{$nicName};

                my $rowspan = 0;
                if( exists( $nicInfo->{ipv4address} )) {
                    ++$rowspan;
                    if( !$appIpAddress && @{$nicInfo->{ipv4address}} ) {
                        $appIpAddress = $nicInfo->{ipv4address}->[0];
                    }
                }
                if( exists( $nicInfo->{ipv6address} )) {
                    ++$rowspan;
                }
                if( $rowspan > 1 ) {
                    $rowspan = " rowspan=$rowspan";
                } else {
                    $rowspan = '';
                }

                my $nicStatus = _get( $nicInfo, 'operational' );
                my $nicType   = _get( $nicInfo, 'type' );
                my $nicMac    = _get( $nicInfo, 'macaddress' );

                $html .= <<HTML;
       <tr>
        <th$rowspan>$nicName</th>
        <td$rowspan>$nicStatus</td>
        <td$rowspan>$nicType</td>
        <td$rowspan>$nicMac</td>
HTML
                if( exists( $nicInfo->{ipv4address} )) {
                    my $ipv4 = join( '<br>', @{$nicInfo->{ipv4address}} ) || '&nbsp;';
                    $html .= <<HTML;
        <td>IPv4</td>
        <td>$ipv4</td>
HTML
                    if( exists( $nicInfo->{ipv6address} )) {
                        my $ipv6 = join( '<br>', @{$nicInfo->{ipv6address}} ) || '&nbsp;';
                        $html .= <<HTML;
       </tr>
       <tr>
        <td>IPv6</td>
        <td>$ipv6</td>
HTML
                    }
                } else {
                    my $ipv6 = join( '<br>', @{$nicInfo->{ipv6address}} ) || '&nbsp;';
                    $html .= <<HTML;
        <td>IPv6</td>
        <td>$ipv6</td>
HTML
                }

                $html .= <<HTML;
       </tr>
HTML
            }
        }
        $html .= <<HTML;
      </table>
     </div>
     <div class="sites">
HTML
        my @sites;
        if( exists( $devicesInfo->{$hostId} ) && exists( $devicesInfo->{$hostId}->{sites} )) {
            @sites = sort { $a->{hostname} cmp $b->{hostname} } values %{$devicesInfo->{$hostId}->{sites}};
        } else {
            @sites = ();
        }

        foreach my $site ( @sites ) {
            my $siteId         = $site->{siteid};
            my $siteAdminId    = $site->{admin}->{userid};
            my $siteAdminUser  = $site->{admin}->{username};
            my $siteAdminEmail = $site->{admin}->{email};
            my $siteAdminCred  = $site->{admin}->{credential};
            my $hostName       = $site->{hostname};
            my $accessAtHost   = $hostName eq '*' ? $appIpAddress : $hostName;
            my $protocol       = exists( $site->{tls} ) ? 'https' : 'http';

            $html .= <<HTML;
      <div class="site">
       <div id="site-$siteId" class="admin hide">
        <table class="admin">
         <tr>
          <th>Site admin user id:</th>
          <td>$siteAdminId</td>
         </tr>
         <tr>
          <th>Site admin user name:</th>
          <td>$siteAdminUser</td>
         </tr>
         <tr>
          <th>Site admin user password:</th>
          <td>
           <a class="sidenote passwd-copy" href="#" id="site-$siteId-passwd-copy">
HTML
            $html .= $UBOS::Live::UbosLiveHtmlConstants::copyImage . "\n";
            $html .= <<HTML;
           </a>
           <div id="site-$siteId-passwd" class="hide"></div>
           <span class="site-$siteId-passwd-reveal reveal">
            &diams;&diams;&diams;&diams;&diams;&diams;&diams;&diams;
            <a class="sidenote" href="javascript:toggle('site-$siteId-passwd');">Reveal</a>
           </span>
           <span class="site-$siteId-passwd-hide hide">
            <span class="tt" id="site-$siteId-passwd-copy-fromhere">$siteAdminCred</span>
            <a class="sidenote" href="javascript:toggle('site-$siteId-passwd');">Hide</a>
           </span>
          </td>
         </tr>
         <tr>
          <th>Site admin user e-mail:</th>
          <td>$siteAdminEmail</td>
         </tr>
        </table>
       </div>
HTML

            if( $accessAtHost ) {
                $html .= <<HTML;
       <h3>Site: <a href="$protocol://$accessAtHost/">$hostName</a>
HTML
            } else {
                $html .= <<HTML;
       <h3>Site: $hostName
HTML
            }

            $html .= <<HTML;
        <span id="lastupdated-$siteId" class="hide sidenote"></span>
        <span class="site-$siteId-reveal reveal sidenote">
         <a href="javascript:toggle('site-$siteId');">Show details</a>
        </span>
        <span class="site-$siteId-hide hide sidenote">
         <a href="javascript:toggle('site-$siteId');">Hide details</a>
        </span>
       </h3>
HTML
            unless( $accessAtHost ) {
                $html .= <<HTML;
       <p class="note">The UBOS device was disconnected from the network when this information was saved.</p>
HTML
            }
            $html .= <<HTML;
       <p class="site-$siteId-hide hide">Site ID: $siteId</p>
       <div class="appconfigs">
HTML
            if( exists( $site->{appconfigs} ) && @{$site->{appconfigs}} ) {
                # foreach my $appConfig ( sort { $a->{context} cmp $b->{context} } @{$site->{appconfigs}} ) {
                foreach my $appConfig ( @{$site->{appconfigs}} ) {
                    my $appConfigId  = $appConfig->{appconfigid};
                    my $appId        = $appConfig->{appid};
                    my @accessoryIds = exists( $appConfig->{accessoryids} ) ? @{$appConfig->{accessoryids}} : ();
                    my $context      = $appConfig->{context};

                    $html .= <<HTML;
        <dl class="appconfig">
         <dt>
HTML

                    if( defined( $context )) {
                        my $contextName = $context ? $context : 'root of site';

                        if( $accessAtHost ) {
                            $html .= <<HTML;
          App $appId at <a href="$protocol://$accessAtHost$context/">$contextName</a>
HTML
                        } else {
                            $html .= <<HTML;
          App $appId at $contextName
HTML
                        }
                    } else {
                        $html .= <<HTML;
          App $appId (not a web app)
HTML
                    }

                    $html .= <<HTML;
          <span class="appconfig-$appConfigId-reveal reveal sidenote">
           <a href="javascript:toggle('appconfig-$appConfigId');">Show details</a>
          </span>
          <span class="appconfig-$appConfigId-hide hide sidenote">
           <a href="javascript:toggle('appconfig-$appConfigId');">Hide details</a>
          </span>
         </dt>
         <dd id="appconfig-$appConfigId" class="hide">
          <p>App Configuration ID: $appConfigId</p>
          <table class="appconfig">
           <thead>
            <tr>
             <th>App / accessory</th>
             <th>Customization point</th>
             <th>Configured value</th>
            </tr>
           </thead>
HTML
                    my @installableIds = ( $appId );
                    push @installableIds, sort @accessoryIds;
                    foreach my $installableId ( @installableIds ) {

                        my @custPointHtmlRows = (); # Only if we have any do we add it
                        if(    exists( $appConfig->{customizationpoints} )
                            && exists( $appConfig->{customizationpoints}->{$installableId} )
                            && keys %{ $appConfig->{customizationpoints}->{$installableId}} )
                        {
                            foreach my $pointName ( sort keys %{$appConfig->{customizationpoints}->{$installableId}} ) {
                                my $pointValue = _formatValue( $appConfig->{customizationpoints}->{$installableId}->{$pointName} );
                                my $custPointHtml .= <<HTML;
            <td>$pointName</td>
            <td>
HTML
                                if(    exists( $appConfig->{customizationpoints}->{$installableId}->{$pointName}->{private} )
                                    && $appConfig->{customizationpoints}->{$installableId}->{$pointName}->{private} )
                                {
                                    $custPointHtml .= <<HTML;
           <div id="appconfig-$appConfigId-$installableId-$pointName" class="hide"></div>
           <span class="appconfig-$appConfigId-$installableId-$pointName-reveal reveal">
            &diams;&diams;&diams;&diams;&diams;&diams;&diams;&diams;
            <a class="sidenote" href="javascript:toggle('appconfig-$appConfigId-$installableId-$pointName');">Reveal</a>
           </span>
           <span class="appconfig-$appConfigId-$installableId-$pointName-hide hide">
            $pointValue
            <a class="sidenote" href="javascript:toggle('appconfig-$appConfigId-$installableId-$pointName');">Hide</a>
           </span>
HTML
                                } else {
                                    $custPointHtml .= <<HTML;
             $pointValue
HTML
                                }
                                $custPointHtml .= <<HTML;
            </td>
HTML
                                push @custPointHtmlRows, $custPointHtml;
                            }
                        }
                        if( @custPointHtmlRows ) {
                            my $nRows = @custPointHtmlRows;
                            $html .= <<HTML;
           <tr>
            <th rowspan=$nRows>$installableId</th>
HTML
                            my $sep = ' ';
                            foreach my $row ( @custPointHtmlRows ) {
                                $html .= "           $sep$row</tr>\n";
                                $sep = '<tr>';
                            }
                            $html .= <<HTML;
           </tr>

HTML
                        } else {
                            $html .= <<HTML;
           <tr>
            <th>$installableId</th>
            <td colspan="2">&mdash;</td>
           </tr>
HTML
                        }
                    }
                    $html .= <<HTML;
          </table>
         </dd>
        </dl>
HTML
                }
            }
            $html .= <<HTML;
       </div>
      </div>
HTML
        }
        $html .= <<HTML;
     </div>
    </div>
HTML
    }

    $html .= <<HTML;
   <div class="staff">
    <div class="keys">
     <h2>
      SSH Keys
      <span class="keys-reveal sidenote">
       <a href="javascript:toggle('keys');">Show keys</a>
      </span>
      <span class="keys-hide hide sidenote">
       <a href="javascript:toggle('keys');">Hide keys</a>
      </span>
     </h2>
     <div id="keys" class="hide">
      <p class="note">If there is an SSH public key on this Staff,
      a file named <span class="tt">id_rsa.pub</span> will be shown below. If there is also an SSH private
      key, it will be in file <span class="tt">id_rsa</span>. Due to browser limitations, displaying
      it this way is the best we can do.</p>
      <iframe src="shepherd/ssh/"></iframe>
     </div>
    </div>
   </div>

   <div class="staff">
    <div class="wifi">
     <h2>
      WiFi Credentials
      <span class="wifi-reveal sidenote">
       <a href="javascript:toggle('wifi');">Show WiFi credentials</a>
      </span>
      <span class="wifi-hide hide sidenote">
       <a href="javascript:toggle('wifi');">Hide WiFI credentials</a>
      </span>
     </h2>
     <div id="wifi" class="hide">
      <p class="note">If there are WiFi credentials on this Staff,
      so your UBOS device automatically connects to a WiFi network when you boot
      it with this Staff inserted, they will be shown below. Each WiFi network must be
      in a separate file with the extention <span class="tt">.conf</span>. Due to browser
      limitations, displaying them this way is the best we can do.</p>
      <iframe src="wifi/"></iframe>
     </div>
    </div>
   </div>

   <div class="staff">
    <div class="site-templates">
     <h2>
      Site Templates
      <span class="site-templates-reveal sidenote">
       <a href="javascript:toggle('site-templates');">Show site templates</a>
      </span>
      <span class="site-templates-hide hide sidenote">
       <a href="javascript:toggle('site-templates');">Hide site templates</a>
      </span>
     </h2>
     <div id="site-templates" class="hide">
      <p class="note">If there are Site templates on this Staff,
      which will be automatically deployed when you boot your UBOS device with
      this Staff inserted, they will be shown below. Files must end with
      extension <span class="tt">.json</span>. Due to browser limitations,
      displaying them this way is the best we can do.</p>
      <iframe src="site-templates/"></iframe>
     </div>
    </div>
   </div>

   <p>This page was automatically generated by UBOS. To update, reboot your UBOS device
      with the Staff inserted.</p>

   <footer>
    <p>&copy; <a href="http://indiecomputing.com/">Indie Computing Corp.</a>
       <a href="https://ubos.net/legal/">Legal</a>. Need help? Go to the
       <a href="https://forum.ubos.net/">forum.</a>
    </p>
   </footer>
  </div>
  <script>
function handlePasswdCopy( ev ) {
    var elId = ev.target.id + "-fromhere";
    var el   = document.getElementById( elId );

    var range = document.createRange();
    range.selectNodeContents( el );
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange( range );

    var success = false;
    try{
        success = document.execCommand("copy");
    } catch(e){
        success = false;
    }
    if( !success ) {
        alert( "Your browser isn't letting me copy to the clipboard. Please type the password in manually." )
    }
}

var pwCopy = document.body.getElementsByClassName( 'passwd-copy' );
for( i=0; i<pwCopy.length; ++i ) {
    pwCopy[i].addEventListener("click", handlePasswdCopy, false );
}
  </script>
 </body>
</html>
HTML

    unless( UBOS::Utils::saveFile( "$staffRootDir/$htmlFile", $html )) {
        error( 'Failed to write file:', "$staffRootDir/$htmlFile" );
        ++$errors;
    }

    return $errors;
}

# Helper method
sub _get {
    my $base  = shift;
    my $field = shift;

    if( $base && exists( $base->{$field} )) {
        return $base->{$field};
    } else {
        return '';
    }
}

# Helper method
sub _formatValue {
    my $json = shift;

    my $ret;
    if( exists $json->{value} ) {
        $ret = $json->{value};
        if( !$ret ) {
            return '(empty)';
        } elsif( $ret =~ m!^[[:print:]]$! ) {
            return '(binary)';
        } elsif( length( $ret ) > 24 ) {
            $ret = substr( $ret, 0, 21 ) . '...';
        }
    } else {
        $ret = '?';
    }
    return $ret;
}

# Helper method: compare two timestamps and return the earlier one.
sub _earlierOf {
    my $a = shift;
    my $b = shift;

    if( $a ) {
        if( $b ) {
            return ( $a <=> $b ) < 0 ? $a : $b;
        } else {
            return $a;
        }
    } else {
        return $b;
    }
}

1;
