#!/usr/bin/perl
#
# Collection of utility methods for UBOS network configuration management.
#
# This file is part of ubos-networking.
# (C) 2012-2015 Indie Computing Corp.
#
# ubos-networking is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-networking is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-networking.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigUtils;

use Cwd;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $ipLinks        = undef;

my $avahiConfigFile             = '/etc/avahi/avahi.conf';
my $nftablesConfigFile          = '/etc/ubos-nftables.conf';
my $openPortsFilePattern        = '/etc/ubos/open-ports/*.open-port';
my $dotNetworkDefaultFile       = '/etc/systemd/network/99-ubos-default.network';
my $dotNetworkDhcpFilePattern   = '/etc/systemd/network/50-ubos-dhcp-%s.network';
my $dotNetworkStaticFilePattern = '/etc/systemd/network/50-ubos-static-%s.network';
my $dotNetworkDeleteGlob        = '/etc/systemd/network/??-ubos-*.network';
my $etherGlobs                  = 'en* eth*';
my $wlanGlobs                   = 'wifi* wlan*';

##
# Find all NetConfigs
# return: hash of net config name to package name
sub findNetConfigs {
    my $ret = UBOS::Utils::findPerlShortModuleNamesInPackage( 'UBOS::Networking::NetConfigs' );

    return $ret;
}

