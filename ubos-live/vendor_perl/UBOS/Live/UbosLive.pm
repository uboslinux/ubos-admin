#!/usr/bin/perl
#
# Centralizes UBOS Live functionality.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::UbosLive;

use File::Temp qw/ :POSIX /;
use UBOS::Logging;
use UBOS::Host;
use UBOS::Utils;
use URI::Escape;
use WWW::Curl::Easy;

my $CONF                     = '/etc/ubos/ubos-live.json';
my $MAX_STATUS_TRIES         = 5;
my $STATUS_DELAY             = 10;
my $API_HOST_PREFIX          = 'https://api.live';
my $REGISTRATION_URL         = '.ubos.net/reg/register-device';
my $DEVICE_STATUS_PARENT_URL = '.ubos.net/status/device/';
my $STATUS_TIMER             = 'ubos-live-status-check.timer';
my %CHANNELS                 = ( 'red' => 51820, 'yellow' => 51820, 'green' => 51820 );
my @NETWORKD_FILES           = map { '/etc/systemd/network/99-ubos-live.' . $_ } qw( netdev network );

my $_conf      = undef; # content of the $CONF file; cached
my $_subdomain = undef;

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
# Contact live.ubos.net, tell it what it does not know already, and
# do the right thing based on the results, such as de/activate the VPN.
#
# If something that was attempted (such as registration) failed, returns 0.
# If the same thing succeeded, or if something was skipped because not
# enough information was available (such as for registration), returns 1.
#
# $account: the account identifier provided by the user or through the Staff (if any)
# $token: the registration token provided by the user or through the Staff (if any)
# return: status
sub statusHandshake {
    my $account  = shift;
    my $token    = shift;

    trace( 'UbosLive::statusHandshake' );

    my $confJson = _getConf();

    my $hostId    = UBOS::Host::hostId();
    my $statusUrl = $API_HOST_PREFIX . _subdomain() . $DEVICE_STATUS_PARENT_URL . $hostId;

    my $request = {
        'hostid'      => UBOS::Host::hostId(),
        'arch'        => UBOS::Utils::arch(),
        'deviceclass' => UBOS::Utils::deviceClass(),
        'channel'     => UBOS::Utils::channel(),
        'sku'         => UBOS::Utils::sku()
    };

    if( defined( $confJson->{registered} )) {
        $request->{registered} = $confJson->{registered};
    }

    if( defined( $confJson->{status} )) {
        $request->{status} = $confJson->{status};
    }

    if( $account && $token ) {
        $request->{account} = {
            'account' => $account,
            'token'   => $token
        };

    } elsif( defined( $confJson->{account} )) {
        $request->{account} = $confJson->{account};
    }

    if(    exists( $confJson->{wireguard} )
        && exists( $confJson->{wireguard}->{client} )
        && exists( $confJson->{wireguard}->{client}->{publickey} ))
    {
        $request->{wireguard}->{client}->{publickey} = $confJson->{wireguard}->{client}->{publickey};
    }

    my $requestString          = UBOS::Utils::writeJsonToString( $request );
    my $statusUrlWithSignature = _signRequest( $statusUrl, 'POST', $requestString );

    trace( 'Curl operation to', $statusUrlWithSignature, 'with payload:', $requestString );

    my $response;
    my $error;
    for( my $i=1 ; $i<=$MAX_STATUS_TRIES ; ++$i ) { # prints better that way

        my $curl = WWW::Curl::Easy->new;
        $curl->setopt( CURLOPT_URL,       $statusUrlWithSignature );
        $curl->setopt( CURLOPT_UPLOAD,    1 );
        $curl->setopt( CURLOPT_POST,      1 );
        $curl->setopt( CURLOPT_READDATA,  $requestString );
        $curl->setopt( CURLOPT_WRITEDATA, \$response );

        my $retCode  = $curl->perform;
        my $httpCode = $curl->getinfo( CURLINFO_HTTP_CODE );

        if( $retCode == 0 && $httpCode =~ m!^200 ! ) {
            trace( 'Successful CURL response, HTTP status:', $httpCode, ', payload:', $response );
            last;
        }
        $error = $curl->strerror( $retCode );

        trace( 'CURL response:', $retCode, ':', $error, ', HTTP status:', $httpCode );

        info( 'UBOS Live status check unsucessful so far. Trying again in', $STATUS_DELAY, 'seconds', "($i/$MAX_STATUS_TRIES)" );

        sleep( $STATUS_DELAY );
    }

    if( $response ) {
        my $responseJson = UBOS::Utils::readJsonFromString( $response );
        if( exists( $responseJson->{wireguard} ) && exists( $responseJson->{wireguard}->{server} )) {
            $confJson->{wireguard}->{server} = $responseJson->{wireguard}->{server};
        }
        if( exists( $responseJson->{registered} )) {
            $confJson->{registered} = $responseJson->{registered};
        }
        if( exists( $responseJson->{status} )) {
            $confJson->{status} = $responseJson->{status};
        }
        if( exists( $responseJson->{account} )) {
            $confJson->{account} = $responseJson->{account};
        }

        if( defined( $confJson->{status} )) {
            my $status = $confJson->{status};

            if( $status eq 'ubos-live-inactive' ) {
                _makeSuspendedIfNeeded();
                _deactivateIfNeeded();

            } elsif( $status =~ m!^ubos-live-active! ) {
                _activateIfNeeded();

                if( $status eq 'ubos-live-active/ubos-live-operational' ) {
                    _makeOperationalIfNeeded();
                } else {
                    _makeSuspendedIfNeeded();
                }
            }
        }

    } else {
        warning( 'Unexpected UBOS Live state:', $response );
        return 0;
    }
}

