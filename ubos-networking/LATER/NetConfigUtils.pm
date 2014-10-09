#!/usr/bin/perl
#
# Collection of utility methods for Indie Box network configuration management.
#
# This file is part of indiebox-networking.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-networking is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-networking is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-networking.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Networking::NetConfigUtils;

use Cwd;
use IndieBox::Logging;
use IndieBox::Utils;

my $interfacesFile = '/etc/indie-device/interfaces.json';
my $interfacesJson = undef;
my $ipLinks        = undef;

##
# Find all NetConfigs
# return: hash of net config name to package name
sub findNetConfigs {
    my $ret = IndieBox::Utils::findPerlShortModuleNamesInPackage( 'IndieBox::Networking::NetConfigs' );

    return $ret;
}

##
# Find known network interfaces
sub getKnownNics {
	return _getNicsWith( [ 'permanent', 'pluggable' ] );
}

##
# Find permanent known network interfaces
sub getPermanentKnownNics {
	return _getNicsWith( [ 'permanent' ] );
}

##
# Find pluggable known network interfaces
sub getPluggableKnownNics {
	return _getNicsWith( [ 'pluggable' ] );
}

##
# Find the single primary known network interface, if there is one.
sub getPrimaryKnownNic {
	my $permanent = getPermanentKnownNics();
	my( $retName, $retValue ); # return

    foreach my $name ( keys %$permanent ) {
        my $value = $permanent->{$name};

		if( defined( $value->{primary} ) && $value->{primary} ) {
            $retName  = $name;
			$retValue = $value;
		}
	}
	unless( defined( $retName )) {
		# take the single one if there is one
		if( keys %$permanent == 1 ) {
            ( $retName, $retValue ) = each %$permanent; # just the first one; previously-line keys resets iteration
			
		} elsif( keys %$permanent == 0 ) {
            my $pluggable = getPluggableKnownNics();
			if( keys %$pluggable == 1 ) {
				( $retName, $retValue ) = each %$pluggable; # just the first one; previously-line keys resets iteration
			}            
		}
	}
	return ( $retName, $retValue );
}

##
# Find all network interfaces
sub getAllNics {
	my $all  = _ipLinks();
	my $json = _interfacesJson();
	my $ret  = {};

    foreach my $name ( keys %$all ) {
        my $value = $all->{$name};

		$ret->{$name} = $value;

        foreach my $sectionName ( keys %$json ) {
            my $sectionValue = $json->{$sectionName};

            foreach my $regex ( keys %$sectionValue ) {
                my $regexValue = $sectionValue->{$regex};

				if( $name =~ m!^$regex$! ) {
					if( defined( $regexValue->{name} )) {
                        $ret->{$name}->{name} = $regexValue->{name};
                    }
					if( defined( $regexValue->{primary} )) {
                        $ret->{$name}->{primary} = $regexValue->{primary};
                    }
                }
			}
		}
	}
	return $ret;
}

##
# Internal helper to get NICs with a particular filter
# $sectionNames: the names of the sections to look at
sub _getNicsWith {
	my $sectionNames = shift;

	my $all  = _ipLinks();
	my $json = _interfacesJson();
	my $ret  = {};

	foreach my $sectionName ( @$sectionNames ) {
		if( defined( $json->{$sectionName} )) {
			my $sectionValue = $json->{$sectionName};

            foreach my $name ( keys %$all ) {
                my $value = $all->{$name};

                foreach my $regex ( keys %$sectionValue ) {
                    my $regexValue = $sectionValue->{$regex};

					if( $name =~ m!^$regex$! ) {
						$ret->{$name} = $value;
						if( defined( $regexValue->{name} )) {
							$ret->{$name}->{name} = $regexValue->{name};
						}                
						if( defined( $regexValue->{primary} )) {
							$ret->{$name}->{primary} = $regexValue->{primary};
						}                
					}
				}
			}
		}
	}
	return $ret;
}

