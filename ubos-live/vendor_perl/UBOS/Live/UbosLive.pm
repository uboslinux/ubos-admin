#!/usr/bin/perl
#
# Centralizes UBOS Live functionality.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Live::UbosLive;

use UBOS::Logging;
use UBOS::Host;
use UBOS::Utils;

my $OPENVPN_CLIENT_CONFIG  = '/etc/openvpn/client/ubos-live.conf';
my $SERVICE_CERT_DIR       = '/etc/ubos-live-certificates';
my $CLIENT_CERT_DIR        = '/etc/ubos-live';
my $OPENVPN_CLIENT_KEY     = $CLIENT_CERT_DIR . '/client.key';
my $OPENVPN_CLIENT_CSR     = $CLIENT_CERT_DIR . '/client.csr';
my $OPENVPN_CLIENT_CRT     = $CLIENT_CERT_DIR . '/client.crt';
my $MAX_REGISTRATION_TRIES = 5;
my $REGISTRATION_DELAY     = 5;
my $REGISTRATION_URL       = 'https://api.live.ubos.net/reg/register-device';
my $SERVICE                = 'openvpn-client@ubos-live.service';

##
# Register for UBOS Live.
# $token: token provided
# $registrationurl: non-default registration URL, if any
# return: number of errors
sub registerWithUbosLive {
    my $token           = shift;
    my $registrationurl = shift || $REGISTRATION_URL;

    trace( 'UbosLive::registerWithUbosLive', $token, $registrationurl );

    my $errors = 0;

    $errors += _ensureOpenvpnKeyCsr();
    unless( $errors ) {
        $errors += _ensureRegistered( $token, $registrationurl );
    }
    unless( $errors ) {
        $errors += _ensureOpenvpnClientConfig();
    }

    return $errors;
}

##
# Determine whether this host is registered for UBOS Live.
# return: true or false
sub isRegisteredWithUbosLive {
    return -e $OPENVPN_CLIENT_CRT;
}

##
# Start UBOS Live.
# return: 1 if successful
sub startUbosLive {

    trace( 'UbosLive::startUbosLive' );

    my $out;
    my $status  = UBOS::Utils::myexec( 'systemctl start '  . $SERVICE, undef, \$out, \$out );
    $status    |= UBOS::Utils::myexec( 'systemctl enable ' . $SERVICE, undef, \$out, \$out );

    return $status == 0;
}

##
# Stop UBOS Live.
sub stopUbosLive {

    trace( 'UbosLive::stopUbosLive' );

    my $out;
    my $status  = UBOS::Utils::myexec( 'systemctl disable ' . $SERVICE, undef, \$out, \$out );
    $status    |= UBOS::Utils::myexec( 'systemctl stop '    . $SERVICE, undef, \$out, \$out );

    return $status == 0;
}

##
# Is UBOS Live running?
sub isUbosLiveRunning {

    my $out;
    my $status = UBOS::Utils::myexec( 'systemctl status ' . $SERVICE, undef, \$out, \$out );

    return $status == 0;
}

##
# If UBOS Live is currently running, restart it
sub _restartUbosLiveIfNeeded() {

    if( isUbosLiveRunning()) {
        my $out;
        UBOS::Utils::myexec( 'systemctl restart  ' . $SERVICE, undef, \$out, \$out );
    }
}

##
# Invoked when the package installs
sub postInstall {
    postUpgrade();
}

##
# Invoked when the package upgrades
sub postUpgrade {
    # UBOS Live may or may not be active

    if( -e $OPENVPN_CLIENT_CONFIG ) {
        _ensureOpenvpnClientConfig();
    }
    _copyAuthorizedKeys();
    _restartUbosLiveIfNeeded();

    return 0;
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
# Copy the authorized SSH keys into ~ubos-live/.ssh/authorized_keys
sub _copyAuthorizedKeys {
    my $keys = UBOS::Utils::slurpFile( '/usr/share/ubos-live/authorized_keys' );
    if( $keys ) {
        my $dir = '/var/ubos-live/.ssh';
        unless( -d $dir ) {
            UBOS::Utils::mkdir( $dir, 0700, 'ubos-live', 'ubos-live' );
        }
        UBOS::Utils::saveFile( "$dir/authorized_keys", $keys, 0600, 'ubos-live', 'ubos-live' );
    }
}

##
# Generate a random registration token.
# return: the token
sub generateRegistrationToken {
    # 32 hex in groups of 4
    my $ret;
    my $sep = '';
    for( my $i=0 ; $i<8 ; ++$i ) {
        $ret .= $sep . UBOS::Utils::randomHex( 4 );
        $sep = '-';
    }        
    return $ret;
}

1;
