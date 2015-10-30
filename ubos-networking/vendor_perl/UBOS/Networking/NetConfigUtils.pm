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

use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $avahiConfigFile             = '/etc/avahi/ubos-avahi.conf';
my $nftablesConfigFile          = '/etc/ubos-nftables.conf';
my $dnsmasqConfigFile           = '/etc/dnsmasq.ubos.d/50-ubos-admin-generated.conf';
my $openPortsFilePattern        = '/etc/ubos/open-ports.d/*';
my $dotNetworkFilePattern       = '/etc/systemd/network/50-ubos-%s.network';
my $dotNetworkDeleteGlob        = '/etc/systemd/network/??-ubos-*.network';
my $etherGlobs                  = 'en* eth*';
my $wlanGlobs                   = 'wifi* wlan*';
my $containerVeth               = 'host0';
my $networkingDefaultsConfFile  = '/etc/ubos/networking-defaults.json';
my $_networkingDefaultsConf     = undef; # cached content of $networkingDefaultsConfFile
my $netconfigConfFilePattern    = '/etc/ubos/netconfig-%s.json';
my $_netconfigConfs             = {}; # cached content of $netconfigConfFilePattern, keyed by netconfig name

# Regardless of Netconfig, always run these
my %alwaysServices = (
        'systemd-networkd.service'  => 1,
        'systemd-networkd.socket'   => 1,
        'systemd-resolved.service'  => 1,
        'ubos-nftables.service'     => 1
);

# All services possibly started/stopped. Depending on Netconfig, not all of
# them may actually be installed.
my %allServices = (
        %alwaysServices,
        'avahi-daemon.service' => 1,
        'avahi-daemon.socket'  => 1,
        'cloud-final.service'  => 1,
        'dnsmasq.service'      => 1
);
                   
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
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
sub activateNetConfig {
    my $newConfigName = shift;
    my $initOnly      = shift;

    my $netConfigs = findNetConfigs();

    if( exists( $netConfigs->{$newConfigName} )) {
        my $newConfig  = $netConfigs->{$newConfigName};

        debug( 'Activating netconfig', $newConfigName );

        return UBOS::Utils::invokeMethod( $newConfig . '::activate', $initOnly );

    } else {
        fatal( 'Unknown netconfig', $newConfigName );
    }
}

##
# Read the networking defaults, if any. Set defaults if needed
sub networkingDefaults() {
    unless( $_networkingDefaultsConf ) {
        my $doWrite     = 0; # info has been updated
        my $skipWriting = 0; # but it would not be safe to write
        if( -e $networkingDefaultsConfFile ) {
            $_networkingDefaultsConf = UBOS::Utils::readJsonFromFile( $networkingDefaultsConfFile );
            unless( $_networkingDefaultsConf ) {
                warning( 'Networking defaults file is malformed, falling back to built-in defaults:', $networkingDefaultsConfFile );
                $skipWriting = 1;
            }
        }
        unless( $_networkingDefaultsConf ) {
            $_networkingDefaultsConf = {};
            $doWrite = 1;
        }
        if( exists( $_networkingDefaultsConf->{networks} )) {
            foreach my $ip ( sort keys %{$_networkingDefaultsConf->{networks}} ) {
                unless( exists( $_networkingDefaultsConf->{networks}->{$ip}->{prefixsize} )) {
                    error( 'prefixsize missing for network', $ip, 'in', $networkingDefaultsConfFile );
                    $_networkingDefaultsConf->{networks}->{$ip}->{prefixsize} = 32; # that seems a safe default
                }
            }
        }
        unless( exists( $_networkingDefaultsConf->{networks} )) {
            $_networkingDefaultsConf->{networks} = {
                # keys: IP addresses of the interfaces of this device connected to the subnet
                # prefixsize: /xx of the subnet
                # e.g. subnet 192.168.140.0/24 with interface IP 192.168.140.1
                "192.168.140.1" => {
                    "prefixsize" => 24
                },
                "192.168.141.1" => {
                    "prefixsize" => 24
                },
                "192.168.142.1" => {
                    "prefixsize" => 24
                },
                "192.168.143.1" => {
                    "prefixsize" => 24
                },
                "192.168.144.1" => {
                    "prefixsize" => 24
                },
                "192.168.145.1" => {
                    "prefixsize" => 24
                },
                "192.168.146.1" => {
                    "prefixsize" => 24
                },
                "192.168.147.1" => {
                    "prefixsize" => 24
                }
            };
            $doWrite = 1;
        }
        unless( exists( $_networkingDefaultsConf->{'dhcp-lease'} )) {
            $_networkingDefaultsConf->{'dhcp-lease'} = '12h';
        }
        if( $doWrite && !$skipWriting ) {
            UBOS::Utils::writeJsonToFile( $networkingDefaultsConfFile, $_networkingDefaultsConf );
        }
    }
    return $_networkingDefaultsConf;
}

