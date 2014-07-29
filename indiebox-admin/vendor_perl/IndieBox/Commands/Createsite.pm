#!/usr/bin/perl
#
# Command that asks the users about the site they want to create, and
# then deploys the site.
#
# Copyright (C) 2013-2014 Indie Box Project http://indieboxproject.org/
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Commands::Createsite;

use Cwd;
use File::Basename;
use Getopt::Long qw( GetOptionsFromArray );
use IndieBox::Host;
use IndieBox::Installable;
use IndieBox::Logging;
use IndieBox::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $dryRun;
    my $parseOk = GetOptionsFromArray(
            \@args,
            'dry-run|n' => \$dryRun );

    if( !$parseOk || @args) {
        fatal( 'Invalid command-line arguments, add --help for help' );
    }

    my $appId = ask( "App to run: ", '^[.-_a-z0-9]+$' );
    IndieBox::Host::installPackages( $appId );

    my $app = new IndieBox::App( $appId );

    my $oldSites     = IndieBox::Host::sites();
    my $existingSite = undef;
    my $hostname     = undef;
    outer: while( 1 ) {
        $hostname = ask( "Hostname for app: ", '^[a-z0-9]([-_a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-_a-z0-9]*[a-z0-9])?)*$' );

        foreach my $oldSite ( values %$oldSites ) {
            if( $oldSite->hostName eq $hostname ) {
                print "There is already a site with hostname $hostname.\n";
                my $yn = ask( "Add app $appId to $hostname? (y/n) " );
                if( $yn !~ m!^y(es)?$!i ) {
                    next outer;
                }
                $existingSite = $oldSite;
            }
        }
        last;
    }

    my $defaultContext = $app->defaultContext;
    my $context        = undef;
    if( $defaultContext ) {
        print "App $appId suggests context path " . $app->defaultContext . "\n";
        my $existingAppConfig;
        if( $existingSite ) {
            $existingAppConfig = $existingSite->appConfigAtContext( $defaultContext );
        }
        if( $existingAppConfig ) {
            print 'But: app ' . $existingAppConfig->app->packageName . " already runs at $defaultContext. You need to choose something different.\n";
        }
        while( 1 ) {
            $context = ask( 'Enter context path: ' );

            if( IndieBox::AppConfiguration::isValidContext( $context )) {
                if( $existingSite ) {
                    my $error = $existingSite->mayContextBeAdded( $context );
                    if( $error ) {
                        print $error . " You need to choose something different.\n";
                    } else {
						last;
					}
                } else {
					last;
				}
            } else {
                print "Invalid context path. A valid context path is either empty or starts with a slash; no spaces\n";
            }
        }
    }

    my $accessories = ask( "Any accessories for $appId? Enter list: " );
    $accessories =~ s!^\s+!!;
    $accessories =~ s!\s+$!!;
    my @accs = ();
    foreach my $accId ( split( /\s+,?\s*/, $accessories )) {
        IndieBox::Host::installPackages( $accId );
        my $acc = new IndieBox::Accessory( $accId );

        push @accs, $acc;
    }

    my $custPointValues = {};
    foreach my $installable ( $app, @accs ) {
        my $custPoints      = $installable->customizationPoints;
        if( $custPoints ) {
            my $knownCustomizationPointTypes = $IndieBox::Installable::knownCustomizationPointTypes;

            while( my( $custPointName, $custPointDef ) = each( %$custPoints )) {
                # only ask for required values
                unless( $custPointDef->{required} ) {
                    next;
                }
                my $value = ask( (( $installable == $app ) ? 'App' : 'Accessory' ) . ' ' . $installable->packageName . " requires a value for $custPointName: " );

                my $custPointValidation = $knownCustomizationPointTypes->{ $custPointDef->{type}};
                unless( $custPointValidation->{valuecheck}->( $value )) {
                    fatal(  $custPointValidation->{valuecheckerror} );
                }
                $custPointValues->{$installable->packageName}->{$custPointName} = $value;
            }
        }
    }

    my $newSiteJsonString;
    
    my $siteId;
    my $appConfigId;
    my $adminUserId;
    my $adminUserName;
    my $adminCredential;
    my $adminEmail;

    if( $existingSite ) {
        my $json = $existingSite->{json};

        $siteId      = $json->{siteid};
        $appConfigId = 'a' . IndieBox::Utils::randomHex( 40 );

        $adminUserId     = $json->{admin}->{userid};
        $adminUserName   = $json->{admin}->{username};
        $adminCredential = $json->{admin}->{credential};
        $adminEmail      = $json->{admin}->{email};

    } else {
        $siteId      = 's' . IndieBox::Utils::randomHex( 40 );
        $appConfigId = 'a' . IndieBox::Utils::randomHex( 40 );

        $adminUserId     = ask( 'Site admin user id (e.g. admin): ', '^[a-z0-9]+$' );
        $adminUserName   = ask( 'Site admin user name (e.g. John Doe): ' );
        $adminCredential = ask( 'Site admin user password (e.g. s3cr3t): ', '^\S+$' );
        $adminEmail      = ask( 'Site admin user e-mail (e.g. foo@bar.com): ', '^[a-z0-9._%+-]+@[a-z0-9.-]*[a-z]$' );
    }

    $newSiteJsonString = <<JSON;
{
    "siteid" : "$siteId",
    "hostname" : "$hostname",

JSON
    if( $existingSite && $existingSite->{json}->{ssl} ) {
        $newSiteJsonString .= IndieBox::Utils::writeJsonToString( $existingSite->{json}->{ssl} );
    }
    $newSiteJsonString .= <<JSON;
    "admin" : {
        "userid" : "$adminUserId",
        "username" : "$adminUserName",
        "credential" : "$adminCredential",
        "email" : "$adminEmail"
    },

    "appconfigs" : [
JSON
    if( $existingSite ) {
        foreach my $appConfig ( @{$existingSite->appConfigs} ) {
            my $toAdd = IndieBox::Utils::writeJsonToString( $appConfig->{json} );
            $toAdd =~ s!\s+$!!;
            $toAdd =~ s!^!        !mg;
            $newSiteJsonString .= "\n" . $toAdd;
        }
        $newSiteJsonString .= ",\n";
    }
    $newSiteJsonString .= <<JSON;
        {
            "appconfigid" : "$appConfigId",
            "appid" : "$appId",
JSON

    if( defined( $context )) {
        $newSiteJsonString .= <<JSON;
            "context" : "$context",
JSON
    }
    if( @accs ) {
        $newSiteJsonString .= <<JSON;
            "accessories" : [
JSON
        $newSiteJsonString .= join( '', map { '                ' . $_->packageName . ",\n" } @accs );
            
        $newSiteJsonString .= <<JSON;
            ],
JSON
    }
    if( %$custPointValues ) {
        $newSiteJsonString .= <<JSON;
            "customizationpoints" : {
JSON
        while( my( $packageName, $packageInfo ) = each %$custPointValues ) {
            $newSiteJsonString .= <<JSON;
                "$packageName" : {
JSON
            while( my( $name, $value ) = each %$packageInfo ) {
                $newSiteJsonString .= <<JSON;
                    "$name" : {
                        "value" : "$value"
                    }
JSON
            }
            $newSiteJsonString .= <<JSON;
                },
JSON
        }
        $newSiteJsonString .= <<JSON;
            }
JSON
    }

    $newSiteJsonString .= <<JSON;
        }
    ]
}
JSON

    if( $dryRun ) {
        print $newSiteJsonString;

    } else {
        my $newSiteJson = IndieBox::Utils::readJsonFromString( $newSiteJsonString );

        my $newSite = new IndieBox::Site( $newSiteJson );

        my $prerequisites = {};
        $newSite->addDependenciesToPrerequisites( $prerequisites );
        IndieBox::Host::installPackages( $prerequisites );

        $newSite->checkDeployable();

        # May not be interrupted, bad things may happen if it is
        IndieBox::Host::preventInterruptions();

        debug( 'Setting up placeholder sites' );

        my $suspendTriggers = {};
        $newSite->setupPlaceholder( $suspendTriggers ); # show "coming soon"
        IndieBox::Host::executeTriggers( $suspendTriggers );

        $newSite->deploy();

        debug( 'Resuming sites' );

        my $resumeTriggers = {};
        $newSite->resume( $resumeTriggers ); # remove "upgrade in progress page"
        IndieBox::Host::executeTriggers( $resumeTriggers );

        debug( 'Running installers/upgraders' );

        foreach my $appConfig ( @{$newSite->appConfigs} ) {
            $appConfig->runInstaller();
        }

        print "Installed site $siteId at http://$hostname/\n";
    }
    return 1;
}

##
# Ask the user a question
# $q: the question text
# $dontTrim: if false, trim whitespace
sub ask {
    my $q        = shift;
    my $regex    = shift || '.?';
    my $dontTrim = shift || 0;

    my $ret;
    while( 1 ) {
        print $q;
        $ret = <STDIN>;
        unless( $dontTrim ) {
            $ret =~ s!\s+$!!;
            $ret =~ s!^\s+!!;
        }
        if( $ret =~ $regex ) {
            last;
        } else {
            print "(input not valid: regex is $regex)\n";
        }
    }
    return $ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH
SSS
    Interactively create a new site.
HHH
    };
}

1;
