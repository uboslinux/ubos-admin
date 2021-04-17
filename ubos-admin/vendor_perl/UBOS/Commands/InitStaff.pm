#!/usr/bin/perl
#
# Command that initializes a staff device according to the UBOS staff conventions.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::InitStaff;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::StaffManager;
use UBOS::Terminal;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    unless( UBOS::Lock::acquire() ) {
        colPrintError( "$@\n" );
        exit -2;
    }

    my $verbose           = 0;
    my $logConfigFile     = undef;
    my $debug             = undef;
    my $format            = undef;
    my $label             = undef;
    my $noUbosLive        = undef;
    my $shepherdKey       = undef;
    my @wifiStrings       = ();
    my @siteTemplateFiles = ();

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'                 => \$verbose,
            'logConfig=s'              => \$logConfigFile,
            'debug'                    => \$debug,
            'format'                   => \$format,
            'no-ubos-live'             => \$noUbosLive,
            'label'                    => \$label,
            'add-shepherd-key=s'       => \$shepherdKey,
            'add-wifi=s'               => \@wifiStrings,
            'add-site-template-file=s' => \@siteTemplateFiles );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( @args > 1 )
        || ( $format && !@args )
        || ( $format && $label )
        || ( $label && !@args )
        || ( $verbose && $logConfigFile ) )
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $device = @args ? $args[0] : undef;
    my $errors = 0;

    my $wifis         = {}; # SSID                       => hash of parameters
    my $siteTemplates = {}; # filename without extension => Site template JSON

    if( $shepherdKey && $shepherdKey !~ m!^ssh-\S+ ! ) {
        fatal( 'This does not look like a valid ssh public key. Perhaps you need to put it in quotes? Invalid key starts with:',
               length( $shepherdKey ) > 8 ? ( substr( $shepherdKey, 0, 8 ) . '...' ) : $shepherdKey );
    }
    foreach my $siteTemplateFile ( @siteTemplateFiles ) {
        # make sure they exist and are valid
        unless( -r $siteTemplateFile ) {
            fatal( 'Cannot read file:', $siteTemplateFile );
        }

        my $shortsiteTemplateName = $siteTemplateFile;
        $shortsiteTemplateName =~ s!^.*/!!;
        $shortsiteTemplateName =~ s!\..*!!;

        if( exists( $siteTemplates->{$shortsiteTemplateName} )) {
            fatal( 'Already have a site template with short name:', $shortsiteTemplateName );
        }

        my $json = UBOS::Utils::readJsonFromFile( $siteTemplateFile );
        unless( $json ) {
            fatal( 'When reading file', $siteTemplateFile, ':', $@ );
        }

        my $site = UBOS::Site->new( $json, 1 );
        unless( $site ) {
            fatal( $@ );
        }
        $siteTemplates->{$shortsiteTemplateName} = UBOS::Utils::readJsonFromFile( $siteTemplateFile );
            # write the original JSON, not the one modified by UBOS::Site
    }

    foreach my $wifiString ( @wifiStrings ) {
        my $w = _parseWifiString( $wifiString );
        if( exists( $wifis->{$w->{ssid}} )) {
            fatal( 'WiFi string specified more than once for ssid:', $w->{ssid} );
        }
        $wifis->{$w->{ssid}} = $w;
    }

    if( $device ) {
        if( $format ) {
            $device = UBOS::StaffManager::formatStaffDevice( $device );
        } else {
            $device = UBOS::StaffManager::checkStaffDevice( $device, $label );
        }
    } else {
        $device = UBOS::StaffManager::guessStaffDevice();
    }
    unless( $device ) {
        fatal( $@ );
    }

    $errors += UBOS::StaffManager::labelDeviceAsStaff( $device );

    my $targetDir;
    $errors += UBOS::StaffManager::mountDevice( $device, \$targetDir );
    $errors += UBOS::StaffManager::initDirectoryAsStaff( $targetDir->dirname(), $shepherdKey, $wifis, $siteTemplates, $noUbosLive );
    $errors += UBOS::StaffManager::unmountDevice( $device, $targetDir );

    return $errors ? 0 : 1;
}

##
# Helper method to parse a wifi String
# $wifiString: the string
# return: hash of the content of the strin
sub _parseWifiString {
    my $wifiString = shift;

    my $currentWifi        = {};
    my $currentKey         = '';
    my $currentValue       = undef;
    my $currentValueEscape = undef;

    for( my $i=0 ; $i<length( $wifiString ) ; ++$i ) {
        my $c = substr( $wifiString, $i, 1 );

        if( defined( $currentValue )) {
            # currently parsing value
            if( $currentValueEscape ) {
                $currentValue .= $c;
                $currentValueEscape = undef;

            } elsif( $c eq '\\' ) {
                $currentValueEscape = $c;

            } elsif( $c eq ',' ) {
                if( exists( $currentWifi->{$currentKey} )) {
                    fatal( 'Field specified more than once in WiFi String:', $currentKey );
                }
                $currentWifi->{$currentKey} = $currentValue;
                $currentKey   = '';
                $currentValue = undef;

            } else {
                $currentValue .= $c;
            }

        } else {
            if( $c eq '=' ) {
                # state transition, now looking for value
                $currentValue = '';

            } elsif( $c eq ',' ) {
                # state transition. No value was given, so we assume empty and move on to the next pair

                if( exists( $currentWifi->{$currentKey} )) {
                    fatal( 'Field specified more than once in WiFi String:', $currentKey );
                }
                $currentWifi->{$currentKey} = '';
                $currentKey   = '';
                $currentValue = undef;

            } else {
                $currentKey .= $c;
            }
        }
    }
    if( $currentKey ) {
        if( exists( $currentWifi->{$currentKey} )) {
            fatal( 'Field specified more than once in WiFi String:', $currentKey );
        }
        $currentWifi->{$currentKey} = $currentValue;
    }
    if( keys %$currentWifi == 0 ) {
        fatal( 'Invalid empty wifi string.' );
    }
    return $currentWifi;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Initialize an attached removable storage device as a UBOS taff.
SSS
        'detail' => <<DDD,
    Various options exist to configure the UBOS Staff in different ways.
DDD
        'cmds' => {
            '' => <<HHH,
    Guess which removable storage device to initialize. The removable
    storage device must be labeled UBOS-STAFF.
HHH
            <<SSS => <<HHH
    [--format | --label] <device>
SSS
    Initialize storage device <device>, e.g. /dev/sdf. If --format is
    given, format the storage device first before initializing (which
    will destroy all existing data on the storage device ). If --label
    is given, do not format but label the device 'UBOS-STAFF' if not
    already labeled.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--add-shepherd-key <key>' => <<HHH,
    Add a public key to the staff. This public key will be used as the
    key for shepherd login on devices that read from the created Staff.
HHH
            '--add-wifi <string>' => <<HHH,
    Add WiFi client information so a device that reads from the created
    Staff can automatically setup wifi. This may be repeated to configure
    multiple wifi networks. <string> is a comma-separated string of
    name=value pairs, each holding an allowed entry with value of the
    "networks" section of a wpa_supplicant.conf file. For example
    "--add-wifi ssid=MyNetwork,psk=secret" will enable the device to
    connect to MyNetwork with password secret.
HHH
            '--add-site-template-file <file>' => <<HHH,
    Add a Site JSON template file to the staff, which will be instantiated
    and deployed when the device boots with this Staff. This may be repeated.
HHH
        }
    };
}

1;
