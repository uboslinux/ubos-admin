#!/usr/bin/perl
#
# Collects functionality related to LetsEncrypt.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::LetsEncrypt;

use Time::Local;
use UBOS::Logging;
use UBOS::Host;
use UBOS::Utils;

my $LETSENCRYPT_ARCHIVE_DIR   = '/etc/letsencrypt/archive';   # created by certbot
my $LETSENCRYPT_LIVE_DIR      = '/etc/letsencrypt/live';      # created by certbot
my $LETSENCRYPT_RENEWAL_DIR   = '/etc/letsencrypt/renewal';   # created by certbot
my $LETSENCRYPT_NORENEWAL_DIR = '/etc/letsencrypt/norenewal'; # created by UBOS -- for the stash

my $_letsEncryptCertificatesStatus = undef; # allocated as needed

##
# Get the filenames of the LetsEncrypt key and certificate for a given
# hostname that is currently live (from a LetsEncrypt perspective) on this
# device.
# $hostname: name of the host
# return: ( file containing key, file containing crt ), or undef; error is in $@
sub getLiveKeyAndCertificateFiles {
    my $hostname = shift;

    return _getKeyAndCertificateFiles( $LETSENCRYPT_LIVE_DIR, $hostname );
}

##
# Get the filenames of the LetsEncrypt key and certificate for a given
# hostname that is current stashed on this device.
# $hostname: name of the host
# return: ( file containing key, file containing crt ), or undef; error is in $@
sub getStashedKeyAndCertificateFiles {
    my $hostname = shift;

    return _getKeyAndCertificateFiles( $LETSENCRYPT_NORENEWAL_DIR, $hostname );
}

##
# Helper to get the filenames of the LetsEncrypt key and certificate for
# a given hostname in a given directory.
# $dir: the directory to look in
# $hostname: name of the host
# return: ( key, crt ), or undef; error is in $@
sub _getKeyAndCertificateFiles {
    my $dir      = shift;
    my $hostname = shift;

    my $keyFile = "$dir/$hostname/privkey.pem";
    my $crtFile = "$dir/$hostname/fullchain.pem";

    if( -r $keyFile ) {
        if( -r $crtFile ) {
            return ( $keyFile, $crtFile );
        } else {
            $@ = 'Cannot read file: ' . $crtFile;
        }
    } else {
        $@ = 'Cannot read file: ' . $keyFile;
    }
    return undef;
}

##
# Register a LetsEncrypt account if needed. This happens automatically
# when the first certificate is getting provisioned, but we need this
# if the first certificate is imported rather than provisioned.
# $adminEmail: e-mail address of the administrator
# return: 1 if success or nothing was done; error message in $@
sub register {
    my $adminEmail  = shift;

    my $flags = UBOS::Host::vars()->get( 'host.certbotflags', '' );
    if( $flags ) {
        $flags = " $flags";
    }

    trace( 'Registering with LetsEncrypt' . $flags );

    my $cmd = 'TERM=dumb'
            . ' certbot register'
            . " --email '" . $adminEmail . "'"
            . ' --agree-tos'
            . ' --non-interactive'
            . $flags;

    my $out;
    my $ret = UBOS::Utils::myexec( $cmd, undef, \$out, \$out );

    if( $ret ) {
        $@ = "Registering with LetsEncrypt$flags failed:\n$out";

        debugAndSuspend( 'Certbot register failed' );
        return 0;
    }
    return 1;
}

