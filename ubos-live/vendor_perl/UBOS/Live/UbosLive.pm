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
use WWW::Curl::Easy;

my $CONF                     = '/etc/ubos/ubos-live.json';
my $MAX_REGISTRATION_TRIES   = 5;
my $REGISTRATION_DELAY       = 5;
my $API_HOST_PREFIX          = 'https://api.live';
my $REGISTRATION_URL         = '.ubos.net/reg/register-device';
my $DEVICE_STATUS_PARENT_URL = '.ubos.net/status/device';
my $STATUS_TIMER             = 'ubos-live-status-check.timer';
my %CHANNELS                 = ( 'red' => 1, 'yellow' => 1, 'green' => 1 );
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
# Invoked periodically, this checks on the status of UBOS Live for this
# device, and performs necessary actions
sub checkStatus {

    my $hostId    = UBOS::Host::hostId();
    my $statusUrl = $API_HOST_PREFIX . _subdomain() . $DEVICE_STATUS_PARENT_URL . $hostId;

    my $response;
    my $curl = WWW::Curl::Easy->new;
    $curl->setopt( CURLOPT_URL,       $statusUrl );
    $curl->setopt( CURLOPT_WRITEDATA, $response );

    my $retCode  = $curl->perform;
    my $httpCode = $curl->getinfo( CURLINFO_HTTP_CODE );

    if( $retCode != 0 || $httpCode !~ m!^200 ! ) {
        warning( 'UBOS Live status check failed:', $retCode, $curl->strerror( $retCode ), $httpCode, $curl->errbuf, ':', $response );
        return 0;
    }

    trace( 'UBOS Live status check:', $retCode, $curl->strerror( $retCode ), $httpCode, ':', $response );

    $response =~ s!^\s+!!;
    $response =~ s!\s+$!!;

    if( $response eq 'ubos-live-inactive' ) {
        _makeSuspendedIfNeeded( $response );
        _deactivateIfNeeded();

    } elsif( $response =~ m!^ubos-live-active! ) {
        _activateIfNeeded();

        if( $response eq 'ubos-live-active/ubos-live-operational' ) {
            _makeOperationalIfNeeded( $response );
        } else {
            _makeSuspendedIfNeeded( $response );
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
# If not already active, activate UBOS Live
sub _activateIfNeeded() {
    my $token           = shift || _generateRegistrationToken();
    my $registrationUrl = shift || ( $API_HOST_PREFIX . _subdomain() . $REGISTRATION_URL );

    trace( 'UbosLive::_activateIfNeeded', $token, $registrationUrl );

    if( isUbosLiveActive()) {
        $@ = 'UBOS Live is active already';
        return 0;
    }

    my $confJson = _getConf();

    my $errors = 0;
    $errors += _ensureRegistered( $token, $registrationUrl, $confJson );

    if( $errors ) {
        $@ = "There were $errors errors.";
        return 0;
    }

    $confJson->{token}  = $token;
    $confJson->{status} = 'ubos-live-active'; # subclass unclear so far

    _setConf( $confJson );

    # Don't handle live99 here: we only bring it up once status subclass is known / right

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

    my $confJson = _getConf();
    if( !exists( $confJson->{status} ) || $confJson->{status} !~ m!^ubos-live-active! ) {
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

    $confJson->{status} = 'ubos-live-inactive';
    _setConf( $confJson );

    $@ = "There were $errors errors.";

    return $errors == 0;
}

##
# If not already operational, make UBOS Live operational
# $liveStatus: the new status value as obtained from the cloud
sub _makeOperationalIfNeeded() {
    my $liveStatus = shift;

    trace( 'UbosLive::_makeOperationalIfNeeded', $liveStatus );

    my $errors = 0;
    my $out;

    _enableLiveLink();

    my $confJson = _getConf();
    $confJson->{status} = $liveStatus;
    _setConf( $confJson );

    $@ = "There were $errors errors.";

    return $errors == 0;
}

##
# If not already suspended, make UBOS Live suspended
# $liveStatus: the new status value as obtained from the cloud
sub _makeSuspendedIfNeeded() {
    my $liveStatus = shift;

    trace( 'UbosLive::_makeSuspendedIfNeeded', $liveStatus );

    my $errors = 0;
    my $out;

    _disableLiveLink();

    my $confJson = _getConf();
    $confJson->{status} = $liveStatus;
    _setConf( $confJson );

    $@ = "There were $errors errors.";

    return $errors == 0;
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

    my $confJson         = _getConf();
    my $clientPrivateKey = $confJson->{wireguard}->{client}->{privatekey};
    my $serverPublicKey  = $confJson->{wireguard}->{server}->{publickey};

    foreach my $to ( @NETWORKD_FILES ) {
        my $from    = '/usr/share/ubos-live/tmpl/' . basename( $to ) . '.tmpl';
        my $content = UBOS::Utils::slurpFile( $from );

        $content =~ s!WIREGUARD_CLIENT_PRIVATE_KEY!$clientPrivateKey!g;
        $content =~ s!WIREGUARD_SERVER_PUBLIC_KEY!$serverPublicKey!g;

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
        $_conf->{registered} = 0;

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
# $confJson: the local configuration JSON
sub _setConf {
    my $confJson = shift;

    UBOS::Utils::writeJsonToFile( $CONF, $confJson );
}

##
# Ensure that the device is registered and has the appropriate key
# $token: the registration token entered by the user
# $registrationurl: URL to post the registration to
# $confJson: configuration JSON
# return: number of errors
sub _ensureRegistered {
    my $token           = shift;
    my $registrationurl = shift;
    my $confJson        = shift;

    trace( 'UbosLive::_ensureRegistered' );

    my $hostid      = UBOS::Host::hostId();
    my $arch        = UBOS::Utils::arch();
    my $deviceClass = UBOS::Utils::deviceClass();
    my $channel     = UBOS::Utils::channel();
    my $sku         = UBOS::Utils::sku();

    my $errors = 0;

    unless( $confJson->{registered} ) {
        $token =~ s!\s!!g;

        if(    !exists( $confJson->{wireguard} )
            || !exists( $confJson->{wireguard}->{client} )
            || !exists( $confJson->{wireguard}->{client}->{publickey} ))
        {
            error( 'Cannot register without Wireguard info' );
            return 1;
        }
        my $clientPublicKey = $confJson->{wireguard}->{client}->{publickey};

        my $cmd = "curl";
        $cmd   .= " --silent";
        $cmd   .= " -XPOST";
        $cmd   .= " -w '%{http_code}'";
        $cmd   .= " --data-urlencode 'token="               . $token           . "'";
        $cmd   .= " --data-urlencode 'wireguard-publickey=" . $clientPublicKey . "'";
        $cmd   .= " --data-urlencode 'hostid="              . $hostid          . "'";
        $cmd   .= " --data-urlencode 'arch="                . $arch            . "'";
        $cmd   .= " --data-urlencode 'deviceclass="         . $deviceClass     . "'";
        $cmd   .= " --data-urlencode 'channel="             . $channel         . "'";

        if( $sku ) {
            # might be a download, self-assembled
            $cmd   .= " --data-urlencode 'sku="     . $sku                . "'";
        }

        my $resultFile = tmpnam();

        $cmd   .= " '$registrationurl'";
        $cmd   .= " -o '$resultFile'";

        my $out;
        my $err;
        for( my $i=1 ; $i<=$MAX_REGISTRATION_TRIES ; ++$i ) { # prints better that way
            trace( "UBOS Live registration try $i\n" );

            my $status = UBOS::Utils::myexec( $cmd, undef, \$out, \$err );
            if( !$status && $out =~ m!200! ) {
                last;
            }
            if( -e $resultFile ) {
                UBOS::Utils::deleteFile( $resultFile );
            }

            info( 'UBOS Live registration unsucessful so far. Trying again in', $REGISTRATION_DELAY, 'seconds', "($i/$MAX_REGISTRATION_TRIES)" );
            sleep( $REGISTRATION_DELAY );
        }
        if( -e $resultFile ) {
            my $resultContent = UBOS::Utils::slurpFile( $resultFile );
            foreach my $resultLine ( split /\n/, $resultContent ) {
                if( $resultLine =~ m!^wireguard-publickey=(.+)$! ) {
                    $confJson->{wireguard}->{server}->{publickey} = $1;
                }
            }
        } else {
            $@ = 'Failed to register with UBOS Live.';
            ++$errors;
        }
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
