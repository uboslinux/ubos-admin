#!/usr/bin/perl
#
# Save the Site JSONs to the Staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::StaffCallbacks::SaveSitesJson;

use JSON;
use UBOS::Host;
use UBOS::HostStatus;
use UBOS::Logging;
use UBOS::Utils;

##
# Reading-from-Staff callback.
# $staffRootDir the root directory of the Staff
# $isActualStaffDevice: if true, this is a physical staff, not a cloud/virtual directory
# return: number of errors
sub performAtLoad {
    my $staffRootDir        = shift;
    my $isActualStaffDevice = shift;

    trace( 'SaveSitesJson::performAtLoad', $staffRootDir, $isActualStaffDevice );

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

    trace( 'SaveSitesJson::performAtSave', $staffRootDir, $isActualStaffDevice );

    return saveSitesJson( $staffRootDir );
}

##
# Save the Sites JSON to the Staff.
# $staffRootDir the root directory of the Staff
# return: number of errors
sub saveSitesJson {
    my $staffRootDir = shift;

    my $sites   = UBOS::Host::sites();
    my $hostId  = UBOS::HostStatus::hostId();
    my $infoDir = "flock/$hostId/device-info";

    my $sitesJson = {};
    foreach my $siteId ( keys %$sites ) {
        my $site     = $sites->{$siteId};
        my $siteJson = $site->siteJson;

        # Mark private customizationpoints so the Staff HTML can render them differently
        foreach my $appConfig ( @{$site->appConfigs} ) {
            my $custPoints = $appConfig->customizationPoints();

            my $appConfigJson = undef;
            foreach my $appConfigJsonI ( @{$siteJson->{appconfigs}} ) {
                if( $appConfigJsonI->{appconfigid} eq $appConfig->appConfigId ) {
                    $appConfigJson = $appConfigJsonI;
                    last;
                }
            }
            unless( $appConfigJson ) {
                warning( 'Failed to find AppConfiguration JSON', $appConfig, $siteJson );
                next;
            }

            if( $custPoints ) {
                foreach my $installableName ( keys %$custPoints ) {
                    foreach my $custPointName ( keys %{$custPoints->{$installableName}} ) {
                        my $custPointDef = $appConfig->customizationPointDefinition( $installableName, $custPointName );
                        if( exists( $custPointDef->{private} ) && $custPointDef->{private} ) {
                            $appConfigJson->{customizationpoints}->{$installableName}->{$custPointName}->{private} = JSON::true;
                        }
                        if( exists( $custPointDef->{internal} ) && $custPointDef->{internal} ) {
                            $appConfigJson->{customizationpoints}->{$installableName}->{$custPointName}->{internal} = JSON::true;
                        }
                    }
                }
            }
        }

        $sitesJson->{$siteId} = $siteJson;
    }

    unless( -d "$staffRootDir/$infoDir" ) {
        UBOS::Utils::mkdirDashP( "$staffRootDir/$infoDir" );
    }
    UBOS::Utils::writeJsonToFile( "$staffRootDir/$infoDir/sites.json", $sitesJson );

    return 0;
}

1;
