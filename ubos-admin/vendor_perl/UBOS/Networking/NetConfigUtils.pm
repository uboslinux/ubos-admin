#!/usr/bin/perl
#
# Collection of utility methods for UBOS network configuration management.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Networking::NetConfigUtils;

use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

my $avahiConfigFile             = '/etc/avahi/avahi-daemon.conf';
my $iptablesConfigFile          = '/etc/iptables/iptables.rules';
my $ip6tablesConfigFile         = '/etc/iptables/ip6tables.rules';
my $dnsmasqConfigFile           = '/etc/dnsmasq.ubos.d/50-ubos-admin-generated.conf';
my $openPortsDir                = '/etc/ubos/open-ports.d';
my $openPortsFilePattern        = $openPortsDir . '/*';
my $dotNetworkFilePattern       = '/etc/systemd/network/%2d-ubos-%s.network';
my $dotNetworkDeleteGlob        = '/etc/systemd/network/??-ubos-*.network';
my $networkingDefaultsConfFile  = '/etc/ubos/networking-defaults.json';
my $_networkingDefaultsConf     = undef; # cached content of $networkingDefaultsConfFile
my $netconfigConfFilePattern    = '/etc/ubos/netconfig-%s.json';
my $_netconfigConfs             = {}; # cached content of $netconfigConfFilePattern, keyed by netconfig name
my $resolvedConfFile            = '/etc/systemd/resolved.conf';
my $currentNetConfigFile        = '/etc/ubos/active-netconfig';

our $DEFAULT_SSHRATELIMITSECONDS = 120;
our $DEFAULT_SSHRATELIMITCOUNT   = 7;

# Regardless of Netconfig, always run these
my %alwaysServices = (
        'systemd-networkd.service' => 1,
        'systemd-networkd.socket'  => 1,
        'systemd-resolved.service' => 1,
        'iptables.service'         => 1,
        'ip6tables.service'        => 1
);