##
# Read the config file for a netconfig with a certain name. If the file doesn't exist,
# return an empty hash. If the file exists but is malformed, emit error and return undef
# $name: name of the netconfig
# return: JSON hash
sub readNetconfigConfFileFor {
    my $name = shift;

    my $file = sprintf( $netconfigConfFilePattern, $name );
    unless( -e $file ) {
        return {};
    }
    my $ret = UBOS::Utils::readJsonFromFile( $file, sub { ( 'Error when parsing configuration for netconfig', $name, '(file', $file, ')' ) } );
    return $ret;
}

##
# Write the config file for a netconfig with a certain name.
# $name: name of the netconfig
# $json: JSON hash to write
sub saveNetconfigConfFileFor {
    my $name = shift;
    my $json = shift;

    my $file = sprintf( $netconfigConfFilePattern, $name );
    UBOS::Utils::writeJsonToFile( $file, $json );
}

##
# Set a particular networking configuration. The various NetConfig objects
# invoking this pass a hash that tells this method what services to run,
# which interfaces to config how etc.
# $name: name of the netconfig for reporting purposes
# $config: the config JSON object
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
sub configure {
    my $name     = shift;
    my $config   = shift;
    my $initOnly = shift;

    my %servicesNeeded = ( %alwaysServices ); # Run these services after generating config files
    my $isRouter       = 0;

    # systemd.network files
    foreach my $nic ( keys %$config ) {
        my $dotNetworkContent = <<END;
#
# UBOS networking configuration for $nic
# Do not edit, your changes will be mercilessly overwritten.
#
[Match]
Name=$nic

[Network]
END
        if( exists( $config->{$nic}->{address} )) {
            $dotNetworkContent .= 'Address=' . $config->{$nic}->{address} . "\n";
        }
        if( exists( $config->{$nic}->{dhcp} ) && $config->{$nic}->{dhcp} ) {
            $dotNetworkContent .= "DHCP=yes\n";
        }

        UBOS::Utils::saveFile( sprintf( $dotNetworkFilePattern, $nic ), $dotNetworkContent );
    }

    # Avahi
    my $avahiAllowInterfacesString = '';
    foreach my $nic ( sort keys %$config ) {
        if( exists( $config->{$nic}->{mdns} ) && $config->{$nic}->{mdns} ) {
            $servicesNeeded{'avahi-daemon.service'} = 1;
            $servicesNeeded{'avahi-daemon.socket'}  = 1;
            if( $avahiAllowInterfacesString ) {
                $avahiAllowInterfacesString .= ' ';
            }
            $avahiAllowInterfacesString .= $nic;
        }
    }

    my $foundNsswitchHostLine = 0;
    my @nsswitchContent       = split( /\n/, UBOS::Utils::slurpFile( '/etc/nsswitch.conf' ));
    for( my $i=0 ; $i<@nsswitchContent ; ++$i ) {
        if( $nsswitchContent[$i] =~ m!^(\s*hosts\s*:\s*)(.*)$! ) {
            my $prefix = $1;
            my @args   = split( /\s+/, $2 );

            @args = grep { $_ !~ m!^mdns! && $_ ne '[NOTFOUND=return]' } @args;

            if( exists( $servicesNeeded{'avahi-daemon.service'} )) {
                # insert before dns or resolve or myhostname
                my $insertHere = @args;
                for( my $j=@args-1 ; $j>=0 ; --$j ) {
                    if( $args[$j] eq 'myhostname' || $args[$j] eq 'dns' || $args[$j] eq 'resolve' ) {
                        $insertHere = $j;
                    }
                }
                splice @args, $insertHere, 0, 'mdns_minimal', '[NOTFOUND=return]';
            }

            $nsswitchContent[$i] = $prefix . join( ' ', @args );
            $foundNsswitchHostLine = 1;
        }
    }
    unless( $foundNsswitchHostLine ) {
        if( exists( $servicesNeeded{'avahi-daemon.service'} ) ) {
            push @nsswitchContent, "hosts: files mymachines mdns_minimal [NOTFOUND=return] dns myhostname";
        } else {
            push @nsswitchContent, "hosts: files mymachines dns myhostname";
        }
    }
    UBOS::Utils::saveFile( '/etc/nsswitch.conf', map { "$_\n" } @nsswitchContent );

    if( exists( $servicesNeeded{'avahi-daemon.service'} )) {
        UBOS::Utils::saveFile( $avahiConfigFile, <<END, 0644 );
#
# The avahi configuration for UBOS.
# Do not edit, your changes will be mercilessly overwritten.
#

[server]
#domain-name=local
browse-domains=
use-ipv4=yes
use-ipv6=no
ratelimit-interval-usec=1000000
ratelimit-burst=1000
allow-interfaces=$avahiAllowInterfacesString

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
    } elsif( -e $avahiConfigFile ) {
        UBOS::Utils::deleteFile( $avahiConfigFile );
    }

    # dnsmasq
    my $dnsmasqConfigContent = '';
    foreach my $nic ( sort keys %$config ) {
        if( exists( $config->{$nic}->{dhcpserver} ) && $config->{$nic}->{dhcpserver} ) {
            my $range = _calculateDhcpRange( $config->{$nic} );

            $dnsmasqConfigContent .= <<END;
interface=$nic
dhcp-range=$range
END
            $servicesNeeded{'dnsmasq.service'} = 1;
        }
    }
    if( exists( $servicesNeeded{'dnsmasq.service'} )) {
        UBOS::Utils::saveFile( $dnsmasqConfigFile, $dnsmasqConfigContent );
        
    } elsif( -e $dnsmasqConfigFile ) {
        UBOS::Utils::deleteFile( $dnsmasqConfigFile );
    }

    # determine the appropriate content to insert into nftables configuration
    # for those interfaces that have application ports open
    my @openPorts = _determineOpenPorts();
    my $openPortsString = '';

    foreach my $portSpec ( @openPorts ) {
        if( $portSpec =~ m!(.+)/tcp! ) {
            $openPortsString .= "    tcp dport $1 accept\n";
        } elsif( $portSpec =~ m!(.+)/udp! ) {
            $openPortsString .= "    udp dport $1 accept\n";
        } else {
            error( 'Unknown open ports spec:', $portSpec );
        }
    }
    
    # firewall / masquerade / netfilter
    my $nftablesContent = <<END;
#
# UBOS nftables configuration
# Do not edit, your changes will be mercilessly overwritten.
#

# lo
table inet filter {
  chain input { # This chain serves as a dispatcher
    type filter hook input priority 0;
    iifname lo accept

END
    foreach my $nic ( sort keys %$config ) {
        $nftablesContent .= <<END;
    iifname $nic jump input_$nic
END
    }

    $nftablesContent .= <<END;

    reject with icmp type port-unreachable
  }
END
    foreach my $nic ( sort keys %$config ) {
        $nftablesContent .= <<END;
  chain input_$nic {
END
        if( exists( $config->{$nic}->{state} ) && $config->{$nic}->{state} eq 'off' ) {
            $nftablesContent .= <<END;
    reject with icmp type port-unreachable
END

        } else {
            $nftablesContent .= <<END;
    ct state {established, related} accept
    ct state invalid drop
END
            if( exists( $config->{$nic}->{dhcp} ) && $config->{$nic}->{dhcp} ) {
                $nftablesContent .= "    udp dport bootpc accept\n";
                $nftablesContent .= "    tcp dport bootpc accept\n";
            }
            if( exists( $config->{$nic}->{dhcpserver} ) && $config->{$nic}->{dhcpserver} ) {
                $nftablesContent .= "    udp dport bootps accept\n";
                $nftablesContent .= "    tcp dport bootps accept\n";
            }
            if( exists( $config->{$nic}->{dns} ) && $config->{$nic}->{dns} ) {
                $nftablesContent .= "    udp dport domain accept\n";
                $nftablesContent .= "    tcp dport domain accept\n";
            }
            if( exists( $config->{$nic}->{mdns} ) && $config->{$nic}->{mdns} ) {
                $nftablesContent .= "    udp dport mdns accept\n";
                $nftablesContent .= "    tcp dport mdns accept\n";
            }
            if( exists( $config->{$nic}->{ports} ) && $config->{$nic}->{ports} ) {
                $nftablesContent .= $openPortsString;
            }
            if( exists( $config->{$nic}->{ssh} ) && $config->{$nic}->{ssh} ) {
                $nftablesContent .= "    tcp dport ssh accept\n";
            }

            $nftablesContent .= <<END;
    ip protocol icmp accept
    ip6 nexthdr icmpv6 accept

    reject with icmp type port-unreachable
END
        }

        $nftablesContent .= <<END;
  }
END
        if( exists( $config->{$nic}->{masquerade} ) && $config->{$nic}->{masquerade} ) {
            $isRouter = 1;
            $nftablesContent .= <<END;
#  chain prerouting {
#      type nat hook prerouting priority 0;
#  }
#
#  chain postrouting {
#    masquerade
#  }
#
END
        }
    }

    $nftablesContent .= <<END;

  chain forward {
    type filter hook forward priority 0;
  }

  chain output { # for now, we let everything out
    type filter hook output priority 0;
    accept
  }
}

END

    UBOS::Utils::saveFile( $nftablesConfigFile, $nftablesContent );
    

    # cloud-init
    foreach my $nic ( keys %$config ) {
        if( exists( $config->{$nic}->{'cloud-init'} ) && $config->{$nic}->{'cloud-init'} ) {
            $servicesNeeded{'cloud-final.service'} = 1;
            last;
        }
    }

    # packet forwarding
    UBOS::Utils::saveFile( '/etc/sysctl.d/ip_forward.conf', 'net.ipv4.ip_forward=' . ( $isRouter ? 1 : 0 ) . "\n" );
    UBOS::Utils::myexec( "sudo systemctl restart systemd-sysctl.service" );
    
    # Start / stop / restart / enable / disable services

    my @runningServices;
    my @installedServices;
    my @enabledServices;
    my %enabledServices;
    my @toDisable;
    my @toEnable;

    if( $initOnly ) {
        @runningServices   = ();
        @installedServices = ();
        @enabledServices   = ();
        %enabledServices   = ();
        @toDisable         = ();
        @toEnable          = keys %servicesNeeded;
        
    } else {
        my $out;
        UBOS::Utils::myexec( 'systemctl list-units --no-legend --no-pager -a --state=active', undef, \$out );
        @runningServices = grep { exists( $allServices{$_} ) } map { my $s = $_; $s =~ s!\s+.*$!!; $s; } split /\n/, $out;

        UBOS::Utils::myexec( 'systemctl list-units --no-legend --no-pager -a', undef, \$out );
        @installedServices = grep { exists( $allServices{$_} ) } map { my $s = $_; $s =~ s!\s+.*$!!; $s; } split /\n/, $out;

        @enabledServices   = grep { my $o; UBOS::Utils::myexec( 'systemctl is-enabled ' . $_, undef, \$o ); $o =~ m!enabled!; } @installedServices;
        %enabledServices   = ();
        map { $enabledServices{$_} = 1; } @enabledServices; # hash is easier

        @toDisable = grep { !exists( $servicesNeeded{$_}  ) } @enabledServices;
        @toEnable  = grep { !exists( $enabledServices{$_} ) } keys %servicesNeeded;
    }

    if( @toDisable ) {
        UBOS::Utils::myexec( 'sudo systemctl disable -q ' . join( ' ', @toDisable ));
    }
    if( @toEnable ) {
        UBOS::Utils::myexec( 'sudo systemctl enable -q ' . join( ' ', @toEnable ));
    }
    unless( $initOnly ) {
        if( @runningServices ) {
            UBOS::Utils::myexec( 'sudo systemctl stop ' . join( ' ', @runningServices ));
        }
        my $allNics = UBOS::Host::nics();
        foreach my $nic ( keys %$allNics ) {
            UBOS::Utils::myexec( "ip addr flush " . $nic );

            if( exists( $config->{$nic}->{state} ) && $config->{$nic}->{state} eq 'off' ) {
                UBOS::Utils::myexec( "ip link set $nic down" );
            } else {
                UBOS::Utils::myexec( "ip link set $nic up" );
            }
        }
        UBOS::Utils::myexec( 'sudo systemctl start ' . join( ' ', grep { m!\.service$! } keys %servicesNeeded ));
        # .socket don't want to be started
    }
}

