#!/usr/bin/perl
#
# Centralizes UBOS Live functionality.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::UbosLive;

use Switch;
use UBOS::Logging;
use UBOS::Host;
use UBOS::Utils;
use WWW::Curl::Easy;

my $OPENVPN_CLIENT_CONFIG    = '/etc/openvpn/client/ubos-live.conf';
my $SERVICE_CERT_DIR         = '/etc/ubos-live-certificates';
my $CLIENT_CERT_DIR          = '/etc/ubos-live';
my $OPENVPN_CLIENT_KEY       = $CLIENT_CERT_DIR . '/client.key';
my $OPENVPN_CLIENT_CSR       = $CLIENT_CERT_DIR . '/client.csr';
my $OPENVPN_CLIENT_CRT       = $CLIENT_CERT_DIR . '/client.crt';
my $CONF                     = $CLIENT_CERT_DIR . '/ubos-live.json';
my $MAX_REGISTRATION_TRIES   = 5;
my $REGISTRATION_DELAY       = 5;
my $REGISTRATION_URL         = 'https://api.live.ubos.net/reg/register-device';
my $DEVICE_STATUS_PARENT_URL = 'https://api.live.ubos.net/status/device';
my $OPENVPN_SERVICE          = 'openvpn-client@ubos-live.service';
my $STATUS_TIMER             = 'ubos-live-status-check.timer';

my $conf = undef; # content of the $CONF file; cached