# All services possibly started/stopped. Depending on Netconfig, not all of
# them may actually be installed.
my %allServices = (
        %alwaysServices,
        'avahi-daemon.service'     => 1,
        'avahi-daemon.socket'      => 1,
        'cloud-config.service'     => 1,
        'cloud-final.service'      => 1,
        'cloud-init.service'       => 1,
        'cloud-init-local.service' => 1,
        'dnsmasq.service'          => 1
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
# $force: do not read existing configuration, initialize netconfig from scratch
sub activateNetConfig {
    my $newConfigName = shift;
    my $initOnly      = shift;
    my $force         = shift;

    my $netConfigs = findNetConfigs();

    if( exists( $netConfigs->{$newConfigName} )) {
        my $newConfig  = $netConfigs->{$newConfigName};

        trace( 'Activating netconfig', $newConfigName );

        return UBOS::Utils::invokeMethod( $newConfig . '::activate', $initOnly, $force );

    } else {
        fatal( 'Unknown netconfig', $newConfigName );
    }
}

##
# If the open-ports spec has changed, make necessary changes.
# If not, don't do anything.
# This works by comparing the timestamp of the open-ports directory with
# that of the active netconfig file.
sub updateOpenPorts {
    
    my $openPortsCtime        = ~0; # max
    my $currentNetConfigCtime =  0;

    if( -d $openPortsDir ) {
        $openPortsCtime = ( stat( $openPortsDir ))[10];
    }
    if( -e $currentNetConfigFile ) {
        $currentNetConfigCtime = ( stat( $currentNetConfigFile ))[10];
    }
    if( $openPortsCtime <= $currentNetConfigCtime ) {
        return 0;
    }

    unless( -e $currentNetConfigFile ) {
        warning( 'Cannot update firewall; do not know current netconfig. Run "ubos-admin setnetconfig" once' );
        return 0;
    }

    info( 'Updating firewall' );

    my $netConfig = UBOS::Utils::slurpFile( $currentNetConfigFile );
    $netConfig =~ s!^\s+!!;
    $netConfig =~ s!\s+$!!;

    activateNetConfig( $netConfig );

    # update the time stamp file
    my $now = time();
    utime $now, $now, $currentNetConfigFile;

    return 1;
}



##
# Obtain the name of the current NetConfig if known.
# return: the name
sub activeNetConfigName {

    my $ret = undef;
    if( -e $currentNetConfigFile ) {
        $ret = UBOS::Utils::slurpFile( $currentNetConfigFile );
        $ret =~ s!\s+!!g;
    }
    return $ret;
}

##
# Read the networking defaults, if any. Set defaults if needed
sub networkingDefaults() {
    unless( $_networkingDefaultsConf ) {
        my $doWrite     = 0; # info has been updated
        my $skipWriting = 0; # but it would not be safe to write
        if( -e $networkingDefaultsConfFile ) {
            $_networkingDefaultsConf = UBOS::Utils::readJsonFromFile(
                    $networkingDefaultsConfFile,
                    sub { ( 'Networking defaults file is malformed, falling back to built-in defaults:', $networkingDefaultsConfFile ) } );
            unless( $_networkingDefaultsConf ) {
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
# Set a particular networking configuration for the currently present
# network interfaces.
# The various NetConfig objects invoking this pass a hash that tells this
# method what services to run, which interfaces to config how etc.
# $name: name of the netconfig for reporting purposes
# $config: the config JSON object
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
sub configure {
    my $name     = shift;
    my $config   = shift;
    my $initOnly = shift;

    if( $initOnly ) {
        return configureAll( $name, $config, $initOnly );

    } else {
        my $nics = UBOS::Host::nics();

        my $filteredConfig = {};
        map { $filteredConfig->{$_} = $config->{$_}; } grep { exists( $nics->{$_} ) } keys %$config;

        return configureAll( $name, $filteredConfig, $initOnly );
    }
}

##
# Set a particular networking configuration for all specified network interfaces,
# regardless of whether they currently exist.
# The various NetConfig objects invoking this pass a hash that tells this
# method what services to run, which interfaces to config how etc.
# $name: name of the netconfig for reporting purposes
# $config: the config JSON object
# $initOnly: if true, enable services but do not start them (e.g. during ubos-install)
sub configureAll {
    my $name     = shift;
    my $config   = shift;
    my $initOnly = shift;

    my %servicesNeeded = ( %alwaysServices ); # Run these services after generating config files
    my $isForwarding   = 0;
    my $isMasquerading = 0;

    # error checking:
    # no wildcards allowed if not initOnly
    # and in any case, only trailing *
    foreach my $nic ( keys %$config ) {
        if( $initOnly ) {
            if( $nic =~ m!\*.+! ) {
                fatal( 'Network interface wildcard * only allowed as last character:', $nic );
            }
        } else {
            if( $nic =~ m!\*! ) {
                fatal( 'Network interface wildcards are not allowed except in --init-only mode:', $nic );
            }
        }
        if( exists( $config->{$nic}->{forwarding} )) {
            fatal( "The setting is called 'forward', not 'forwarding'. Please correct your netconfig '$name' in file " . sprintf( $netconfigConfFilePattern, $name ) . "." );
        }
    }

    # systemd.network files

    my @existingDotNetworkFiles = glob( $dotNetworkDeleteGlob );
    if( @existingDotNetworkFiles ) {
        UBOS::Utils::deleteFile( @existingDotNetworkFiles );
    }

    foreach my $nic ( keys %$config ) {
        # wildcards allowed here
        my $nicPriority       = 50; # by default
        my $dotNetworkContent = <<END;
#
# UBOS networking configuration for $nic
# Do not edit, your changes will be mercilessly overwritten as soon
# as somebody invokes 'ubos-admin setnetconfig'.
#
[Match]
Name=$nic

[Network]
END
        if( exists( $config->{$nic}->{address} )) {
            $dotNetworkContent .= 'Address=' . $config->{$nic}->{address} . "\n";
            if( exists( $config->{$nic}->{dhcpserver} ) && $config->{$nic}->{dhcpserver} ) {
                $dotNetworkContent .= 'DNS=' . $config->{$nic}->{address} . "\n";
            }
        }
        if( exists( $config->{$nic}->{dhcp} ) && $config->{$nic}->{dhcp} ) {
            $dotNetworkContent .= "DHCP=yes\n";
        }
        if( exists( $config->{$nic}->{forward} ) && $config->{$nic}->{forward} ) {
            $dotNetworkContent .= "IPForward=yes\n";
        }
        if( exists( $config->{$nic}->{bindcarrier} ) && $config->{$nic}->{bindcarrier} ) {
            $dotNetworkContent .= "BindCarrier=" . $config->{$nic}->{bindcarrier} . "\n";
        }
        if( exists( $config->{$nic}->{priority} ) && $config->{$nic}->{priority} ) {
            $nicPriority = $config->{$nic}->{priority};
        }

        my $noWildNic = $nic;
        $noWildNic =~ s!\*!!g;

        UBOS::Utils::saveFile( sprintf( $dotNetworkFilePattern, $nicPriority, $noWildNic ), $dotNetworkContent );
    }

    # Avahi
    my $avahiAllowInterfacesString = '';
    my $avahiHaveWildcardInterface = 0;
    foreach my $nic ( sort keys %$config ) {
        if( exists( $config->{$nic}->{mdns} ) && $config->{$nic}->{mdns} ) {
            $servicesNeeded{'avahi-daemon.service'} = 1;
            $servicesNeeded{'avahi-daemon.socket'}  = 1;
            if( $avahiAllowInterfacesString ) {
                $avahiAllowInterfacesString .= ' ';
            }
            $avahiAllowInterfacesString .= $nic;

            if( $nic =~ m!\*!  ) {
                $avahiHaveWildcardInterface = 1;
            }
        }
    }
    if( $initOnly && $avahiHaveWildcardInterface ) {
        $avahiAllowInterfacesString = '';
        # This is a compromise. This is during installation time, so we don't know what the
        # interfaces will be. And Avahi doesn't have a wildcard syntax for allow-interfaces.
        # So we do Avahi on all interfaces if it is set for at least one wildcard.
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
    UBOS::Utils::saveFile( '/etc/nsswitch.conf', join( '', map { "$_\n" } @nsswitchContent ));

    if( exists( $servicesNeeded{'avahi-daemon.service'} )) {
        # do not provide empty value of allow-interfaces; apparently means "none"
        if( $avahiAllowInterfacesString ) {
            $avahiAllowInterfacesString = "allow-interfaces=$avahiAllowInterfacesString";
        } else {
            $avahiAllowInterfacesString = "# allow-interfaces=";
        }
        UBOS::Utils::saveFile( $avahiConfigFile, <<END, 0644 );
#
# The avahi configuration for UBOS.
# Do not edit, your changes will be mercilessly overwritten as soon
# as somebody invokes 'ubos-admin setnetconfig'.
#

[server]
#domain-name=local
browse-domains=
use-ipv4=yes
use-ipv6=no
ratelimit-interval-usec=1000000
ratelimit-burst=1000
$avahiAllowInterfacesString

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
# rlimit-nproc=3
# UBOS: this default limit makes it impossible to run avahi on both host and container on the same machine
# inhibiting testing, so we increase this slightly
rlimit-nproc=6
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
dhcp-range=$nic,$range
END
            # dnsmasq allows trailing * for wildcard
            $servicesNeeded{'dnsmasq.service'} = 1;
        }
    }
    if( exists( $servicesNeeded{'dnsmasq.service'} )) {
        UBOS::Utils::saveFile( $dnsmasqConfigFile, $dnsmasqConfigContent );

    } elsif( -e $dnsmasqConfigFile ) {
        UBOS::Utils::deleteFile( $dnsmasqConfigFile );
    }

    # firewall / masquerade / netfilter
    # inspired by: https://wiki.archlinux.org/index.php/Simple_stateful_firewall
    # but we create a TCP and a UDP chain for each nic
    foreach my $nic ( sort keys %$config ) {
        if( exists( $config->{$nic}->{masquerade} ) && $config->{$nic}->{masquerade} ) {
            $isMasquerading = 1;
        }
        if( exists( $config->{$nic}->{forward} ) && $config->{$nic}->{forward} ) {
            $isForwarding = 1;
        }
    }

    my $iptablesContent = <<END;
#
# UBOS iptables configuration
# Do not edit, your changes will be mercilessly overwritten as soon
# as somebody invokes 'ubos-admin setnetconfig'.
#

*filter
:INPUT DROP [0:0]
END
    if( $isForwarding ) {
        $iptablesContent .= <<END;
:FORWARD ACCEPT [0:0]
END
    } else {
        $iptablesContent .= <<END;
:FORWARD DROP [0:0]
END
    }

    # our chains can't have a default policy specified here, so -
    $iptablesContent .= <<END;
:OUTPUT - [0:0]
:OPEN-PORTS - [0:0]
END

    # UBOS Live
    $iptablesContent .= <<END;
:NIC-tun90-TCP - [0:0]
END

    # don't accept anything from nics that are off or switch
    foreach my $nic ( sort keys %$config ) {
        my $noWildNic = $nic;
        $noWildNic =~ s!\*!!g;
        if(    exists( $config->{$nic}->{state} )
            && ( $config->{$nic}->{state} eq 'off' || $config->{$nic}->{state} eq 'switch' ))
        {
            $iptablesContent .= <<END;
:NIC-$noWildNic - [0:0]
END
        } else {
            $iptablesContent .= <<END;
:NIC-$noWildNic-TCP - [0:0]
:NIC-$noWildNic-UDP - [0:0]
END
        }
    }

    # applies to all nics
    $iptablesContent .= <<END;
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
END
    # always accept loopback
    $iptablesContent .= <<END;
-A INPUT -i lo -j ACCEPT
END
    # always accept traffic from containers (+ is wildcard)
    $iptablesContent .= <<END;
-A INPUT -i ve-+ -j ACCEPT
END

    # dispatch by nic
    foreach my $nic ( sort keys %$config ) {
        if(    exists( $config->{$nic}->{state} )
            && ( $config->{$nic}->{state} eq 'off' || $config->{$nic}->{state} eq 'switch' ))
        {
            my $noWildNic = $nic;
            my $wildNic   = $nic;
            $noWildNic =~ s!\*!!g;
            $wildNic   =~ s!\*!+!g; # iptables uses + instead of *

            $iptablesContent .= <<END;
-A INPUT -i $wildNic -j NIC-$noWildNic
END
        }
    }
    $iptablesContent .= <<END;
-A INPUT -p icmp -m icmp --icmp-type 8 -m conntrack --ctstate NEW -j ACCEPT
END

    foreach my $nic ( sort keys %$config ) {
        if(    exists( $config->{$nic}->{state} )
            && ( $config->{$nic}->{state} eq 'off' || $config->{$nic}->{state} eq 'switch' ))
        {
            # handled this already
        } else {
            my $noWildNic = $nic;
            my $wildNic   = $nic;
            $noWildNic =~ s!\*!!g;
            $wildNic   =~ s!\*!+!g; # iptables uses + instead of *

            $iptablesContent .= <<END;
-A INPUT -i $wildNic -p udp -m conntrack --ctstate NEW -j NIC-$noWildNic-UDP
-A INPUT -i $wildNic -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j NIC-$noWildNic-TCP
END
        }
    }
    $iptablesContent .= <<END;
-A INPUT -i tun90 -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j NIC-tun90-TCP
-A INPUT -p udp -j REJECT --reject-with icmp-port-unreachable
-A INPUT -p tcp -j REJECT --reject-with tcp-reset
-A INPUT -j REJECT --reject-with icmp-proto-unreachable
END

    foreach my $nic ( sort keys %$config ) {
        if(    exists( $config->{$nic}->{state} )
            && ( $config->{$nic}->{state} eq 'off' || $config->{$nic}->{state} eq 'switch' )) {
            # handled this already
        } else {
            my $noWildNic = $nic;
            $noWildNic =~ s!\*!!g;

            if( exists( $config->{$nic}->{dhcp} ) && $config->{$nic}->{dhcp} ) {
                $iptablesContent .= "-A NIC-$noWildNic-UDP -p udp --dport bootpc -j ACCEPT\n";
                $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp --dport bootpc -j ACCEPT\n";
            }
            if( exists( $config->{$nic}->{dhcpserver} ) && $config->{$nic}->{dhcpserver} ) {
                $iptablesContent .= "-A NIC-$noWildNic-UDP -p udp --dport bootps -j ACCEPT\n";
                $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp --dport bootps -j ACCEPT\n";
            }
            if( exists( $config->{$nic}->{dns} ) && $config->{$nic}->{dns} ) {
                $iptablesContent .= "-A NIC-$noWildNic-UDP -p udp --dport domain -j ACCEPT\n";
                $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp --dport domain -j ACCEPT\n";
            }
            if( exists( $config->{$nic}->{mdns} ) && $config->{$nic}->{mdns} ) {
                $iptablesContent .= "-A NIC-$noWildNic-UDP -p udp --dport mdns -j ACCEPT\n";
                $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp --dport mdns -j ACCEPT\n";
            }
            if( exists( $config->{$nic}->{ssh} ) && $config->{$nic}->{ssh} ) {
                if( exists( $config->{$nic}->{sshratelimit} ) && $config->{$nic}->{sshratelimit} ) {
                    $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp --dport ssh -m state --state NEW -m recent --set\n";
                    $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp --dport ssh -m state --state NEW -m recent --update"
                                        . " --seconds "
                                            . ( exists( $config->{$nic}->{sshratelimitseconds} )
                                            ? $config->{$nic}->{sshratelimitseconds}
                                            : $DEFAULT_SSHRATELIMITSECONDS )
                                        . " --hitcount "
                                            . ( exists( $config->{$nic}->{sshratelimitcount}   )
                                            ? $config->{$nic}->{sshratelimitcount}
                                            : $DEFAULT_SSHRATELIMITCOUNT )
                                        . " -j DROP\n";
                }
                $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp --dport ssh -j ACCEPT\n";
            }
            if( exists( $config->{$nic}->{ports} ) && $config->{$nic}->{ports} ) {
                $iptablesContent .= "-A NIC-$noWildNic-UDP -p udp -j OPEN-PORTS\n";
                $iptablesContent .= "-A NIC-$noWildNic-TCP -p tcp -j OPEN-PORTS\n";
            }
        }
    }

    $iptablesContent .= "-A NIC-tun90-TCP -p tcp --dport ssh -j ACCEPT\n";

    # determine the appropriate content to insert into iptables configuration
    # for those interfaces that have application ports open
    my @openPorts = _determineOpenPorts();
    foreach my $portSpec ( @openPorts ) {
        if( $portSpec =~ m!(.+)/tcp! ) {
            $iptablesContent .= "-A OPEN-PORTS -p tcp --dport $1 -j ACCEPT\n";
        } elsif( $portSpec =~ m!(.+)/udp! ) {
            $iptablesContent .= "-A OPEN-PORTS -p udp --dport $1 -j ACCEPT\n";
        } else {
            error( 'Unknown open ports spec:', $portSpec );
        }
    }

    if( $isForwarding ) {
        $iptablesContent .= <<END;
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
END
    }
    my @lans = (); # only used if $isMasquerading
    if( $isMasquerading ) {
        foreach my $nic ( sort keys %$config ) {
            if( exists( $config->{$nic}->{masquerade} ) && $config->{$nic}->{masquerade} ) {
                # nothing
            } elsif( exists( $config->{$nic}->{address} )) {
                push @lans, _networkAddress( $config->{$nic}->{address}, $config->{$nic}->{prefixsize} );

                my $wildNic = $nic;
                $wildNic=~ s!\*!+!g; # iptables uses + instead of *

                $iptablesContent .= <<END;
-A FORWARD -i $wildNic -j ACCEPT
END
            }
        }
        $iptablesContent .= <<END;
-A FORWARD -i ve-+ -j ACCEPT
-A FORWARD -j REJECT --reject-with icmp-host-unreachable
END
            # always forward from containers
    }
    foreach my $nic ( sort keys %$config ) {
        my $noWildNic = $nic;
        $noWildNic =~ s!\*!!g;

        if(    exists( $config->{$nic}->{state} )
            && ( $config->{$nic}->{state} eq 'off' || $config->{$nic}->{state} eq 'switch' ))
        {
            $iptablesContent .= <<END;
-A NIC-$noWildNic -j DROP
END
        } else {
            $iptablesContent .= <<END;
-A NIC-$noWildNic-UDP -j REJECT --reject-with icmp-host-unreachable
-A NIC-$noWildNic-TCP -p tcp -j REJECT --reject-with tcp-reset
END
            # this -p tcp is redundant, but iptables doesn't know that, and refuses
            # to accept the line without it
        }
    }

    $iptablesContent .= <<END;
COMMIT
END

    if( $isMasquerading ) {
        $iptablesContent .= <<END;
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
END
        foreach my $nic ( sort keys %$config ) {
            if( exists( $config->{$nic}->{masquerade} ) && $config->{$nic}->{masquerade} ) {
                my $wildNic = $nic;
                $wildNic=~ s!\*!+!g; # iptables uses + instead of *

                foreach my $lan ( sort @lans ) {
                    $iptablesContent .= <<END;
-A POSTROUTING -s $lan -o $wildNic -j MASQUERADE
END
                }
            }
        }
        $iptablesContent .= <<END;
COMMIT
END
    }

    UBOS::Utils::saveFile( $iptablesConfigFile, $iptablesContent );

    my $ip6tablesContent = <<END;
#
# UBOS ip6tables configuration
# Do not edit, your changes will be mercilessly overwritten as soon
# as somebody invokes 'ubos-admin setnetconfig'.
#

*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT - [0:0]
:NIC-tun90-TCP - [0:0]
-A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A INPUT -i tun90 -p tcp --tcp-flags FIN,SYN,RST,ACK SYN -m conntrack --ctstate NEW -j NIC-tun90-TCP
-A INPUT -p udp -j REJECT
-A INPUT -p tcp -j REJECT --reject-with tcp-reset
-A INPUT -j REJECT
-A NIC-tun90-TCP -p tcp --dport ssh -j ACCEPT
COMMIT
END

    UBOS::Utils::saveFile( $ip6tablesConfigFile, $ip6tablesContent );

    # cloud-init
    foreach my $nic ( keys %$config ) {
        if( exists( $config->{$nic}->{'cloud-init'} ) && $config->{$nic}->{'cloud-init'} ) {
            $servicesNeeded{'cloud-config.service'}     = 1;
            $servicesNeeded{'cloud-final.service'}      = 1;
            $servicesNeeded{'cloud-init.service'}       = 1;
            $servicesNeeded{'cloud-init-local.service'} = 1;

            last;
        }
    }

    # updates to resolved.conf
    if( -e $resolvedConfFile ) {
        my $resolvedConfContent = UBOS::Utils::slurpFile( $resolvedConfFile );
        if( $resolvedConfContent !~ m!DNSStubListener=no! ) {
            # it can match anywhere, it does not matter where -- it means somebody manually edited the file,
            # in which case we leave it alone
            if( $resolvedConfContent =~ m!^\[Resolve\]! ) {
                $resolvedConfContent =~ s!(\[Resolve\])!$1\nDNSStubListener=no!;
            } else {
                $resolvedConfContent .= "\n[Resolve]\nDNSStubListener=no";
            }
            UBOS::Utils::saveFile( $resolvedConfFile, $resolvedConfContent, 0644 );
        }
    }

    # configure callbacks
    my @appNics = grep { exists( $config->{$_}->{appnic} ) && $config->{$_}->{appnic} }
                  sort keys %$config;

    if( @appNics ) {
        my $callbackContent = 'UBOS::HostnameCallbacks::UpdateEtcHosts 1 ' . join( ' ', @appNics ) . "\n";
        UBOS::Utils::saveFile( '/etc/ubos/hostname-callbacks/etchosts', $callbackContent );
    } else {
        if( -e '/etc/ubos/hostname-callbacks/etchosts' ) {
            UBOS::Utils::deleteFile( '/etc/ubos/hostname-callbacks/etchosts' );
        }
    }

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
        UBOS::Utils::myexec( 'sudo systemctl disable -q ' . join( ' ', @toDisable ) . ( UBOS::Logging::isTraceActive() ? '' : ' 2> /dev/null' ));
    }
    if( @toEnable ) {
        UBOS::Utils::myexec( 'sudo systemctl enable -q ' . join( ' ', @toEnable ) . ( UBOS::Logging::isTraceActive() ? '' : ' 2> /dev/null' ));
    }
    unless( $initOnly ) {
        if( @runningServices ) {
            UBOS::Utils::myexec( 'sudo systemctl stop ' . join( ' ', @runningServices ));
        }
        UBOS::Utils::myexec( 'sudo systemctl restart systemd-sysctl.service' );

        foreach my $nic ( keys %$config ) {
            UBOS::Utils::myexec( "ip addr flush $nic" );

            if( exists( $config->{$nic}->{state} ) && $config->{$nic}->{state} eq 'off' ) {
                # keep link up for state eq 'switch'
                UBOS::Utils::myexec( "ip link set $nic down" );

            } else {
                UBOS::Utils::myexec( "ip link set $nic up" );
            }
        }
        UBOS::Utils::myexec( 'sudo systemctl start ' . join( ' ', grep { m!\.service$! } keys %servicesNeeded ));
        # .socket don't want to be started
    }

    UBOS::Utils::saveFile( $currentNetConfigFile, "$name\n" );

    return 1;
}

##
# Find a network that's not allocated yet
# $conf: the current configuration object
# return: ( $ip, $prefixsize ): IP address to be assigned to the NIC, and prefix size for the subnet
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
        # IPv4
        $bin = $1;
        $bin = $bin*256 + $2;
        $bin = $bin*256 + $3;
        $bin = $bin*256 + $4;
    } elsif( $ip =~ m!^[0-9a-f:]+$! ) {
        # IPv6
    } else {
        error( 'Not an IP address:', $ip );
    }
    return $bin;
}

##
# Calculate integer netmask from prefixsize
# $prefixsize, e.g. 1
# return: binary netmask, e.g. 1<<31
sub _binNetMask {
    my $prefixsize = shift;

    my $mask = 0;
    for( my $i=0 ; $i<32 ; ++$i ) {
        if( $i<$prefixsize ) {
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
# Calculate a network address from IP address and prefixsize
# $ip: IP address, e.g. 1.2.3.4
# $prefixsize, e.g. 8
# return: string, e.g. 1.0.0.0/8
sub _networkAddress {
    my $ip         = shift;
    my $prefixsize = shift;

    my $binIp   = _binIpAddress( $ip );
    my $binMask = _binNetMask( $prefixsize );
    $binIp &= $binMask;

    my $ret = _stringIpAddress( $binIp ) . '/' . $prefixsize;
    return $ret;
}

##
# Determine if a given IP address is on a LAN, or publicly accessible
# $ip: the IP address
# return: 1 if it is on a LAN
sub isOnLan {
    my $ip = shift;

    my $binIp = _binIpAddress( $ip );
    unless( $binIp ) {
        return 0;
    }

    my $mask8  = _binNetMask( 8 );
    if( ( $binIp & $mask8 ) == _binIpAddress( '10.0.0.0' )) {
        # 10.0.0.0        -   10.255.255.255  (10/8 prefix)
        return 1;
    }

    my $mask12 = _binNetMask( 12 );
    if( ( $binIp & $mask12 ) == _binIpAddress( '172.16.0.0' )) {
        # 172.16.0.0      -   172.31.255.255  (172.16/12 prefix)
        return 1;
    }

    my $mask16 = _binNetMask( 16 );
    if( ( $binIp & $mask16 ) == _binIpAddress( '192.168.0.0' )) {
        # 192.168.0.0     -   192.168.255.255 (192.168/16 prefix)
        return 1;
    }
    return 0;
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
