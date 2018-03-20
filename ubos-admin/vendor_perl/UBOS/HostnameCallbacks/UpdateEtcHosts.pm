#!/usr/bin/perl
#
# This callback updates /etc/hosts when a virtual hostname has been added or removed
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::HostnameCallbacks::UpdateEtcHosts;

use UBOS::Networking::NetConfigUtils;
use UBOS::Utils;

my $HOSTS_SEP = '### DO NOT EDIT ANYTHING BELOW THIS LINE, UBOS WILL OVERWRITE ###';
# after that line, the syntax is:
# <ip> <hostname> # <siteid>
# e.g.
# 192.168.140.1 example.com # s1234567890

##
# A site has been deployed to this host
# $siteId: the id of the site
# $hostname: the hostname of the site
# @nics: the network interfaces on which the site can be reached
sub deployed {
    my $siteId   = shift;
    my $hostname = shift;
    my @nics     = @_;

    unless( '*' eq $hostname ) {
        my @ips = ();
        map { push @ips, UBOS::Host::ipAddressesOnNic( $_ ) } @nics;
        my @ipsOnLan = grep { UBOS::Networking::NetConfigUtils::isOnLan( $_ ) } @ips;

        if( @ipsOnLan ) {
            my $ip = $ipsOnLan[0]; # take the first one

            my( $before, $after ) = _parseEtcHosts();

            $after .= "$ip $hostname # $siteId\n";

            _writeEtcHosts( $before, $after );
        }
    }

    return 1;
}

##
# A site with this hostname has been undeployed from this host
# $siteId: the id of the site
# $hostname: the hostname of the site
# @nics: the network interfaces on which the site can be reached
# @nics: the network interfaces on which the site can be reached
sub undeployed {
    my $siteId   = shift;
    my $hostname = shift;
    my @nics     = @_;

    unless( '*' eq $hostname ) {
        my( $before, $after ) = _parseEtcHosts();

        my $newAfter;
        foreach my $line ( split "\n", $after ) {
            if( $line !~ m!#\s*$siteId\s*$! ) {
                $newAfter .= $line;
                $newAfter .= "\n";
            }
        }
        _writeEtcHosts( $before, $newAfter );
    }

    return 1;
}

##
# Parse the /etc/hosts file
# return: ( $before, $after )
sub _parseEtcHosts {
    my $hosts = UBOS::Utils::slurpFile( '/etc/hosts' );

    my $before = undef;
    my $after  = undef;

    foreach my $line ( split "\n", $hosts ) {
        if( defined( $after )) {
            $after .= $line;
            $after .= "\n";
        } elsif( $line =~ m!^$HOSTS_SEP$! ) {
            $after  = '';
        } else {
            $before .= $line;
            $before .= "\n";
        }
    }
    unless( defined( $after )) {
        $after = ''; # If inexplicably the separator wasn't found
    }
    return( $before, $after );
}

##
# Write the /etc/hosts file
# $before: the content before the separator
# $after: the content after the separator
sub _writeEtcHosts {
    my $before = shift || '';
    my $after  = shift || '';

    my $content = "$before$HOSTS_SEP\n$after";
    UBOS::Utils::saveFile( '/etc/hosts', $content );
}

1;