##
# Activate a NetConfig by name
# $newConfigName: name of the NetConfig
sub activateNetConfig {
    my $newConfigName = shift;
    
    my $netConfigs = findNetConfigs();

    if( exists( $netConfigs->{$newConfigName} ) {
        my $newConfig  = $netConfigs->{$newConfigName};
        UBOS::Utils::invokeMethod( $newConfig . '::activate' );

    } else {
        fatal( 'Unknown netconfig', $newConfigName );
    }
    return 1;
}

##
# Find all network interfaces
sub getAllNics {
	my $all = _ipLinks();

	return $all;
}

##
# Set a particular networking configuration. This method has different
# ways of invoking it, so pay attention.
# $name: name of the configuration for reporting purposes
# $dhcpClientNicInfo:
#      if this is an array, it contains the list of NIC names that shall
#          receive their IP address via DHCP
#      if this is 1, it means all NICs not otherwise listed shall receive
#          their IP address via DHCP
#      if this is undef, it means no NIC shall receive their IP address
#          via DHCP
# $privateNetworkNicInfo:
#      if this is an array, it contains the list of NIC names that shall
#          be assigned a locally managed IP address, e.g. in 192.168.0.0/16
#      if this is 1, it means all NICs not otherwise listed shall be
#          assigned a locally managed IP address
#      if this is undef, it means no NIC shall be assigned a locally
#          managed IP address
# if both parameters are undef, it means deactivate all interfaces.
# if both parameters are NOT undef, NAT shall be setup between the two
#
# $notLocalNics:
#      if this is an array, it contains the list of NIC names that go to the
#          WAN and that should not advertise or let through any sensitive info
#      if this is 1, it means that all NICs shall not advertise or let through
#          any sensitive info
#      if this is 0, it means that all NICs are on a friendly LAN
#
# Examples:
# setNetConfig( 'off',    undef, undef ) -- deactivate all interfaces
# setNetConfig( 'foo',    [ eth0 ], undef ) -- only activate eth0 as DHCP client
# setNetConfig( 'client', 1, undef ) -- all interfaces are DHCP clients
# setNetConfig( 'bar',    undef, [eth0, eth1] ) -- assign static IP addresses to eth0 and eth1

sub setNetConfig {
    my $name                  = shift;
    my $dhcpClientNicInfo     = shift;
    my $privateNetworkNicInfo = shift;
    my $notLocalNics          = shift;

    my $allNics = UBOS::Host::nics();

    # error checking
    if(    defined( $dhcpClientNicInfo )     && !ref( $dhcpClientNicInfo )     && $dhcpClientNicInfo == 1
        && defined( $privateNetworkNicInfo ) && !ref( $privateNetworkNicInfo ) && $privateNetworkNicInfo == 1 )
    {
        fatal( 'Must not specify 1 (all) for both dhcpClientNicInfo and privateNetworkNicInfo' );
    }
    if( ref( $dhcpClientNicInfo ) eq 'ARRAY' && ref( $privateNetworkNicInfo ) eq 'ARRAY' ) {
        foreach my $nic1 ( @$dhcpClientNicInfo ) {
            foreach my $nic2 ( @$privateNetworkNicInfo ) {
                if( $nic1 eq $nic2 ) {
                    fatal( 'Network interface', $nic1, 'given in both dhcpClientNicInfo and privateNetworkNicInfo' );
                }
            }
            unless( defined( $allNics->{$nic1} )) {
                fatal( 'Unknown network interface', $nic1 );
            }
        }
        foreach my $nic2 ( @$privateNetworkNicInfo ) {
            unless( defined( $allNics->{$nic2} )) {
                fatal( 'Unknown network interface', $nic2 );
            }
        }
    }

    # delete the current systemd-networkd settings
    UBOS::Utils::deleteFile( glob $dotNetworkDeleteGlob );

    # create new systemd-networkd settings
    if( defined( $dhcpClientNicInfo )) {
        if( ref( $dhcpClientNicInfo )) {
            foreach my $nic ( @$dhcpClientNicInfo ) {
                UBOS::Utils::saveFile( sprintf( $dotNetworkDhcpFilePattern, $nic ), <<END );
#
# DHCP interface configuration. Generated automatically, do not modify. Use
#     ubos-admin setnetconfig
# instead.
#

[Match]
Name=$nic

[Network]
DHCP=ipv4
END
            }
        } else {
            UBOS::Utils::saveFile( $dotNetworkDefaultFile, <<END );
#
# Fallback configuration. Generated automatically, do not modify. Use
#     ubos-admin setnetconfig
# instead.
#

[Match]
Name=$etherGlobs $wlanGlobs

[Network]
DHCP=ipv4
END
        }
    }
    if( defined( $privateNetworkNicInfo )) {
        if( ref( $privateNetworkNicInfo )) {
            foreach my $nic ( @$privateNetworkNicInfo ) {
                UBOS::Utils::saveFile( sprintf( $dotNetworkStaticFilePattern, $nic ), <<END );
#
# Static interface configuration. Generated automatically, do not modify. Use
#     ubos-admin setnetconfig
# instead.
#

[Match]
Name=$nic

[Network]
Address=0.0.0.0/16
END
            }
        } else {
            UBOS::Utils::saveFile( $dotNetworkDefaultFile, <<END );
#
# Fallback configuration. Generated automatically, do not modify. Use
#     ubos-admin setnetconfig
# instead.
#

[Match]
Name=$etherGlobs $wlanGlobs

[Network]
Address=0.0.0.0/16
END
        }
    }
    foreach my $nic ( keys %$allNics ) {
        UBOS::Utils::myexec( "ip addr flush " . $nic );
    }

    if( defined( $dhcpClientNicInfo ) || defined( $privateNetworkNicInfo )) {
        UBOS::Utils::saveFile( '/etc/nsswitch.conf', <<END );
hosts: files mdns_minimal [NOTFOUND=return] dns myhostname
END
    } else {
        UBOS::Utils::saveFile( '/etc/nsswitch.conf', <<END );
hosts: files dns myhostname
END
    }

    # NAT
    my @openPorts = _determineOpenPorts();
    my $openPortsString;
    foreach my $portSpec ( @openPorts ) {
        # tcp dport ssh accept
        if( $portsSpec =~ m!(.+)/tcp! ) {
            $openPortsString .= "    tcp dport $1 accept\n";
        } elsif( $portsSpec =~ m!(.+)/udp! ) {
            $openPortsString .= "    udp dport $1 accept\n";
        } else {
            error( 'Unknown open ports spec:', $portsSpec );
        }
    }
    if( defined( $dhcpClientNicInfo ) && defined( $privateNetworkNicInfo )) {
        # NAT
        UBOS::Utils::saveFile( $nftablesConfigFile, <<END, 0644 );
#
# The nftables configuration for UBOS. Generated automatically, do not modify
#
table inet filter {
  chain input {
    type filter hook input priority 0;

    # allow established/related connections
    ct state {established, related} accept

    # early drop of invalid connections
    ct state invalid drop

    # allow from loopback
    iifname lo accept

    # allow icmp
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

$openPortsString

    # everything else
    reject with icmp type port-unreachable
  }
  chain forward {
    type filter hook forward priority 0;
    drop
  }
  chain output {
    type filter hook output priority 0;
  }
}
table nat {
  chain prerouting {
    type nat hook prerouting priority -150;
  }
  chain postrouting {
    type nat hook postrouting priority -150;
  }
}
END
    } else {
        # no NAT, just firewall
        UBOS::Utils::saveFile( $nftablesConfigFile, <<END, 0644 );
#
# The nftables configuration for UBOS. Generated automatically, do not modify
#
table inet filter {
  chain input {
    type filter hook input priority 0;

    # allow established/related connections
    ct state {established, related} accept

    # early drop of invalid connections
    ct state invalid drop

    # allow from loopback
    iifname lo accept

    # allow icmp
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

$openPortsString

    # everything else
    reject with icmp type port-unreachable
  }
  chain forward {
    type filter hook forward priority 0;
    drop
  }
  chain output {
    type filter hook output priority 0;
  }
}
END
    }    

    # Avahi
    if( !defined( $notLocalNics ) || !$notLocalNics ) {
        if( -e $avahiConfigFile ) {
            UBOS::Utils::deleteFile( $avahiConfigFile );
        }

    } elsif( ref( $notLocalNics ) eq 'ARRAY' ) {
        my $denyString = join( ', ', @$notLocalNics );
        UBOS::Utils::saveFile( $avahiConfigFile, <<END, 0644 );
#
# The avahi configuration for UBOS. Generated automatically, do not modify
#

[server]
#domain-name=local
browse-domains=
use-ipv4=yes
use-ipv6=no
ratelimit-interval-usec=1000000
ratelimit-burst=1000
deny-interfaces=$denyString

[wide-area]
enable-wide-area=no

[publish]
publish-hinfo=no
publish-workstation=no
publish-domain=yes
publish-resolv-conf-dns-servers=no
publish-aaaa-on-ipv4=no
publish-a-on-ipv6=no

[reflector]
enable-reflector=no
reflect-ipv=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
END
    } else {
        # all friendly
        UBOS::Utils::saveFile( $avahiConfigFile, <<END, 0644 );
#
# The avahi configuration for UBOS. Generated automatically, do not modify
#

[server]
#domain-name=local
browse-domains=
use-ipv4=yes
use-ipv6=no
ratelimit-interval-usec=1000000
ratelimit-burst=1000

[wide-area]
enable-wide-area=no

[publish]
publish-hinfo=no
publish-workstation=no
publish-domain=yes
publish-resolv-conf-dns-servers=no
publish-aaaa-on-ipv4=no
publish-a-on-ipv6=no

[reflector]
enable-reflector=no
reflect-ipv=no

[rlimits]
rlimit-core=0
rlimit-data=4194304
rlimit-fsize=0
rlimit-nofile=768
rlimit-stack=4194304
rlimit-nproc=3
END
    }
}

##
# Helper method to determine which nic should be the upstream interface
#
# return: name of the nic
sub determineUpstreamNic {
    my $allNics = UBOS::Host::nics();
    my $conf    = netConfig();

    my $upstreamNic = undef;
    if( exists( $conf->{upstream} )) {
        $upstreamNic = $conf->{upstream};

        unless( exists( $allNics->{upstreamNic} )) {
            UBOS::Logging::warning( 'Upstream NIC specified in', $confFile, 'not found:', $upstreamNic );
            $upstreamNic = undef;
        }
    }
    unless( $upstreamNic ) {
        # take the first wired one, if that fails, the first wifi one
        my $firstEther = undef;
        my $firstWlan  = undef;
        my $bestEtherIndex = 65535;
        my $bestWlanIndex  = 65535;

        foreach my $nic ( keys %$allNics ) {
            my $data  = $allNics->{$nic};
            my $index = $data->{index};
            if( 'ether' eq $data->{type} ) {
                if( $index < $bestEtherIndex ) {
                    $bestEtherIndex = $index;
                    $firstEther     = $nic;
                }
            } elsif( 'wlan' eq $data->{type} ) {
                if( $index < $bestWlanIndex ) {
                    $bestWlanIndex = $index;
                    $firstWlan     = $nic;
                }
            } # ignore others
        }
        if( $firstEther ) {
            $upstreamNic = $firstEther;
        } else { # this may be null
            $upstreamNic = $firstWlan;
        }
    }
    return $upstreamNic;
}


##
# Consistently sort NIC names. Keep numerically ordered within groups.
# Must declare prototype, otherwise shift won't work.
sub compareNics($$) {
    my $a = shift;
    my $b = shift;

    if( $a =~ m!^([a-z]+)(\d+)$! ) { # e.g. eth0, wifi0
        my( $a1, $a2 ) = ( $1, $2 );

        if( $b =~ m!^([a-z]+)(\d+)$! ) {
            my( $b1, $b2 ) = ( $1, $2 );

            if( $a1 eq $b1 ) {
                return $a2 <=> $b2;
            }
        }
    } elsif( $a =~ m!^([a-z]+)(\d+)([a-z]+)(\d+)$! ) { # e.g. enp0s0
        my( $a1, $a2, $a3, $a4 ) = ( $1, $2, $3, $4 );
        
        if( $b =~ m!^([a-z]+)(\d+)([a-z]+)(\d+)$! ) {
            my( $b1, $b2, $b3, $b4 ) = ( $1, $2, $3, $4 );
            
            if( $a1 eq $b1 ) {
                if( $a2 == $b2 ) {
                    if( $a3 eq $b3 ) {
                        return $a4 <=> $b4;
                    } else {
                        return $a3 cmp $b3;
                    }
                } else {
                    return $a2 <=> $b2;
                }
            }
        }
    }
    return $a cmp $b; # big "else"
}

##
# Determine the list of open ports
# return: list of ports
sub _determineOpenPorts {

    my $all;
    foreach my $file ( glob $openPortsFilePattern ) {
        my $found = UBOS::Utils::slurpFile( $file );
        $all .= "$found\n";
    }
    my %ret = ();
    map { my $s = $_; $s =~ s!^\s+!! ; $s =~ s!\s+$!! ; $ret{$s} = 1; } grep { $_ } split /\n/, $all;

    return sort keys %$ret;
}

1;