##
# Internal helper to read the interfaces file
# return: JSON containing the interfaces file
sub _interfacesJson {
	unless( defined( $interfacesJson )) {
		if( -r $interfacesFile ) {
            $interfacesJson = IndieBox::Utils::readJsonFromFile( $interfacesFile );
        } else {
			IndieBox::Logging::warn( 'Cannot read', $interfacesFile, '. Is an indie-device package installed?' );
			$interfacesJson = {};
		}
	}
	return $interfacesJson;
}

##
# Internal helper to execute "ip link" and parse the output
sub _ipLinks {
	unless( defined( $ipLinks )) {
		my $out;
		IndieBox::Utils::myexec( 'ip link show', undef, \$out );
		
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
# Set a particular networking configuration. This method has different
# ways of invoking it, so pay attention.
# $dhcpClientNicInfo:
#      if this is an array, it contains the list of NIC names that shall
#          receive their IP address via DHCP
#      if this is 1, it means all NICs shall receive their IP address
#          via DHCP
#      if this is undef, it means no NIC shall receive their IP address
#          via DHCP
# $privateNetworkNicInfo:
#      if this is an array, it contains the list of NIC names that shall
#          be assigned a locally managed IP address, e.g. in 192.168.0.0/16
#      if this is 1, it means all NICs shall be assigned a locally managed
#          IP address
#      if this is undef, it means no NIC shall be assigned a locally
#          managed IP address
# if both parameter is undef, it means deactivate all interfaces
sub setNetConfig {
    my $dhcpClientNicInfo     = shift;
    my $privateNetworkNicInfo = shift;

    print 'setNetConfig( '
            . ( defined( $dhcpClientNicInfo ) ? ( ref( $dhcpClientNicInfo ) ? ( '<' . join( ', ', @$dhcpClientNicInfo ) . '>' ) : $dhcpClientNicInfo ) : '-' )
            . ', '
            . ( defined( $privateNetworkNicInfo ) ? ( ref( $privateNetworkNicInfo ) ? ( '<' . join( ', ', @$privateNetworkNicInfo ) . '>' ) : $privateNetworkNicInfo ) : '-' )
            . ' )'
            . "\n";

    my $networkJson = IndieBox::Utils::readJsonFromFile( 'etc/indie-box/networking/managed-network.json' ); # do this first, so it fails first
    my $allNics     = getAllNics();

    # Decode
    my @dhcpClientNics;
    my @privateNetworkNics;
    
    if( !$dhcpClientNicInfo ) {
        @dhcpClientNics = ();
    } elsif( ref( $dhcpClientNicInfo )) {
        @dhcpClientNics = @$dhcpClientNicInfo;
    } else {
        @dhcpClientNics = keys %$allNics;
    }
    if( !$privateNetworkNicInfo ) {
        @privateNetworkNics = ();
    } elsif( ref( $privateNetworkNicInfo )) {
        @privateNetworkNics = @$privateNetworkNicInfo;
    } else {
        @privateNetworkNics = keys %$allNics;
    }

    # Turn off everything: DNS, DHCP, DHCPC, UFW, and all interfaces
    _stopService( 'dnsmasq' );
    _stopService( 'stop dhcpcd@*.service' );
    IndieBox::Utils::myexec( 'which ufw 2>/dev/null && ufw disable' ); # only execute if installed
    _stopService( 'ufw' );

    foreach my $nic ( keys %$allNics ) {
        IndieBox::Utils::myexec( "netctl stop $nic" );
        IndieBox::Utils::myexec( "netctl disable $nic" );

        if( -e "/etc/netctl/$nic" ) {
            IndieBox::Utils::deleteFile( "/etc/netctl/$nic" );
        }
    }

    my $tmplDir = '/usr/share/indie-box-networking/tmpl';
    my $config  = new IndieBox::Configuration( "NetConfigUtils", { 'networking' => $networkJson }, IndieBox::Host::config() );


    if( $dhcpClientNicInfo ) {
        # Need firewall if we have an upstream    

        _startService( 'ufw' );

        IndieBox::Utils::myexec( 'ufw default deny' );
        IndieBox::Utils::myexec( 'ufw reject from any' );
        IndieBox::Utils::myexec( 'ufw limit SSH' ); # Seems like a good idea
        IndieBox::Utils::myexec( 'ufw allow from any port 68 to any port 67 proto udp' ); # Allow DHCP
        IndieBox::Utils::myexec( 'ufw enable' );
    }

    if( $privateNetworkNicInfo ) {
        # Turn on dnsmasq
        IndieBox::Utils::myExec( "install -m644 $tmplDir/dnsmasq.conf /etc/dnsmasq.conf" );
        _parameterizeFile( $config, "$tmplDir/dnsmasq.indie.conf.tmpl", '/etc/dnsmasq.d/dnsmasq.indie.conf' );
        _parameterizeFile( $config, "$tmplDir/etc-resolve.conf.head.tmpl", '/etc/resolv.conf.head' );

        _startService( 'dnsmasq' );

        if( $dhcpClientNicInfo ) {
            my $privateNetwork = $config->getResolve( 'networking.network.ip' );
            
            IndieBox::Utils::myexec( 'ufw allow from ' . $privateNetwork );
        }
 
    } else {
        if( -e '/etc/dnsmasq.d/dnsmasq.indie.conf' ) {
            IndieBox::Utils::deleteFile( '/etc/dnsmasq.d/dnsmasq.indie.conf' );
        }
        if( -e '/etc/resolve.conf.head' ) {
            IndieBox::Utils::deleteFile( '/etc/resolve.conf.head' );
        }
    }

    # Turn on upstream interfaces
    foreach my $nic ( @dhcpClientNics ) {
        IndieBox::Utils::myexec( 'systemctl enable dhcpcd@' . $nic . '.service' );
        IndieBox::Utils::myexec( 'systemctl restart dhcpcd@' . $nic . '.service' );
        
        IndieBox::Utils::myexec( "ip link set dev $nic up" );
    }

    # Turn on downstream interfaces
    foreach my $nic ( @privateNetworkNics ) {
        my $nicParam = { 'foo' => 'bar' }; # FIXME
        my $config2  = new IndieBox::Configuration( "NetConfigUtils $nic", $nicParam, $config );
        _parameterizeFile( $config2, "$tmplDir/eth-static.tmpl", '/etc/netctl/' . $nic );
        
        IndieBox::Utils::myexec( "netctl start $nic" );
        IndieBox::Utils::myexec( "netctl enable $nic" );
    }
}

##
# Determine whether the system is in a particular network configuration.
# Parameters are the same as for #setNetConfig.
sub isNetConfig {
    my $dhcpClientNicInfo     = shift;
    my $privateNetworkNicInfo = shift;

    warn( 'Not implemented at this time' );

    0;
}

##
# Start a daemon, but install first if needed
sub _startService {
    my $service = shift;
    my $package = shift || $service;

    if( $package ) {
        IndieBox::Host::ensurePackages( $package );
    }

    # Status messages unfortunately go to stderr
    my $out;
    my $err;
    IndieBox::Utils::myexec( 'systemctl enable '  . $service, undef, \$out, \$err );
    IndieBox::Utils::myexec( 'systemctl restart ' . $service, undef, \$out, \$err );
}

##
# Stop a daemon
sub _stopService {
    my $service = shift;

    my $out;
    my $err;
    IndieBox::Utils::myexec( 'systemctl stop ' . $service, undef, \$out, \$err );

    if( $err !~ m!No such file or directory! && $err !~ m!not loaded! ) {
        IndieBox::Utils::myexec( 'systemctl disable ' . $service, undef, \$out, \$err );
    }
}

##
# Read a file, parameterize it with config, and save it in some other place
sub _parameterizeFile {
    my $config      = shift;
    my $srcFile     = shift;
    my $destFile    = shift;
    my $permissions = shift;
    
    my $content = IndieBox::Utils::slurpFile( $srcFile );
    $content    = $config->replaceVariables( $content );
    IndieBox::Utils::saveFile( $destFile, $content, $permissions );
}
        
1;

