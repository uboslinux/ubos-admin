#!/usr/bin/perl
#
# Collects functionality related to LetsEncrypt.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::LetsEncrypt;

my $LETSENCRYPT_RENEW_DIR   = '/etc/letsencrypt/renew';
my $LETSENCRYPT_NORENEW_DIR = '/etc/letsencrypt/norenew';

my $_letsEncryptCertificatesStatus = undef; # allocated as needed

##
# Obtain a new certificate from LetsEncrypt
# $hostname: name of the host
# $webrootPath path to the web server's root directory
# $adminEmail: e-mail address of the administrator
# return: 1 if success
sub obtainCertificate {
    my $hostname    = shift;
    my $webrootPath = shift;
    my $adminEmail  = shift;

    my $out;
    my $err;
    my $ret = UBOS::Utils::myexec(
            'TERM=dumb'
            . ' certbot certonly'
            . ' --webroot'
            . " --email '" . $adminEmail . "'"
            . ' --agree-tos'
            . ' --no-self-upgrade'
            . ' --non-interactive'
            . " --webroot-path '" . $webrootPath . "'"
            . " -d '" . $hostname . "'",
            undef,
            \$out,
            \$err );

    if( $ret ) {
        warning( "Obtaining certificate from letsencrypt failed. proceeding without certificate or TLS/SSL.\n"
                 . "Make sure you are not running this behind a firewall, and that DNS is set up properly.\n"
                 . "Letsencrypt message:\n"
                 . $err );
        return 0;
    }
    return 1;
}

##
# Renew a certificate from LetsEncrypt
# $hostname: name of the host
# return: 1 if success
sub renewCertificate {
    my $hostname = shift;

    # We cannot actually renew just one, so it will be all of them

    my $out;
    my $err;
    my $ret = UBOS::Utils::myexec(
            'TERM=dumb'
            . ' certbot renew'
            . ' --quiet'
            . ' --agree-tos',
            undef,
            \$out,
            \$err );

    if( $ret ) {
        warning( "Renewing certificates from letsencrypt failed. proceeding without certificate or TLS/SSL.\n"
                 . "Make sure you are not running this behind a firewall, and that DNS is set up properly.\n"
                 . "Letsencrypt message:\n"
                 . $err );
        return 0;
    }
    return 1;
}

##
# Smart factory method to obtain information about all Letsencrypt certificates on this host
# $force: if true, do not use any cached values
# return: hash, keyed by hostname
sub determineCertificatesStatus {
    my $force = shift || 0;

    if( !$_letsEncryptCertificatesStatus || $force ) {
        my $out;
        if( UBOS::Utils::myexec(
                'TERM=dumb'
                . ' certbot certificates',
                undef,
                \$out,
                \$out )) {
            warning( "certbot certificates invocation failed" );
            return {};
        }

        $_letsEncryptCertificatesStatus = {};

        my @chunks = split( /Certificate Name:/, $out );
        shift @chunks; # discard first one
        foreach my $chunk ( @chunks ) {
            my $domain = undef;
            my $valid;
            my $certPath;
            my $keyPath;

            my @lines = split( /\n/, $chunk );
            foreach my $line ( @lines ) {
                if( $line =~ m!Domains:\s*(\S+)! ) {
                    $domain = $1;
                } elsif( $line =~ m!Expiry Date:.*\(([^)]+)\)! ) {
                    my $validInvalid = $1;
                    if( $validInvalid =~ m!INVALID! ) {
                        $valid = 0;
                    } else {
                        $valid = 1;
                    }
                } elsif( $line =~ m!Certificate Path:\s* (\S+)! ) {
                    $certPath = $1;

                } elsif( $line =~ m!Private Key Path:\s* (\S+)! ) {
                    $keyPath = $1;
                }
            }
            if( $domain ) {
                $_letsEncryptCertificatesStatus->{$domain} = {
                    'isvalid'  => $valid,
                    'certpath' => $certPath,
                    'keypath'  => $keyPath
                };
            }
        }
    }
    return $_letsEncryptCertificatesStatus;
}

##
# Determine the status of one certificate, for a certain host.
# $hostname: name of the host
# $force: if true, do not use any cached values
# return: undef if not known, JSON hash otherwise
sub determineCertificateStatus {
    my $hostname = shift;
    my $force    = shift || 0;

    my $status = determineCertificatesStatus( $force );
    if( exists( $status->{$hostname} )) {
        return $status->{$hostname};
    } else {
        return undef;
    }
}

##
# Move a Letsencrypt certificate from "renew" to "norenew" status (e.g.
# when a site is undeployed)
# $hostname: name of the host
# return: success or failure
sub makeCertificateNoRenew {
    my $hostname = shift;

    my $from = "$LETSENCRYPT_RENEW_DIR/$hostname.conf";
    if( -e $from ) {
        my $to = "$LETSENCRYPT_NORENEW_DIR/$hostname.conf";
        if( UBOS::Utils::move( $from, $to )) {
            return 1;
        } else {
            error( 'Failed to move file:', $from, $to );
            return 0;
        }
    } else {
        error( 'File does not exist:', $from );
        return 0;
    }
}

##
# Move a Letsencrypt certificate from "norenew" to "renew" status (e.g.
# when a previously undeployed TLS site is redeployed)
# $hostname: name of the host
# return: success or failure
sub makeCertificateRenew {
    my $hostname = shift;

    my $from = "$LETSENCRYPT_NORENEW_DIR/$hostname.conf";
    if( -e $from ) {
        my $to = "$LETSENCRYPT_RENEW_DIR/$hostname.conf";
        if( UBOS::Utils::move( $from, $to )) {
            return 1;
        } else {
            error( 'Failed to move file:', $from, $to );
            return 0;
        }
    } else {
        # No error here; it may never have been a TLS site
        return 0;
    }
}

1;