##
# Invoked periodically, this checks on the status of UBOS Live for this
# device, and performs necessary actions
sub checkStatus {

    my $hostId    = UBOS::Host::hostId();
    my $statusUrl = $DEVICE_STATUS_PARENT_URL . $hostId;

    my $response;
    my $curl = WWW::Curl::Easy->new;
    $curl->setopt( CURLOPT_URL,       $statusUrl );
    $curl->setopt( CURLOPT_WRITEDATA, $response );

    my $retCode  = $curl->perform;
    my $httpCode = $curl->getinfo( CURLINFO_HTTP_CODE );

    if( $retcode != 0 || $httpCode !~ m!^200 ! ) {
        warning( 'UBOS Live status check failed:', $retCode, $curl->strerror( $retCode ), $httpCode, $curl->errbuf, ':', $response );
        return 0;
    }

    trace( 'UBOS Live status check:', $retCode, $curl->strerror( $retCode ), $httpCode, ':', $response );

    $response =~ s!^\s+!!;
    $response =~ s!\s+$!!;

    if( $response eq 'ubos-live-inactive' {
        _deactivateIfNeeded();

    } elsif( $response =~ m!^ubos-live-active! ) {
        _activateIfNeeded();

        if( $response eq 'ubos-live-active/ubos-live-operational' ) {
            _makeOperationalIfNeeded();
        } else {
            _makeNonOperationalIfNeeded();
        }

    } else {
        warning( 'Unexpected UBOS Live state:', $response );
        return 0;
    }
}

##
# Activate UBOS Live.
# $token: if provided, use this token
# $registrationUrl: if provided, use this registration URL
# return: 1 if successful
sub ubosLiveActivate {
    my $token           = shift;
    my $registrationUrl = shift;

    _activateIfNeeded( $token, $registrationUrl );
}

##
# Deactivate UBOS Live.
# return: 1 if successful
sub ubosLiveDeactivate {

    _deactivateIfNeeded();
}

##
# Is UBOS Live active?
sub isUbosLiveActive {

    my $out;
    my $status = UBOS::Utils::myexec( 'systemctl status ' . $STATUS_TIMER, undef, \$out, \$out );

    return $status == 0;
}

##
# Is UBOS Live operational?
sub isUbosLiveOperational {

    my $out;
    my $status = UBOS::Utils::myexec( 'systemctl status ' . $OPENVPN_SERVICE, undef, \$out, \$out );

    return $status == 0;
}

##
# If not already active, activate UBOS Live
sub _activateIfNeeded() {
    my $token           = shift || _generateRegistrationToken();
    my $registrationUrl = shift || $REGISTRATION_URL;

    trace( 'UbosLive::_activateIfNeeded'. $token, $registrationUrl );

    if( isUbosLiveActive()) {
        return 0;
    }

    my $errors = 0;
    $errors += _ensureOpenvpnKeyCsr();
    unless( $errors ) {
        $errors += _ensureRegistered( $token, $registrationUrl );
    }
    unless( $errors ) {
        $errors += _ensureOpenvpnClientConfig();
    }

    if( $errors ) {
        return 0;
    }

    my $confJson = {
        'token'  => $token,
        'status' => 'active'
    };
    setConf( $confJson );

    my $out;
    my $status = UBOS::Utils::myexec( 'systemctl enable --now ' . $STATUS_TIMER, undef, \$out, \$out );
    if( $status ) {
        warning( 'systemctl enable --now', $STATUS_TIMER, ':', $out );
    }

    return $status == 0;
}


##
# If not already inactive, deactivate UBOS Live
sub _deactivateIfNeeded() {

    trace( 'UbosLive::_deactivateIfNeeded' );

    my $errors = 0;
    my $out;

    my $status = UBOS::Utils::myexec( 'systemctl disable --now ' . $STATUS_TIMER, undef, \$out, \$out );
    if( $status ) {
        error( 'systemctl disable --now', $STATUS_TIMER, ':', $out );
        ++$errors;
    }

    $status = UBOS::Utils::myexec( 'systemctl disable --now ' . $OPENVPN_SERVICE, undef, \$out, \$out );
    if( $status ) {
        error( 'systemctl disable --now', $OPENVPN_SERVICE, ':', $out );
        ++$errors;
    }

    my $confJson = getConf();
    $conf->{status} = 'inactive';
    setConf( $confJson );

    return $errors == 0;
}

##
# If not already operational, make UBOS Live operational
sub _makeOperationalIfNeeded() {

    $status = UBOS::Utils::myexec( 'systemctl enable --now ' . $OPENVPN_SERVICE, undef, \$out, \$out );
    if( $status ) {
        error( 'systemctl enable --now', $OPENVPN_SERVICE, ':', $out );
        ++$errors;
    }

    return $errors == 0;
}

##
# If not already non-operational, make UBOS Live non-operational
sub _makeNonOperationalIfNeeded() {

    $status = UBOS::Utils::myexec( 'systemctl disable --now ' . $OPENVPN_SERVICE, undef, \$out, \$out );
    if( $status ) {
        error( 'systemctl disable --now', $OPENVPN_SERVICE, ':', $out );
        ++$errors;
    }

    return $errors == 0;
}

##
# If UBOS Live is currently active, restart it
sub _restartUbosLiveIfNeeded() {

    if( isUbosLiveOperational()) {
        my $out;
        UBOS::Utils::myexec( 'systemctl restart  ' . $OPENVPN_SERVICE, undef, \$out, \$out );
    }
    return 0;
}

##
# Get the current configuration as saved locally
# return: status JSON, or undef
sub getConf {

    unless( $_conf ) {
        $_conf = UBOS::Utils::readJsonFromFile( $CONF );
    }
    return $_conf;
}

##
# Save the current configuration locally
# $conf: the local configuration JSON
sub setConf {
    my $conf = shift;

    UBOS::Utils::writeJsonToFile( $CONF, $conf );
}

##
# Ensure that there is an OpenVPN client key and csr
# Return: number of errors
sub _ensureOpenvpnKeyCsr {

    trace( 'UbosLive::_ensureOpenvpnKeyCsr' );

    my $errors = 0;
    my $out;

    my $swallow = UBOS::Logging::isInfoActive() ? undef : \$out;
    unless( -e $OPENVPN_CLIENT_KEY ) {
        if( UBOS::Utils::myexec( "openssl genrsa -out '$OPENVPN_CLIENT_KEY' 4096", undef, $swallow, $swallow )) {
            error( 'openssl genrsa failed:', $swallow );
            ++$errors;
        }
    }
    unless( -e $OPENVPN_CLIENT_KEY ) {
        $@ = 'Failed to generate UBOS Live client VPN key';
        return $errors;
    }
    chmod 0600, $OPENVPN_CLIENT_KEY;

    unless( -e $OPENVPN_CLIENT_CSR ) {
        my $id = UBOS::Host::hostId();
        $id = lc( $id );
        if( UBOS::Utils::myexec( "openssl req -new -key '$OPENVPN_CLIENT_KEY' -out '$OPENVPN_CLIENT_CSR' -subj '/CN=$id.d.live.ubos.net'", undef, $swallow, $swallow )) {
            error( 'openssl req failed:', $swallow );
            ++$errors;
        }
    }
    unless( -e $OPENVPN_CLIENT_CSR ) {
        $@ = 'Failed to generate UBOS Live client VPN certificate request';
        return $errors;
    }
    return $errors;
}

##
# Ensure that the device is registered and has the appropriate key
# $token: the registration token entered by the user
# $registrationurl: URL to post the registration to
# return: number of errors
sub _ensureRegistered {
    my $token           = shift;
    my $registrationurl = shift;

    trace( 'UbosLive::_ensureRegistered' );

    my $hostid      = UBOS::Host::hostId();
    my $arch        = UBOS::Utils::arch();
    my $deviceClass = UBOS::Utils::deviceClass();
    my $channel     = UBOS::Utils::channel();
    my $sku         = UBOS::Utils::sku();

    my $errors = 0;

    unless( -e $OPENVPN_CLIENT_CRT ) {
        $token =~ s!\s!!g;

        my $cmd = "curl";
        $cmd   .= " --silent";
        $cmd   .= " -XPOST";
        $cmd   .= " -w '%{http_code}'";
        $cmd   .= " --data-urlencode 'token="       . $token              . "'";
        $cmd   .= " --data-urlencode 'csr@"         . $OPENVPN_CLIENT_CSR . "'";
        $cmd   .= " --data-urlencode 'hostid="      . $hostid             . "'";
        $cmd   .= " --data-urlencode 'arch="        . $arch               . "'";
        $cmd   .= " --data-urlencode 'deviceclass=" . $deviceClass        . "'";
        $cmd   .= " --data-urlencode 'channel="     . $channel            . "'";

        if( $sku ) {
            # might be a download, self-assembled
            $cmd   .= " --data-urlencode 'sku="     . $sku                . "'";
        }

        $cmd   .= " '$registrationurl'";
        $cmd   .= " -o " . $OPENVPN_CLIENT_CRT;

        my $out;
        my $err;
        for( my $i=1 ; $i<=$MAX_REGISTRATION_TRIES ; ++$i ) { # prints better that way
            trace( "UBOS Live registration try $i\n" );

            my $status = UBOS::Utils::myexec( $cmd, undef, \$out, \$err );
            if( !$status && $out =~ m!200! ) {
                last;
            }
            if( -e $OPENVPN_CLIENT_CRT ) {
                UBOS::Utils::deleteFile( $OPENVPN_CLIENT_CRT );
            }

            info( 'UBOS Live registration unsucessful so far. Trying again in', $REGISTRATION_DELAY, 'seconds', "($i/$MAX_REGISTRATION_TRIES)" );
            sleep( $REGISTRATION_DELAY );
        }
        unless( -e $OPENVPN_CLIENT_CRT ) {
            $@ = 'Failed to register with UBOS Live.';
            ++$errors;
        }
    }
    return $errors;
}

##
# Ensure that the OpenVPN client is set up correctly
# return: number of errors
sub _ensureOpenvpnClientConfig {

    trace( 'UbosLive::_ensureOpenvpnClientConfig' );

    my $errors = 0;

    # Always do that, so it's regenerated when the code has changed
    unless( UBOS::Utils::saveFile( $OPENVPN_CLIENT_CONFIG, <<CONTENT )) {
#
# OpenVPN UBOS Live client-side config file.
# Adopted from OpenVPN client.conf example
# DO NOT MODIFY. UBOS WILL OVERWRITE MERCILESSLY.
#
client
dev tun90
# tun-ipv6 -- supposedly not needed any more
proto udp
remote vpn.live.ubos.net 1194
resolv-retry infinite
nobind
user nobody
group nobody
persist-key
persist-tun
;mute-replay-warnings
ca $SERVICE_CERT_DIR/s-cas.live.ubos.net.crt
cert $OPENVPN_CLIENT_CRT
key $OPENVPN_CLIENT_KEY
;remote-cert-tls server
;tls-auth ta.key 1
comp-lzo
verb 3
;mute 20
CONTENT
        ++$errors;
    }
    return $errors;
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
# Generate a random registration token.
# return: the token
sub _generateRegistrationToken {
    # 32 hex in groups of 4
    my $ret;
    my $sep = '';
    for( my $i=0 ; $i<8 ; ++$i ) {
        $ret .= $sep . UBOS::Utils::randomHex( 4 );
        $sep = '-';
    }
    return $ret;
}

##
# Invoked when the package installs
sub postInstall {

    _ensureOpenvpnClientConfig();

    _ensureUser();
    _ensureAuthorizedKeys();

    _restartUbosLiveIfNeeded();

    return 0;
}

##
# Invoked when the package upgrades
sub postUpgrade {

    _ensureOpenvpnClientConfig();

    _restartUbosLiveIfNeeded();

    return 0;
}

1;