##
# Obtain a new certificate from LetsEncrypt
# $hostname: name of the host
# $webrootPath path to the web server's root directory
# $adminEmail: e-mail address of the administrator
# return: 1 if success; error message in $@
sub provisionCertificate {
    my $hostname    = shift;
    my $webrootPath = shift;
    my $adminEmail  = shift;

    my $flags = UBOS::Host::vars()->get( 'host.certbotflags', '' );
    if( $flags ) {
        $flags = " $flags";
    }

    info( "Obtaining LetsEncrypt certificate$flags" );

    my $cmd = 'TERM=dumb'
            . ' certbot certonly'
            . ' --webroot'
            . " --email '" . $adminEmail . "'"
            . ' --agree-tos'
            . ' --no-self-upgrade'
            . ' --non-interactive'
            . " --webroot-path '" . $webrootPath . "'"
            . " -d '" . $hostname . "'"
            . $flags;

    my $out;
    my $ret = UBOS::Utils::myexec( $cmd, undef, \$out, \$out );

    if( $ret ) {
        $@ = "Obtaining certificate from LetsEncrypt$flags failed:\n$out";
        debugAndSuspend( 'Certbot certonly failed' );
        return 0;
    }
    return 1;
}

##
# Renew the certificates from LetsEncrypt. Certbot will decide which ones
# actually needed renwal.
# return: 1 if success
sub renewCertificates {

    my $flags = UBOS::Host::vars()->get( 'host.certbotflags', '' );
    if( $flags ) {
        $flags = " $flags";
    }

    info( "Renewing LetsEncrypt certificate(s)$flags" );

    my $cmd = 'TERM=dumb'
            . ' certbot renew'
            . ' --quiet'
            . ' --agree-tos'
            . $flags;

    my $out;
    my $ret = UBOS::Utils::myexec( $cmd, undef, \$out, \$out );

    if( $ret ) {
        $@ = "Renewing certificates from LetsEncrypt$flags failed:\n$out";
        debugAndSuspend( 'Certbot renew failed' );
        return 0;
    }
    return 1;
}

##
# Move a LetsEncrypt certificate from "renew" to "norenew" status (e.g.
# when a site is undeployed). We stash by moving conf file, and the
# domain's live directory into $LETSENCRYPT_NORENEWAL_DIR
# $hostname: name of the host
# return: success or failure
sub stashCertificate {
    my $hostname = shift;

    my $fromConf = "$LETSENCRYPT_RENEWAL_DIR/$hostname.conf";
    my $fromDir  = "$LETSENCRYPT_LIVE_DIR/$hostname";
    my $to       = "$LETSENCRYPT_NORENEWAL_DIR/";

    my $ret = 1;
    unless( -d $LETSENCRYPT_NORENEWAL_DIR ) {
        UBOS::Utils::mkdirDashP( $LETSENCRYPT_NORENEWAL_DIR );
    }

    if( -e $fromConf ) {
        if( !UBOS::Utils::move( $fromConf, $to )) {
            error( 'Failed to move:', $fromConf, $to );
            $ret = 0;
        }
    } else {
        # LetsEncrypt setup may have failed initially
        warning( 'File does not exist:', $fromConf );
    }
    if( -e $fromDir ) {
        if( !UBOS::Utils::move( $fromDir, $to )) {
            error( 'Failed to move:', $fromDir, $to );
            $ret = 0;
        }
    } else {
        # LetsEncrypt setup may have failed initially
        warning( 'Directory does not exist:', $fromDir );
    }

    return $ret;
}

##
# Move a LetsEncrypt certificate from "norenew" to "renew" status (e.g.
# when a previously undeployed TLS site is redeployed). Only invoke
# this if the certificate is known to be still valid.
# $hostname: name of the host
# return: success or failure
sub unstashCertificate {
    my $hostname = shift;

    my $fromConf = "$LETSENCRYPT_NORENEWAL_DIR/$hostname.conf";
    my $fromDir  = "$LETSENCRYPT_NORENEWAL_DIR/$hostname";
    my $toConf   = "$LETSENCRYPT_RENEWAL_DIR/$hostname.conf";
    my $toDir    = "$LETSENCRYPT_LIVE_DIR/$hostname";

    my $ret = 1;
    if( -e $fromConf ) {
        if( !UBOS::Utils::move( $fromConf, $toConf )) {
            error( 'Failed to move file:', $fromConf, $toConf );
            $ret = 0;
        }
    } else {
        warning( 'File does not exist:', $fromConf );
        $ret = 0;
    }
    if( -e $fromDir ) {
        if( !UBOS::Utils::move( $fromDir, $toDir )) {
            error( 'Failed to move file:', $fromDir, $toDir );
            $ret = 0;
        }
    } else {
        warning( 'Directory does not exist:', $fromDir );
        $ret = 0;
    }

    return $ret;
}

