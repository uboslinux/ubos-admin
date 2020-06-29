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
use URI::Escape;
use UBOS::Utils;
use HTTP::Request;
use LWP::UserAgent;
use Time::Local qw( timegm );

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
    my $statusUrlWithSignature = _signRequest( $statusUrl, 'POST', 'application/json', $requestString );

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
# $contentType: the payload content type
# $content: the payload
# return: the signed URL
sub _signRequest {
    my $url         = shift;
    my $method      = shift;
    my $contentType = shift;
    my $content     = shift;

    my $ret = $url;
    $ret .= _appendQueryPair( $ret, 'lid-version',   '3' );
    $ret .= _appendQueryPair( $ret, 'lid',           'gpg:' . _trimKey( UBOS::HostStatus::hostPublicKey()));
    $ret .= _appendQueryPair( $ret, 'lid-nonce',     _nonce());
    $ret .= _appendQueryPair( $ret, 'lid-credtype',  'gpg --clearsign,hash=SHA256' );

    my $toSign = $ret;
    $toSign .= _appendQueryPair( $toSign, 'lid-verb', $method );

    if( $content ) {
        if( $contentType ) {
            $toSign .= _appendQueryPair( $toSign, 'lid-content-type', $contentType );
        } else {
            warning( 'No content type given for signing LID request' )
        }
        $toSign .= '&lid-content=' . $content; # Do not escape
    }

    my ( $hash, $signature ) = UBOS::Host::hostSign( $toSign );
    if( $hash ne 'SHA256' ) {
        warning( 'Signed with the wrong hash', $hash )
    }

    $ret .= _appendQueryPair( $ret, 'lid-credential', $signature );

    return $ret;
}

##
# Trim a public key by removing the ---XXX--- head and foot.
#
# $key: to-be-trimmed key
# return: trimmed
sub _trimKey {
    my $key = shift;

    if( $key =~ m!-----BEGIN PGP PUBLIC KEY BLOCK-----\s+(\S.*\S)\s+-----END PGP PUBLIC KEY BLOCK-----!s ) {
        return $1;
    } else {
        error( 'Failed to trim public key:', $key );
        return $key;
    }
}

##
# Helper method to create a nonce. The nonce is a timestamp
# (so the receiver can discard already-used nonces after some time and
# reject old nonces according to its policy) plus a random number
# (to avoid collisions).
#
# return: nonce
sub _nonce {

    my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = gmtime( time() );
    my $rand = UBOS::Utils::randomHex( 16 );
    my $ret = sprintf "%.4d%.2d%.2dT%.2d%.2d%.2dZ%s", ($year+1900), ( $mon+1 ), $mday, $hour, $min, $sec, $rand;

    return $ret;
}

##
# Helper to append a name=value pair to the query of a URL.
#
# $url: the URL so far
# $name: to append
# $value: top append
# return: the URL with appended query
sub _appendQueryPair {
    my $url   = shift;
    my $name  = shift;
    my $value = shift;

    my $ret = $url;
    if( $ret =~ m!\?! ) {
        $ret = '&';
    } else {
        $ret = '?';
    }

    $ret .= _queryEscape( $name );
    $ret .= '=';
    $ret .= _queryEscape( $value );
    return $ret;
}

##
# Escape a name or value in a query.
# Note: URI::Escape is too aggressive, it %-encodes /
# $v: the value
# return: escaped value
sub _queryEscape {
    my $v = shift;

    return uri_escape( $v, "^A-Za-z0-9\-\._~/" ); # add slash to default
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
