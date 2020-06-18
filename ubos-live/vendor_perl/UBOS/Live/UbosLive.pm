#!/usr/bin/perl
#
# Centralizes UBOS Live functionality.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::UbosLive;

use JSON;
use UBOS::Lock;
use UBOS::Logging;
use UBOS::Host;
use UBOS::HostStatus;
use UBOS::Utils;
use URI::Escape;
use WWW::Curl::Easy;

my $CONF                   = '/etc/ubos/ubos-live.json';
my $MAX_STATUS_TRIES       = 5;
my $STATUS_DELAY           = 10;
my $API_HOST_PREFIX        = 'http://api.live'; # FIXME https
my $DEVICE_PING_PARENT_URL = '.ubos.net/ping/device/';
my $STATUS_TIMER           = 'ubos-live-ping.timer';
my %CHANNELS               = ( 'red' => 1, 'yellow' => 1, 'green' => 1 );

my $_conf      = undef; # content of the $CONF file; cached
my $_subdomain = undef; # insert subdomain into status URL; cached

##
# Determine which subdomain to use when contacting cloud.
sub _subdomain() {

    unless( defined( $_subdomain )) {
        my $confJson = _getConf();
        my $channel  = $confJson->{channel};
        $_subdomain  = ".$channel";
    }
    return $_subdomain;
}

##
# Contact live.ubos.net, report status, and do the right thing based on the results.
#
# return: desired exit code
sub statusPing {
    trace( 'UbosLive::statusPing' );

    UBOS::Lock::acquire();

    my $confJson = _getConf();

    my $statusUrl = $API_HOST_PREFIX . _subdomain() . $DEVICE_PING_PARENT_URL . UBOS::HostStatus::hostId();

    my $request = UBOS::HostStatus::liveAsJson();

    UBOS::Lock::release();

    my $requestString          = UBOS::Utils::writeJsonToString( $request );
    my $statusUrlWithSignature = _signRequest( $statusUrl, 'POST', $requestString );

    trace( 'Curl operation to', $statusUrlWithSignature, 'with payload:', $requestString );

    my $response;
    my $error;
    my $ret = 1; # error unless success
    for( my $i=1 ; $i<=$MAX_STATUS_TRIES ; ++$i ) { # prints better that way

        eval {
            my $curl = WWW::Curl::Easy->new;
            $curl->setopt( CURLOPT_URL,        $statusUrlWithSignature );
            $curl->setopt( CURLOPT_HTTPHEADER, [ 'Expect:' ] );
            $curl->setopt( CURLOPT_UPLOAD,     1 );
            $curl->setopt( CURLOPT_POST,       1 );
            $curl->setopt( CURLOPT_READDATA,   $requestString );
            $curl->setopt( CURLOPT_WRITEDATA,  \$response );

            my $retCode  = $curl->perform;
            my $httpCode = $curl->getinfo( CURLINFO_HTTP_CODE );

            if( $retCode == 0 && $httpCode =~ m!^200 ! ) {
                trace( 'Successful CURL response, HTTP status:', $httpCode, ', payload:', $response );
                $ret = 0;
                last;
            }
            $error = $curl->strerror( $retCode );

            trace( 'CURL response:', $retCode, ':', $error, ', HTTP status:', $httpCode );
        };
        if( $@ ) {
            trace( 'CURL threw exception:', $@ );
        }
        info( 'UBOS Live status check unsucessful to', $statusUrl, '. Trying again in', $STATUS_DELAY, 'seconds', "($i/$MAX_STATUS_TRIES)" );

        sleep( $STATUS_DELAY );
    }

    # response payload is currently ignored

    return $ret;
}

##
# Activate UBOS Live.
# return: 1 if successful
sub ubosLiveActivate {

    return _activateIfNeeded();
}

##
# Deactivate UBOS Live.
# return: 1 if successful
sub ubosLiveDeactivate {

    return _deactivateIfNeeded();
}

##
# Is UBOS Live active?
# return: true or false
sub isUbosLiveActive {

    my $out;
    my $status = UBOS::Utils::myexec( 'systemctl status ' . $STATUS_TIMER, undef, \$out, \$out );

    return $status == 0;
}

##
# If not already active, activate UBOS Live
sub _activateIfNeeded() {
    trace( 'UbosLive::_activateIfNeeded' );

    if( isUbosLiveActive()) {
        $@ = 'UBOS Live is active already';
        return 0;
    }

    my $errors = 0;
    my $out;

    my $status = UBOS::Utils::myexec( 'systemctl enable --now ' . $STATUS_TIMER, undef, \$out, \$out );
    if( $status ) {
        warning( 'systemctl enable --now', $STATUS_TIMER, ':', $out );
        ++$errors;
    }

    my $confJson = _getConf();
    $confJson->{active} = JSON::true;
    _saveConf();

    if( $errors ) {
        $@ = "There were $errors errors.";
    }

    return $errors == 0;
}

##
# If not already inactive, deactivate UBOS Live
sub _deactivateIfNeeded() {

    trace( 'UbosLive::_deactivateIfNeeded' );

    if( !isUbosLiveActive()) {
        $@ = 'UBOS Live is not active';
        return 0;
    }

    my $errors = 0;
    my $out;

    my $status = UBOS::Utils::myexec( 'systemctl disable --now ' . $STATUS_TIMER, undef, \$out, \$out );
    if( $status ) {
        error( 'systemctl disable --now', $STATUS_TIMER, ':', $out );
        ++$errors;
    }

    my $confJson = _getConf();
    $confJson->{active} = JSON::false;
    _saveConf();

    if( $errors ) {
        $@ = "There were $errors errors.";
    }

    return $errors == 0;
}

##
# Get the current configuration as saved locally, or defaults
# return: status JSON, or undef
sub _getConf {

    unless( $_conf ) {
        if( -e $CONF ) {
            $_conf = UBOS::Utils::readJsonFromFile( $CONF );
        } else {
            $_conf = {};
        }
        unless( exists( $_conf->{active} )) {
            $_conf->{active} = JSON::true;
        }

        if( !exists( $_conf->{channel} ) || !$CHANNELS{$_conf->{channel}} ) {
            $_conf->{channel} = 'green';
        }
    }

    return $_conf;
}

##
# Save the current configuration locally
sub _saveConf {
    if( $_conf ) {
        UBOS::Utils::writeJsonToFile( $CONF, $_conf );
    }
}

##
# Helper to sign a URL with payload
# $url: the base URL
# $method: the HTTP verb, such as GET
# $payload: the payload
# return: the signed URL
sub _signRequest {
    my $url     = shift;
    my $method  = shift;
    my $payload = shift;

    my $ret = $url;
    if( $url =~ m!\?! ) {
        $ret .= '&';
    } else {
        $ret .= '?';
    }
    $ret .= '&lid=gpg%3A' . uri_escape( UBOS::HostStatus::hostPublicKey());
    $ret .= '&lid-version=3';
    $ret .= '&lid-credtype=gpg%20--clearsign';

    my $toSign = $ret;
    if( $method ) {
        $toSign = '&lid-method=' . $method;
    }
    if( $payload ) {
        $toSign = '&lid-payload=' . $payload;
    }

    my $signature = UBOS::Host::hostSign( $toSign );

    $ret .= '&lid-credential=' . uri_escape( $signature );

    return $ret;
}

##
# Invoked when the package installs
sub postInstall {

    # no op for now

    return 0;
}

##
# Invoked when the package upgrades
sub postUpgrade {

    # no op for now

    return 0;
}

1;