##
# Find a network that's not allocated yet
# $conf: the current configuration object
# return: ( $ip, $prefixSize ): IP address to be assigned to the NIC, and prefix size for the subnet
sub findUnusedNetwork {
    my $conf = shift;

    my $defaults = networkingDefaults();

    # Determine which networks have been allocated
    my @allocated = (); # contains array[2], where [0]: binary IP address of interface, [1]: binary netmask
    foreach my $nic ( sort keys %$conf ) {
        if( exists( $conf->{$nic}->{address} )) {
            my $prefixsize = exists( $conf->{$nic}->{prefixsize} ) ? $conf->{$nic}->{prefixsize} : 32; # seems a safe default

            my $binIp = _binIpAddress( $conf->{$nic}->{address} );
            my $mask  = _binNetMask( $prefixsize );

            push @allocated, [ $binIp, $mask ];
        }
    }

    # Return the first network that doesn't overlap with an allocated one
    foreach my $candidateIp ( sort keys %{$defaults->{networks}} ) {
        my $prefixsize     = $defaults->{networks}->{$candidateIp}->{prefixsize};
        my $binCandidateIp = _binIpAddress( $candidateIp );
        my $candidateMask  = _binNetMask( $prefixsize );

        my $overlap = 0;
        foreach my $allocated ( @allocated ) {
            # there's overlap if the networks are the same masked by the shorter
            # netmask (as in counting the number of 1's)

            my $effectiveMask = $allocated->[1] & $candidateMask;

            if(( $allocated->[0] & $effectiveMask ) == ( $binCandidateIp & $effectiveMask )) {
                $overlap = 1;
                last;
            }
        }
        unless( $overlap ) {
            return( $candidateIp, $prefixsize );
        }
    }
    return undef;
}