##
# Delete a stashed certificate
# $hostname: name of the host
# return: true or false
sub deleteStashedCertificate {
    my $hostname = shift;

    my $conf = "$LETSENCRYPT_NORENEWAL_DIR/$hostname.conf";
    my $dir  = "$LETSENCRYPT_NORENEWAL_DIR/$hostname";

    my $ret = 1;
    if( -e $conf ) {
        if( !UBOS::Utils::deleteFile( $conf )) {
            error( 'Failed to delete file:', $conf );
            $ret = 0;
        }
    }
    if( -e $dir ) {
        if( !UBOS::Utils::deleteRecursively( $dir )) {
            error( 'Failed to delete directory hierarchy:', $dir );
            $ret = 0;
        }
    }
    return $ret;
}

##
# Determine whether a certificate is currently live
# $hostname: name of the host
# return: true or false
sub isCertificateLive {
    my $hostname = shift;

    my $conf = "$LETSENCRYPT_RENEWAL_DIR/$hostname.conf";
    if( -e $conf ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine whether a certificate is currently stashed
# $hostname: name of the host
# return: true or false
sub isCertificateStashed {
    my $hostname = shift;

    my $conf = "$LETSENCRYPT_NORENEWAL_DIR/$hostname.conf";
    if( -e $conf ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine whether the certificate contained in this file has a sufficiently
# far-ahead expiration time, or already has or will shortly expire.
# $crtFile: name of the file containing the certificate
# return: true or false
sub certFileNeedsRenewal {
    my $crtFile = shift;

    my $out;
    if( UBOS::Utils::myexec( "openssl x509 -in '$crtFile' -dates -noout", undef, \$out )) {
        error( 'Failed to run opeenssl x509 against:', $crtFile );
        return undef; # better return value?
    }
    foreach my $line ( split( "\n", $out )) {
        # notAfter=Sep 22 17:52:55 2019 GMT
        # assuming no locale stuff
        if( $line =~ m!^notAfter=(\S+)\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)\s+(\S+)$! ) {
            my( $month, $day, $hour, $minute, $second, $year, $tz ) = ( $1, $2, $3, $4, $5, $6, $7 );
            if( $tz ne 'GMT' ) {
                error( 'Wrong time zone reported by openssl' );
                # but we continue, we are not too far off
            }
            my @months = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
            for( my $i=0 ; $i<@months ; ++$i ) {
                if( $month =~ m!^$months[$i]! ) {
                    $month = $i;
                    last;
                }
            }

            my $certTs = timegm( $second, $minute, $hour, $day, $month, $year-1900 );
            my $now    = UBOS::Utils::now();
            my $delta  = $certTs - $now;
            my $cutoff = UBOS::Host::vars()->get( 'host.letsencryptreissuecutoff', 172800 );

            trace( 'LetsEncrypt certFileNeedsRenewal for', $crtFile, 'returns', $delta, '<', $cutoff );

            return $delta < $cutoff;
        }
    }
    error( 'Failed to parse time stamp:', $out );

    return undef; # better return value
}

##
# Given a previously created key and cert, import them into the LetsEncrypt
# installation. This is used for device migration or restoring a still-valid
# LetsEncrypt certificate to a new device. Only invoke this if there is
# a valid LetsEncrypt account on the device.
# $hostname: name of the host
# $webroot: directory used by LetsEncrypt for renewals
# $key: the key
# $crt: the certificate
# $adminEmail: administrator e-mail in case we need to register
sub importCertificate {
    my $hostname = shift;
    my $webroot  = shift;
    my $key      = shift;
    my $crt      = shift;
    my $adminEmail  = shift;

    if( -e "$LETSENCRYPT_RENEWAL_DIR/$hostname.conf" ) {
        error( 'Letsencrypt config already exists for this hostname, cannot import:', $hostname );
        return 0;
    }

    my @accountIds = accountIdentifiers();
    unless( @accountIds ) {
        unless( register( $adminEmail )) {
            error( $@ );
            return 0;
        }
        @accountIds = accountIdentifiers();
        unless( @accountIds ) {
            error( 'No LetsEncrypt account found' );
            return 0;
        }
    }

    foreach my $dir ( $LETSENCRYPT_RENEWAL_DIR, "$LETSENCRYPT_ARCHIVE_DIR/$hostname", "$LETSENCRYPT_LIVE_DIR/$hostname" ) {
        unless( -d $dir ) {
            UBOS::Utils::mkdirDashP( $dir, 0700 );
        }
    }
    my $accountId = $accountIds[0];

    UBOS::Utils::saveFile( "$LETSENCRYPT_RENEWAL_DIR/$hostname.conf", <<CONTENT, 0644 );
# renew_before_expiry = 30 days
version = 0.32.0
archive_dir = /etc/letsencrypt/archive/$hostname
cert = /etc/letsencrypt/live/$hostname/cert.pem
privkey = /etc/letsencrypt/live/$hostname/privkey.pem
chain = /etc/letsencrypt/live/$hostname/chain.pem
fullchain = /etc/letsencrypt/live/$hostname/fullchain.pem

# Options used in the renewal process
[renewalparams]
account = 6bf0fdc8237f055b6f18bdfd4e53781d
authenticator = webroot
webroot_path = $webroot,
server = https://acme-v02.api.letsencrypt.org/directory
[[webroot_map]]
$hostname = $webroot
CONTENT

    my $i = 1; # In case there are some leftovers from some previous deployment of the same site
    while( -e "$LETSENCRYPT_ARCHIVE_DIR/$hostname/privkey$i.pem" ) {
        ++$i;
    }

    # save the same full cert in all three places
    UBOS::Utils::saveFile( "$LETSENCRYPT_ARCHIVE_DIR/$hostname/privkey$i.pem",   $key, 0644 );
    UBOS::Utils::saveFile( "$LETSENCRYPT_ARCHIVE_DIR/$hostname/fullchain$i.pem", $crt, 0644 );
    UBOS::Utils::saveFile( "$LETSENCRYPT_ARCHIVE_DIR/$hostname/chain$i.pem",     $crt, 0644 );
    UBOS::Utils::saveFile( "$LETSENCRYPT_ARCHIVE_DIR/$hostname/cert$i.pem",      $crt, 0644 );

    UBOS::Utils::symlink( "../../archive/$hostname/privkey$i.pem",   "$LETSENCRYPT_LIVE_DIR/$hostname/privkey.pem" );
    UBOS::Utils::symlink( "../../archive/$hostname/fullchain$i.pem", "$LETSENCRYPT_LIVE_DIR/$hostname/fullchain.pem" );
    UBOS::Utils::symlink( "../../archive/$hostname/chain$i.pem",     "$LETSENCRYPT_LIVE_DIR/$hostname/chain.pem" );
    UBOS::Utils::symlink( "../../archive/$hostname/cert$i.pem",      "$LETSENCRYPT_LIVE_DIR/$hostname/cert.pem" );
}

##
# Determine the ACME account identifiers present on this device
# return: array of account identifiers, may be empty
sub accountIdentifiers {

    my @privateKeyFiles = </etc/letsencrypt/accounts/*/*/*/private_key.json>;
    my @ret = map { m!/etc/letsencrypt/.*directory/([a-f0-9]+)/private_key.json!; $1; } @privateKeyFiles;
    return @ret;
}

1;