##
# Register for UBOS Live.
# $account: account identifier on UBOS Live provided by the user (if any)
# $token: security token provided by the user (if any)
# return: 1 if successful
sub ubosLiveRegister {
    my $account = shift;
    my $token   = shift;

    return statusHandshake( $account, $token );
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

    # Don't handle live99 here: we only bring it up once status subclass is known / right

    my $errors = 0;
    my $out;

    my $status = UBOS::Utils::myexec( 'systemctl enable --now ' . $STATUS_TIMER, undef, \$out, \$out );
    if( $status ) {
        warning( 'systemctl enable --now', $STATUS_TIMER, ':', $out );
        ++$errors;
    }

    my $confJson = _getConf();

    $confJson->{status} = 'ubos-live-active'; # subclass unclear so far
    _saveConf();

    $@ = "There were $errors errors.";

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

    _disableLiveLink();

    my $confJson = _getConf();
    $confJson->{status} = 'ubos-live-inactive';
    _saveConf();

    $@ = "There were $errors errors.";

    return $errors == 0;
}

##
# If not already operational, make UBOS Live operational
sub _makeOperationalIfNeeded() {

    trace( 'UbosLive::_makeOperationalIfNeeded' );

    _enableLiveLink();
}

##
# If not already suspended, make UBOS Live suspended
sub _makeSuspendedIfNeeded() {

    trace( 'UbosLive::_makeSuspendedIfNeeded' );

    _disableLiveLink();
}

##
# Disable the live99 network link if it exists
sub _disableLiveLink() {

    foreach my $f ( @NETWORKD_FILES ) {
        if( -e $f ) {
            UBOS::Utils::deleteFile( $f );
        }
    }

    UBOS::Utils::myexec( 'ip link delete dev live99' );
    # ignore result
}

##
# Enable the live99 network link if needed
sub _enableLiveLink() {

    my $channel = UBOS::Utils::channel();
    my $serverPort = $CHANNELS{$channel};
    unless( $serverPort ) {
        $channel    = 'green';
        $serverPort = $CHANNELS{$channel};
    }

    my $confJson         = _getConf();
    my $clientPrivateKey = $confJson->{wireguard}->{client}->{privatekey};
    my $serverPublicKey  = $confJson->{wireguard}->{server}->{publickey};
    my $serverName       = "wg.$channel.live.ubos.net";

    foreach my $to ( @NETWORKD_FILES ) {
        my $from    = '/usr/share/ubos-live/tmpl/' . basename( $to ) . '.tmpl';
        my $content = UBOS::Utils::slurpFile( $from );

        $content =~ s!WIREGUARD_CLIENT_PRIVATE_KEY!$clientPrivateKey!g;
        $content =~ s!WIREGUARD_SERVER_PUBLIC_KEY!$serverPublicKey!g;
        $content =~ s!WIREGUARD_SERVER_NAME!$serverName!g;
        $content =~ s!WIREGUARD_SERVER_PORT!$serverPort!g;

        UBOS::Utils::saveFile( $to, $content, 'root', 'systemd-networkd', 0640 );
    }

    if( UBOS::Utils::myexec( 'systemctl restart systemd-networkd' )) {
        error( 'Restarting systemd-networkd failed' );
    }
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
        unless( exists( $_conf->{registered} )) {
            $_conf->{registered} = JSON::false;
        }

        if( !exists( $_conf->{wireguard} ) || !exists( $_conf->{wireguard}->{client} )) {
            my $privateOut;
            my $publicOut;

            if( UBOS::Utils::myexec( 'wg genkey', undef, \$privateOut )) {
                error( 'Failed to generate Wireguard key pair' );

            } elsif( UBOS::Utils::myexec( 'wg pubkey', $privateOut, \$publicOut )) {
                error( 'Failed to obtain Wireguard public key' );

            } else {
                $privateOut =~ s!^\s+!!;
                $privateOut =~ s!\s+$!!;
                $publicOut  =~ s!^\s+!!;
                $publicOut  =~ s!\s+$!!;

                $_conf->{wireguard}->{client} = {
                    'privatekey' => $privateOut,
                    'publickey'  => $publicOut
                };
            }
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
# Because the systemd-sysusers hook only runs after the package install
# script is completed, we run it ourselves from the package install script.
sub _ensureUser {
    UBOS::Utils::myexec( "systemd-sysusers /usr/lib/sysusers.d/ubos-live.conf" );
}

##
# Copy the authorized SSH keys into ~ubos-live/.ssh/authorized_keys
sub _ensureAuthorizedKeys {
    my $keys = UBOS::Utils::slurpFile( '/usr/share/ubos-live/authorized_keys' );
    if( $keys ) {
        my $dir = '/var/ubos-live/.ssh';
        unless( -d $dir ) {
            UBOS::Utils::mkdirDashP( $dir, 0700, 'ubos-live', 'ubos-live' );
        }
        UBOS::Utils::saveFile( "$dir/authorized_keys", $keys, 0600, 'ubos-live', 'ubos-live' );
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
    $ret .= '&lid=gpg%3A' . uri_escape( UBOS::Host::hostPublicKey());
    $ret .= '&lid-version=3';
    $ret .= '&lid-credtype=gpg%20--clearsign';

    my $toSign = $ret;
    $toSign = '&lid-method=' . $method;
    $toSign = '&lid-payload=' . $payload;

    my $signature = UBOS::Host::hostSign( $toSign );

    $ret .= '&lid-credential=' . uri_escape( $signature );

    return $ret;
}

##
# Invoked when the package installs
sub postInstall {

    _ensureUser();
    _ensureAuthorizedKeys();

    return 0;
}

##
# Invoked when the package upgrades
sub postUpgrade {

    _ensureUser();
    _ensureAuthorizedKeys();

    return 0;
}

1;
