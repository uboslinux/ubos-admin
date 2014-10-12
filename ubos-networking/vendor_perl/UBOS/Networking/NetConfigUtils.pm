#!/usr/bin/perl
#
# Collection of utility methods for UBOS network configuration management.
#
# This file is part of ubos-networking.
# (C) 2012-2014 Indie Computing Corp.
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

my $ipLinks      = undef;
my $dhcpConfHead = '/usr/share/ubos-networking/tmpl/dhcpcd.head';
my $dhcpConf     = '/etc/dhcpcd.conf';
my $ipAddrPrefix = '192.168.139.';
my $confFile     = '/etc/ubos/networking.conf';

##
# Initialize if needed. Invoked at boot and when module is installed
sub initializeIfNeeded {

    my $conf;
    if( -e $confFile ) {
        $conf = UBOS::Utils::readJsonFromFile( $confFile );
    } else {
        $conf = {
            'netconfig' => 'client'
        };
        UBOS::Utils::writeJsonToFile( $confFile, $conf );
    }
    
    my $netConfigName = $conf->{netconfig}; 
    activateNetConfig( $netConfigName );
}

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
    my $newConfig  = $netConfigs->{$newConfigName};

    if( $newConfig ) {
        UBOS::Utils::invokeMethod( $newConfig . '::activate' );

        # update config file
        
        my $conf;
        if( -e $confFile ) {
            $conf = UBOS::Utils::readJsonFromFile( $confFile );
        } else {
            $conf = {};
        }
        $conf->{netconfig} = $newConfigName;
        UBOS::Utils::writeJsonToFile( $confFile, $conf );
        
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
# if both parameters are undef, it means deactivate all interfaces
#
# Examples:
# setNetConfig( undef, undef ) -- deactivate all interfaces
# setNetConfig( [ eth0 ], undef ) -- only activate eth0 as DHCP client
# setNetConfig( 1, undef ) -- all interfaces are DHCP clients
# setNetConfig( undef, [eth0, eth1] ) -- assign static IP addresses to eth0 and eth1

sub setNetConfig {
    my $dhcpClientNicInfo     = shift;
    my $privateNetworkNicInfo = shift;

    my $allNics = getAllNics();

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

    # determine new configuration
    my $dhcpcdFrag1;
    my $dhcpcdFrag2;
    if( ref( $dhcpClientNicInfo ) eq 'ARRAY' ) {
        $dhcpcdFrag1 = _configureDhcpcd( $dhcpClientNicInfo, undef, $allNics ); # DHCP for named nics
        
    } elsif( defined( $dhcpClientNicInfo ) && $dhcpClientNicInfo == 1 ) {
        if( ref( $privateNetworkNicInfo ) eq 'ARRAY' ) {
            $dhcpcdFrag1 = _configureDhcpcd( undef, $privateNetworkNicInfo, $allNics ); # DHCP for all except named nics
        } else {
            $dhcpcdFrag1 = _configureDhcpcd( undef, [], $allNics ); # DHCP for all
        }
    } else {
        $dhcpcdFrag1 = _configureDhcpcd( undef, undef, $allNics ); # DHCP for none
    }

    if( ref( $privateNetworkNicInfo ) eq 'ARRAY' ) {
        $dhcpcdFrag2 = _configureStatic( $privateNetworkNicInfo, undef, $allNics ); # static for named nics
        
    } elsif( defined( $privateNetworkNicInfo ) && $privateNetworkNicInfo == 1 ) {
        if( ref( $dhcpClientNicInfo ) eq 'ARRAY' ) {
            $dhcpcdFrag2 = _configureStatic( undef, $dhcpClientNicInfo, $allNics ); # static for all except named nics
        } else {
            $dhcpcdFrag2 = _configureStatic( undef, [], $allNics ); # static for all
        }
    } else {
        $dhcpcdFrag2 = _configureStatic( undef, undef, $allNics ); # static for none
    }

    # write config file
    my $dhcpcdContent = UBOS::Utils::slurpFile( $dhcpConfHead );
    if( $dhcpcdFrag1 ) {
        $dhcpcdContent .= $dhcpcdFrag1;
    }
    if( $dhcpcdFrag2 ) {
        $dhcpcdContent .= $dhcpcdFrag2;
    }
    UBOS::Utils::saveFile( $dhcpConf, $dhcpcdContent );
        
    # start/stop daemons
    if( defined( $dhcpClientNicInfo ) || defined( $privateNetworkNicInfo )) {
        _startService( 'dhcpcd', 'dhcpcd' );
    } else {
        _stopService( 'dhcpcd' );
    }
}

##
# Internal helper to execute "ip link" and parse the output
sub _ipLinks {
	unless( defined( $ipLinks )) {
		my $out;
		UBOS::Utils::myexec( 'ip link show', undef, \$out );
		
# example output:
# 1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default 
#     link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
# 2: enp2s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000
#     link/ether 00:30:18:c0:53:6a brd ff:ff:ff:ff:ff:ff
# 3: enp3s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
#     link/ether 00:30:18:c0:53:6b brd ff:ff:ff:ff:ff:ff
# 8: enp0s29f7u3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
#     link/ether 00:50:b6:5c:8f:a9 brd ff:ff:ff:ff:ff:ff
# 9: wlp0s29f7u4: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT group default qlen 1000
#     link/ether 5c:f3:70:03:6b:ed brd ff:ff:ff:ff:ff:ff

        my @sections = split /\n\d+:\s*/, $out;
        my $atts     = {
			'mtu'   => '\d+',
			'qdisc' => undef,
			'noop'  => undef,
			'state' => '\S+',
			'mode'  => '\S+',
			'group' => '\S+',
			'qlen'  => '\d+'
        };
        foreach my $section ( @sections ) {
			# first line may still have 1: prefix
			if( $section =~ m!^(?:\d+:\s+)?([a-z0-9]+):\s*(?:<([^>]*)>)\s+(.*)\n\s+link/(\S+)\s+([0-9a-f:]+)\s+([a-z]+)\s+([0-9a-f:]+)$! ) {
				my $devName      = $1; # e.g. enp2s0

                if( 'lo' eq $devName ) {
                    next;
                }
                
				my $devFlags     = $2; # e.g. LOOPBACK,UP,LOWER_UP
				my $devFirstLine = $3; # e.g. mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default 
				my $devType      = $4; # e.g. loopback
				my $macAddr      = $5; # e.g. 00:30:18:c0:53:6a
				my $broadcast    = $6; # always seems to be brd
				my $brdAddr      = $7; # e.g. ff:ff:ff:ff:ff:ff

				unless( defined( $ipLinks )) {
					$ipLinks = {};
				}
				my $h = {};
				$h->{flags} = {};
				$h->{atts}  = {};
				map { $h->{flags}->{$_} = 1 } split ',', $devFlags;
				# This loop isn't quite clean: att names may be parts of words, not entire words; does not seem to happen though
                foreach my $att ( keys %$atts ) {
                    my $regex = $atts->{$att};

					if( $regex ) {
                        if( $devFirstLine =~ m!$att ($regex)! ) {
						    $h->{atts}->{$att} = $1;
						}
					} else {
                        if( $devFirstLine =~ m!$att! ) {
						    $h->{atts}->{$att} = 1;
						}
					}
				}
				$h->{type} = $devType;
				$h->{mac}  = $macAddr;
				$h->{brd}  = $brdAddr;
				
				$ipLinks->{$devName} = $h;
			}
		}
	}
	return $ipLinks;
}

##
# Configure dhcpcd. Either par1 or par2 are provided
# $these: activate dhcpcd on these interfaces
# $notThese: activate dhcpcd on all interfaces but notThese
# $allNics: hash of all known interfaces
# return: fragment for dhcpcd conf file
sub _configureDhcpcd {
    my $these    = shift;
    my $notThese = shift;
    my $allNics  = shift;

    my $ret;
    if( $these ) {
        if( @$these ) {
            $ret = 'allowinterfaces ' . join( ' ', @$these ) . "\n";
            notice( 'Activating DHCP on interfaces', @$these );
        } else {
            $ret = "allowinterfaces\n"; # none
            notice( 'Activating DHCP on no interfaces' );
        }

    } elsif( $notThese ) {
        if( @$notThese ) {
            $ret = 'denyinterfaces ' . join( ' ', @$notThese ) . "\n";
            notice( 'Activating DHCP on all interfaces BUT', @$notThese );
        } else {
            notice( 'Activating DHCP on all interfaces' );
        }

    } else {
        $ret = "allowinterfaces\n"; # none
        notice( 'Turning off DHCP' );
    }
    return $ret;
}

##
# Configure static networking. Either par1 or par2 are provided
# $these: set static IP on these interfaces
# $notThese: set static IP on all interfaces but notThese
# $allNics: hash of all known interfaces
# return: fragment for dhcpcd conf file
sub _configureStatic {
    my $these    = shift;
    my $notThese = shift;
    my $allNics  = shift;

    my @list;
    if( $these ) {
        if( @$these ) {
            notice( 'Configuring static IP on interfaces', @$these );
            @list = @$these;
        } else {
            notice( 'Configuring static IP on no interfaces' );
            @list = ();
        }
    } elsif( $notThese ) {
        if( @$notThese ) {
            foreach my $nic1 ( keys @$allNics ) {
                my $found = 0;
                foreach my $nic2 ( @$notThese ) {
                    if( $nic1 eq $nic2 ) {
                        $found = 1;
                        last;
                    }
                }
                unless( $found ) {
                    push @list, $nic1;
                }
            }
            notice( 'Configuring static IP on interfaces', @list );
        } else {
            notice( 'Configuring static IP on all interfaces' );
            @list = keys %$allNics;
        }
    } else {
        notice( 'Configuring no static IP' );
    }
    
    @list = sort compareNics @list;
    
    my $ret;
    my $trailingIp = 1;
    foreach my $nic ( @list ) {
        $ret .= "interface $nic\n";
        $ret .= "static ip_address=$ipAddrPrefix$trailingIp\n";
        ++$trailingIp;
    }
    return $ret;
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
# Start a daemon, but install first if needed
sub _startService {
    my $service = shift;
    my $package = shift;

    if( defined( $package )) {
        UBOS::Host::ensurePackages( $package );
    }

    # Status messages unfortunately go to stderr
    my $out;
    my $err;
    UBOS::Utils::myexec( 'systemctl enable '  . $service, undef, \$out, \$err );
    UBOS::Utils::myexec( 'systemctl restart ' . $service, undef, \$out, \$err );
}

##
# Stop a daemon
sub _stopService {
    my $service = shift;

    my $out;
    my $err;
    UBOS::Utils::myexec( 'systemctl stop ' . $service, undef, \$out, \$err );

    if( $err !~ m!No such file or directory! && $err !~ m!not loaded! ) {
        UBOS::Utils::myexec( 'systemctl disable ' . $service, undef, \$out, \$err );
    }
}

1;