##
# Calculate the binary representation of an IP address
# $ip: IP address as string, e.g. 1.2.3.4
# return: integer number
sub _binIpAddress {
    my $ip = shift;

    my $bin;
    if( $ip =~ m!^(\d+)\.(\d+)\.(\d+)\.(\d+)$! ) {
        $bin = $1;
        $bin = $bin*256 + $2;
        $bin = $bin*256 + $3;
        $bin = $bin*256 + $4;
    } else {
        error( 'Not an IP address:', $ip );
    }
    return $bin;
}

##
# Calculate integer netmask from prefixlength
# $prefixlength, e.g. 1
# return: binary netmask, e.g. 1<<31
sub _binNetMask {
    my $prefixlength = shift;

    my $mask = 0;
    for( my $i=0 ; $i<32 ; ++$i ) {
        if( $i<$prefixlength ) {
            $mask |= 1<<( 31-$i );
        }
    }
    return $mask;
}

##
# Convert a binary representation of an IP address to string
# $bin: integer number, e.g. 257
# return: IP address as string, e.g. 0.0.1.1
sub _stringIpAddress {
    my $bin = shift;
    
    return join( '.', ( map { 0 + ($bin >> ($_*8)) & 255 } (3,2,1,0) ));
}

##
# Calculate a suitable dhcp-range from an interface configuration
# $nicConfig: configuration for this interface
# return: string suitable for dnsmasq
sub _calculateDhcpRange {
    my $nicConfig = shift;

    my $address    = $nicConfig->{address};
    my $prefixsize = $nicConfig->{prefixsize};
    my $lease;

    if( exists( $nicConfig->{'dhcp-lease'} )) {
        $lease = $nicConfig->{'dhcp-lease'};
    } else {
        my $defaults = networkingDefaults();
        $lease = exists( $defaults->{'dhcp-lease'} ) ? $defaults->{'dhcp-lease'} : '12h';
    }
        
    my $binAddress   = _binIpAddress( $address );
    my $binFrom      = $binAddress+1;
    my $from         = _stringIpAddress( $binFrom );
    my $mask         = _binNetMask( $prefixsize );
    my $invertedMask = ( ~$mask ) & ( ( 1<<32 ) -1 ); # 32bits not 64
    my $binTo        = ( $binAddress | $invertedMask ) - 1; # don't use .255 or such
    my $to           = _stringIpAddress( $binTo );

    return "$from,$to,$lease";
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

    my $all = '';
    foreach my $file ( glob $openPortsFilePattern ) {
        my $found = UBOS::Utils::slurpFile( $file );
        $all .= "$found\n";
    }
    my %ret = ();
    map { $ret{$_} = 1; }
        grep { $_ }
        map { my $s = $_; $s =~ s!#.*!! ; $s =~ s!^\s+!! ; $s =~ s!\s+$!! ; $s }
        split /\n/, $all;

    return sort keys %ret;
}

1;
