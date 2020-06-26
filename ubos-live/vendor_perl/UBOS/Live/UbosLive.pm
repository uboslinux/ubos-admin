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
use HTTP::Request;
use LWP::UserAgent;
use Time::HiRes;

my $CONF                   = '/etc/ubos/ubos-live.json';
my $MAX_STATUS_TRIES       = 5;
my $STATUS_DELAY           = 10;
my $STATUS_TIMER           = 'ubos-live-ping.timer';
my $CHANNELS               = {
    'red'    => {
        'pingendpoint' => 'http://api.live.red.ubos.net/ping' # no TLS
    },
    'yellow' => {
        'pingendpoint' => 'https://api.live.yellow.ubos.net/ping'
    },
    'green'  => {
        'pingendpoint' => 'https://api.live.ubos.net/ping'
    }
};

my $_conf = undef; # content of the $CONF file; cached

##
# Contact live.ubos.net, report status, and do the right thing based on the results.
#
# return: desired exit code
sub statusPing {
    trace( 'UbosLive::statusPing' );

    UBOS::Lock::acquire();

    my $confJson = _getConf();
    my $channel  = $confJson->{channel};

    if( !exists( $CHANNELS->{$channel} ) || !exists( $CHANNELS->{$channel}->{pingendpoint} )) {
        fatal( 'UBOS Live is not available on release channel', $channel );
    }
    my $statusUrl = $CHANNELS->{$channel}->{pingendpoint} . '/device/' . UBOS::HostStatus::hostId();

    my $request = UBOS::HostStatus::liveAsJson();

    UBOS::Lock::release();

    my $requestString          = UBOS::Utils::writeJsonToString( $request );
    my $statusUrlWithSignature = _signRequest( $statusUrl, 'POST', $requestString );

    trace( 'HTTP to', $statusUrlWithSignature, 'with payload:', $requestString );

    my $response;
    my $error;
    my $ret = 1; # error unless success
    for( my $i=1 ; $i<=$MAX_STATUS_TRIES ; ++$i ) { # prints better that way

        my $req = HTTP::Request->new( 'POST', $statusUrlWithSignature );
        $req->header( 'Content-Type' => 'application/json' );
        $req->content( $requestString );

        my $lwp      = LWP::UserAgent->new;
        my $response = $lwp->request( $req );

        if( $response->is_success() ) {
            trace( 'Successful HTTP response, payload:', $response->decoded_content );
            $ret = 0;
            last;
        }
        trace( 'HTTP response:', $response->status_line );

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

        if( !exists( $_conf->{channel} )) {
            $_conf->{channel} = 'green';
        }
        unless( exists( $CHANNELS->{$_conf->{channel}} )) {
            fatal( 'Unsupported release channel:', $_conf->{channel} );
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
    $ret .= '&lid-version=3';
    $ret .= '&lid=gpg%3A' . uri_escape( UBOS::HostStatus::hostPublicKey());
    $ret .= '&lid-nonce=' . _nonce();
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
# Helper method to create a nonce
sub _nonce {

    my $now = Time::HiRes::time();
    my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = gmtime( $now );
    my $millis = int(( $now - int( $now )) * 1000 );

    my $ret = sprintf "%.4d%.2d%.2dT%.2d%.2d%.2d.%.3dZ", ($year+1900), ( $mon+1 ), $mday, $hour, $min, $sec, $millis;
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
