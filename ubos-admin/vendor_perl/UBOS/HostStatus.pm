#!/usr/bin/perl
#
# Factors out determining the status of the current device. This is
# essentially a singleton object whose fields are calculated on demand.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::HostStatus;

use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

# above these thresholds we report errors
my $ERROR_DISK_PERCENT         = 90;
my $ERROR_LOAD_PER_CPU_PERCENT = 90;

# above these thresholds we report warnings
my $WARNING_DISK_PERCENT         = 70;
my $WARNING_LOAD_PER_CPU_PERCENT = 70;

# files where to get info from
my $PRODUCT_FILE                 = '/etc/ubos/product.json';

# Location of the update backups
my $updateBackupDir = '/ubos/backups/update';

# cached data -- inserted as needed
my $json = {};


##
# Is this system virtualized?
# return: string with type of virtualization, or undef
sub virtualization {
    unless( exists( $json->{systemd_detect_virt} )) {
        trace( 'Detect virtualization' );

        my $out;
        UBOS::Utils::myexec( 'systemd-detect-virt', undef, \$out );
        $out =~ s!^\s+!!;
        $out =~ s!\s+$!!;
        if( $out eq 'none' ) {
            $json->{systemd_detect_virt} = undef;
        } else {
            $json->{systemd_detect_virt} = $out;
        }
    }
    return $json->{systemd_detect_virt};
}

##
# Obtain the host id. It is determined as a
# fingerprint of the host key and unique.
# return: string
sub hostId {
    unless( exists( $json->{hostid} )) {

        my $out;
        my $err;
        if( myexec( 'GNUPGHOME=/etc/pacman.d/gnupg gpg --fingerprint pacman@localhost', undef, \$out, \$err )) {
            error( 'Cannot determine host key', $out, $err );
            return undef;
        }
        # gpg: WARNING: unsafe permissions on homedir '/etc/pacman.d/gnupg'
        # pub   rsa2048/B0B434F0 2015-02-15
        #       Key fingerprint = 26FC BC8B 874A 9744 7718  5E8C 5311 6A36 B0B4 34F0
        # uid       [ultimate] Pacman Keyring Master Key <pacman@localhost>
        # 2016-07: apparently the "Key fingerprint =" is not being emitted any more

        my $hostId;
        if( $out =~ m!((\s+[0-9A-F]{4}){10})!m ) {
            $hostId = lc( $1 );
            $hostId =~ s!\s+!!g;
        } else {
            error( 'Unexpected fingerprint format:', $out );
            $hostId = undef;
        }
        $json->{hostid} = $hostId;
    }
    return $json->{hostid};
}

##
# Obtain the hostname.
# return: string
sub hostname {
    unless( exists( $json->{hostname} )) {
        $json->{hostname} = UBOS::Host::hostname();
    }
    return $json->{hostname};
}

##
# Information about the product
# return: JSON hash
sub productJson {
    unless( exists( $json->{product} )) {
        trace( 'Determine product' );
        if( -e $PRODUCT_FILE ) {
            $json->{product} = UBOS::Utils::readJsonFromFile( $PRODUCT_FILE );
        } else {
            $json->{product} = {
                'name' => 'UBOS'
            };
        }
    }
    return $json->{product};
}

##
# Information about UBOS Live status
# return: JSON hash
sub liveJson {
    unless( exists( $json->{live} )) {

        trace( 'Check UBOS Live status' );

        my $liveActive = eval "use UBOS::Live::UbosLive;  UBOS::Live::UbosLive::isUbosLiveActive();";
        if( $@ ) {
            # error --not installed
            $json->{live} = {
                'active'    => $JSON::false,
                'installed' => $JSON::false
            };
        } else {
            $json->{live} = {
                'active'    => $liveActive ? $JSON::true : $JSON::false,
                'installed' => $JSON::true
            };
        }
    }
    return $json->{live};
}

##
# Obtain the device arch
# return: string
sub arch {
    unless( exists( $json->{arch} )) {
        $json->{arch} = UBOS::Utils::arch();
    }
    return $json->{arch};
}

##
# Obtain the device class
# return: string
sub deviceClass {
    unless( exists( $json->{deviceclass} )) {
        $json->{deviceclass} = UBOS::Utils::deviceClass();
    }
    return $json->{deviceclass};
}

##
# Since when has this device been in state ubos-ready.
# return: UNIX time or undef if not ready
sub readySince {
    unless( exists( $json->{'ubos-admin-ready'} )) {
        $json->{'ubos-admin-ready'} = UBOS::Host::isReady();
    }
    return $json->{'ubos-admin-ready'};
}

##
# When was this device class updated
# return: UNIX time or undef if never
sub lastUpdated {
    unless( exists( $json->{lastUpdated} )) {
        trace( 'Determining when last updated' );
        $json->{lastUpdated} = UBOS::Host::lastUpdated();
    }
    return $json->{lastUpdated};
}

##
# Determine this device's release channel
# return: string
sub channel {
    unless( exists( $json->{channel} )) {
        trace( 'Obtaining channel' );
        my $channel = UBOS::Utils::slurpFile( '/etc/ubos/channel' );
        $channel =~ s!^\s+!!;
        $channel =~ s!\s+$!!;
        $json->{channel} = $channel;
    }
    return $json->{channel};
}

##
# Determine information about CPU(s).
# return: JSON
sub cpuJson {
    unless( exists( $json->{cpu} )) {

        trace( 'Checking CPU' );

        my $nCpu;
        my %loads;
        my $out;

        debugAndSuspend( 'Executing lscpu' );
        UBOS::Utils::myexec( "lscpu --json", undef, \$out );
        if( $out ) {
            my $newJson = UBOS::Utils::readJsonFromString( $out );

            my %relevants = (
                    'Architecture'        => 'architecture',
                    'CPU\(s\)'            => 'ncpu',
                    'Vendor ID'           => 'vendorid',
                    'Model name'          => 'modelname',
                    'CPU MHz'             => 'cpumhz',
                    'Virtualization type' => 'virttype'
            );
            foreach my $entry ( @{$newJson->{lscpu}} ) {
                foreach my $relevant ( keys %relevants ) {
                    if( $entry->{field} =~ m!^$relevant:$! ) {
                        $json->{cpu}->{$relevants{$relevant}} = $entry->{data};
                    }
                }
            }
        } else {
            warning( 'Could not determine CPUs' );
            $json->{cpu} = undef;
        }
    }
    return $json->{cpu};
}

##
# Determine information about uptime
# return: JSON
sub uptimeJson {
    unless( exists( $json->{uptime} )) {

        trace( 'Checking uptime' );
        debugAndSuspend( 'Executing w' );

        my $out;
        UBOS::Utils::myexec( "w -f -u", undef, \$out );

        $json->{uptime}->{users} = [];

        my @lines = split /\n/, $out;
        my $first = shift @lines;

        if( $first =~ m!^\s*(\d+:\d+:\d+)\s*up\s*(.+),\s*(\d+)\s*users?,\s*load\s*average:\s*([^,]+),\s*([^,]+),\s*([^,]+)\s*$! ) {
            $json->{uptime}->{time}      = $1;
            $json->{uptime}->{uptime}    = $2;
            $json->{uptime}->{nusers}    = $3;
            $json->{uptime}->{loadavg1}  = $4;
            $json->{uptime}->{loadavg5}  = $5;
            $json->{uptime}->{loadavg15} = $6;

            shift @lines; # remove line "USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT"
            foreach my $line ( @lines ) {
                if( $line =~ m!^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*?)\s*$! ) {
                    push @{$json->{uptime}->{users}}, {
                        'user'  => $1,
                        'tty'   => $2,
                        'from'  => $3,
                        'login' => $4,
                        'idle'  => $5,
                        'jcpu'  => $6,
                        'pcpu'  => $7,
                        'what'  => $8,
                    };
                }
            }
        }
    }
    return $json->{uptime};
}

##
# Determine the device's public key
# return: string
sub hostPublicKey {
    unless( exists( $json->{publickey} )) {
        trace( 'Host public key' );

        my $out;
        my $err;
        if( myexec( 'GNUPGHOME=/etc/pacman.d/gnupg gpg --export --armor pacman@localhost', undef, \$out, \$err )) {
            error( 'Cannot determine host key', $out, $err );
            return undef;
        }
        # gpg: WARNING: unsafe permissions on homedir '/etc/pacman.d/gnupg'
        # gpg: Warning: using insecure memory!
        # -----BEGIN PGP PUBLIC KEY BLOCK-----

        # mQENBFyhL+IBCADGzNkwXtMnZ8fHE5MddJ8fEJGeraqKtTOwc4udAed8EFFgCyCs
        # ...
        # ymqmWp6TWcU3DN7Qz1XutKzCjVCpnmELGU3XLaNjAQ==
        # =7xqV
        # -----END PGP PUBLIC KEY BLOCK-----

        my $publicKey;
        if( $out =~ m!(-+BEGIN PGP PUBLIC KEY BLOCK-+.+-+END PGP PUBLIC KEY BLOCK-+)!s ) {
            $publicKey = $1;
        } else {
            error( 'Failed to parse public key on host' );
            $publicKey = undef;
        }
        $json->{publickey} = $publicKey;
    }
    return $json->{publickey};
}

##
# Determine information about block devices
# return: JSON
sub blockDevicesJson {
    unless( exists( $json->{blockdevices} )) {

        trace( 'Checking disks' );
        debugAndSuspend( 'Executing lsblk' );

        my $out;
        UBOS::Utils::myexec( "lsblk --json --output-all --paths", undef, \$out );
        if( $out ) {
            my $newJson = UBOS::Utils::readJsonFromString( $out );

            my $smartCmd = ( -x '/usr/bin/smartctl' && !virtualization()) ? '/usr/bin/smartctl -H -j' : undef;

            $json->{blockdevices} = [];
            foreach my $blockDevice ( @{$newJson->{blockdevices}} ) {
                if( $blockDevice->{type} eq 'rom' ) {
                    next;
                }
                my $name       = $blockDevice->{name};
                my $fstype     = $blockDevice->{fstype};
                my $mountpoint = $blockDevice->{mountpoint};

                if( $fstype ) {
                    $blockDevice->{usage} = _usageAsJson( $name, $fstype, $mountpoint );
                }

                if( $smartCmd ) {
                    UBOS::Utils::myexec( "$smartCmd $name", undef, \$out );
                    my $smartJson = UBOS::Utils::readJsonFromString( $out );
                    if( $smartJson && exists( $smartJson->{smart_status} )) {
                        $blockDevice->{smart} = $smartJson;

                    } elsif(    $smartJson
                             && exists( $smartJson->{smartctl} )
                             && exists( $smartJson->{smartctl}->{messages} )
                             && @{$smartJson->{smartctl}->{messages}} )
                    {
                        # some warning or error, but this is not material here

                    } else {
                        warning( 'Failed to parse smartctl json for device', $name, ':', $out );
                    }
                }

                foreach my $childDevice ( @{$blockDevice->{children}} ) {
                    my $childName       = $childDevice->{name};
                    my $childFstype     = $childDevice->{fstype};
                    my $childMountpoint = $childDevice->{mountpoint};

                    if( $childFstype ) {
                        $childDevice->{usage} = _usageAsJson( $childName, $childFstype, $childMountpoint );
                    }
                }

                push @{$json->{blockdevices}}, $blockDevice;
            }
        }
    }
    return $json->{blockdevices};
}

##
# Determine memory information
# return: JSON
sub memoryJson {
    unless( defined( $json->{memory} )) {

        trace( 'Checking memory' );
        debugAndSuspend( 'Executing free' );

        my $out;
        UBOS::Utils::myexec( "free --bytes --lohi --total", undef, \$out );

        $json->{memory} = {};

        my @lines = split /\n/, $out;
        my $header = shift @lines;
        $header =~ s!^\s+!!;
        $header =~ s!\s+$!!;
        my @headerFields = map { my $s = $_; $s =~ s!/!!; $s; } split /\s+/, $header;
        foreach my $line ( @lines ) {
            $line =~ s!^\s+!!;
            $line =~ s!\s+$!!;
            my @fields = split /\s+/, $line;
            my $key    = shift @fields;
            my $max    = @headerFields;
            if( $max > @fields ) {
                $max = @fields;
            }
            $key =~ s!:!!;
            $key = lc( $key );
            for( my $i=0 ; $i<$max ; ++$i ) {
                $json->{memory}->{$key}->{$headerFields[$i]} = $fields[$i];
            }
        }
    }
    return $json->{memory};
}

##
# Determine snapper information
# return: JSON
sub snapperJson {
    unless( exists( $json->{snapper} )) {

        trace( 'Checking snapper snapshots' );

        my $out;
        my $err;
        if( UBOS::Utils::myexec( 'snapper --machine-readable json list --all', undef, \$out, \$err )) {
            $json->{snapper} = undef;
        } else {
            # even if snapper is not configured, this particular invocation will exit with 0 and produce an empty JSON hash
            $json->{snapper} = UBOS::Utils::readJsonFromString( $out );
        }
    }
    return $json->{snapper};
}

##
# Determine information about failed systemd units
# return: pointer to array
sub failedUnits {
    unless( exists( $json->{failedunits} )) {
        trace( 'Determining failed systemd units' );

        my $out;
        UBOS::Utils::myexec( 'systemctl --failed --output=json', undef, \$out );
        my $failedJson = UBOS::Utils::readJsonFromString( $out );

        $json->{failedunits} = [ map { $_->{unit} } @$failedJson ];
    }
    return $json->{failedunits};
}

##
# Find changed configuration files (.pacnew)
# return: array pointer
sub pacnewFiles {
    unless( exists( $json->{pacnew} )) {
        trace( 'Looking for .pacnew files' );
        debugAndSuspend( 'Executing find for .pacnew files' );

        my $out;
        UBOS::Utils::myexec( "find /boot /etc /usr -name '*.pacnew' -print", undef, \$out );

        if( $out ) {
            my @items = split /\n/, $out;
            $json->{pacnew} = \@items;
        } else {
            $json->{pacnew} = [];
        }
    }
    return $json->{pacnew};
}

##
# Determine all network interfaces of this host and their properties.
# return: JSON
sub nics {
    unless( exists( $json->{nics} )) {

        my $out;
        my $err; # swallow error messages
        myexec( "networkctl --no-pager --no-legend", undef, \$out, \$err );
        if( $err ) {
            trace( 'HostStatus::nics: networkctl said:', $err );
        }

        $json->{nics} = {};
        foreach my $line ( split "\n", $out ) {
            if( $line =~ /^\s*(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$/ ) {
                my( $index, $link, $type, $operational, $setup ) = ( $1, $2, $3, $4, $5 );

                my $n = {};

                $n->{index}       = $index;
                $n->{type}        = $type;
                $n->{operational} = $operational;
                $n->{setup}       = $setup;

                $json->{nics}->{$link} = $n;
            }
        }

        # Add IP addresses
        foreach my $nicName ( keys %{$json->{nics}} ) {
            my $nic   = $json->{nics}->{$nicName};
            my @allIp = ipAddressesOnNic( $nicName );
            $nic->{ipv4address} = [ grep { UBOS::Utils::isIpv4Address( $_ ) } @allIp ];
            $nic->{ipv6address} = [ grep { UBOS::Utils::isIpv6Address( $_ ) } @allIp ];
            $nic->{macaddress}  = macAddressOfNic( $nicName );
        }
    }
    return $json->{nics};
}

##
# Helper to determine whether a NIC is hardware
# $nicName: name of the NIC
# $nicType: type of the NIC
# return: true or false
sub _isHardwareNic {
    my $nicName = shift;
    my $nicType = shift;

    if(    $nicName !~ m!^(ve-|tun|tap|docker)!
        && $nicType !~ m!^loopback! )
    {
        return 1;
    } else {
        return 0;
    }
}

##
# Helper to determine whether a NIC is wireless land
# $nicName: name of the NIC
# $nicType: type of the NIC
# return: true or false
sub _isWlanNic {
    my $nicName = shift;
    my $nicType = shift;

    if( $nicType eq 'wlan' ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine the physical network interfaces of this host and their properties.
# return: JSON
sub hardwareNics {
    unless( exists( $json->{hardwarenics} )) {

        my $nics = nics();
        $json->{hardwarenics} = {};
        foreach my $nicName ( keys %$nics ) {
            my $nic = $nics->{$nicName};

            if( _isHardwareNic( $nicName, $nic->{type} )) {
                $json->{hardwarenics}->{$nicName} = $nic;
            }
        }
    }
    return $json->{hardwarenics};
}

##
# Determine the virtual network interfaces of this host and their properties.
# return: JSON
sub softwareNics {
    unless( exists( $json->{softwarenics} )) {

        my $nics = nics();
        $json->{softwarenics} = {};
        foreach my $nicName ( keys %$nics ) {
            my $nic = $nics->{$nicName};

            if( !_isHardwareNic( $nicName, $nic->{type} )) {
                $json->{softwarenics}->{$nicName} = $nic;
            }
        }
    }
    return $json->{softwarenics};
}

##
# Determine the wireless network interfaces of this host and their properties.
# return: JSON
sub wlanNics {
    unless( exists( $json->{wlannics} )) {

        my $nics = nics();
        $json->{wlannics} = {};
        foreach my $nicName ( keys %$nics ) {
            my $nic = $nics->{$nicName};

            if( _isWlanNic( $nicName, $nic->{type} )) {
                $json->{wlannics}->{$nicName} = $nic;
            }
        }
    }
    return $json->{wlannics};

}

##
# Determine IP addresses assigned to a network interface given by a
# name or a wildcard expression, e.g. "enp2s0" or "enp*".
#
# $nic: the network interface
# return: the zero or more IP addresses assigned to the interface
sub ipAddressesOnNic {
    my $nic = shift;

    my $nicRegex = $nic;
    $nicRegex =~ s!\*!.*!g;

    my $netctl;
    my $err; # swallow error messages
    myexec( "networkctl --no-pager --no-legend status", undef, \$netctl, \$err );
            # can't ask nic directly as we need wildcard support
    if( $err ) {
        trace( 'Host::nics: networkctl said:', $err );
    }

    my @ret = ();

    my $hasSeenAddressLine = 0;
    foreach my $line ( split "\n", $netctl ) {
        if( $hasSeenAddressLine ) {
            if( $line =~ m!^\s*Gateway:! ) {
                # "Gateway:" is the next item after "Address:", so we know we are done
                last;
            } else {
                if( $line =~ m!\s*(\S+)\s*on\s*(\S+)\s*$! ) {
                    my $foundIp  = $1;
                    my $foundNic = $2;

                    if( $foundNic =~ m!$nicRegex! ) {
                        push @ret, $foundIp;
                    }
                }
            }
        } else {
            # have not found one already
            if( $line =~ m!^\s*Address:\s*(\S+)\s*on\s*(\S+)\s*$! ) {
                my $foundIp  = $1;
                my $foundNic = $2;

                if( $foundNic =~ m!$nicRegex! ) {
                    push @ret, $foundIp;
                }
                $hasSeenAddressLine = 1;
            }
        }
    }
    return @ret;
}

##
# Obtain the Mac address of a nic
# $nic: the network interface
# return: the hardware address
sub macAddressOfNic {
    my $nic = shift;

    my $ret  = undef;
    my $file = "/sys/class/net/$nic/address";
    if( -e $file ) {
        $ret = UBOS::Utils::slurpFile( $file );
        $ret =~ s!^\s+!!;
        $ret =~ s!\s+$!!;
    }
    return $ret;
}

##
# Determine whether this device is connected to the internet.
# return: true or false
sub isOnline {
    unless( exists( $json->{online} )) {
        checkOnline();
    }
    return $json->{online};
}

##
# Attempt to check (again, if needed) whether this device is connected to the internet.
# return: true or false
sub updateOnline {
    my $ret;
    if( UBOS::Utils::isOnline() ) {
        $ret = 1;
    } else {
        $ret = 0;
    }
    $json->{online} = $ret;
    return $ret;
}

##
# Determine problems and warnings
# return: two array pointers: first is errors, second is warnings
sub problems {
    unless( exists( $json->{problems} )) {

        $json->{problems} = [];
        $json->{warnings} = [];

        # Something in the backup folder
        if( -d $updateBackupDir && !UBOS::Utils::isDirEmpty( $updateBackupDir )) {
            push @{$json->{problems}}, "Update backup directory is not empty: $updateBackupDir";
        }

        # CPU load
        my $cpuJson    = cpuJson();
        my $uptimeJson = uptimeJson();

        if( exists( $cpuJson->{ncpu} )) {
            my $nCpu = $cpuJson->{ncpu};

            my %loads;
            $loads{1}  = $uptimeJson->{loadavg1};
            $loads{5}  = $uptimeJson->{loadavg5};
            $loads{15} = $uptimeJson->{loadavg15};

            foreach my $period ( sort { $a <=> $b } keys %loads ) {
                if( $loads{$period} / $nCpu * 100 >= $ERROR_LOAD_PER_CPU_PERCENT ) {
                    push @{$json->{problems}},
                            'High CPU load: ' . $loads{$period} . " ($period min) with $nCpu CPUs.";

                } elsif( $loads{$period} / $nCpu * 100 >= $WARNING_LOAD_PER_CPU_PERCENT ) {
                    push @{$json->{warnings}},
                            'High CPU load: ' . $loads{$period} . " ($period min) with $nCpu CPUs.";
                }
            }
        }

        # Disks

        my $blockDevicesJson = blockDevicesJson();
        foreach my $blockDevice ( @$blockDevicesJson ) {

            if( exists( $blockDevice->{smart} )) {
                my $smartJson = $blockDevice->{smart};

                if(    exists( $smartJson->{smart_status} )
                    && (    !exists( $smartJson->{smart_status}->{passed} )
                         || !$smartJson->{smart_status}->{passed} ))
                {
                    # Not sure exactly what the output will be
                    push @{$json->{problems}}, 'Disk ' . $blockDevice->{name} . ' status is not "passed".';
                }

                if(    exists( $smartJson->{ata_smart_attributes} )
                    && exists( $smartJson->{ata_smart_attributes}->{table} ))
                {
                    foreach my $item ( @{$smartJson->{ata_smart_attributes}->{table}} ) {
                        if(    exists( $item->{when_failed} )
                            && $item->{when_failed}
                            && $item->{when_failed} ne 'past' )
                        {
                           push @{$json->{problems}}, 'Disk ' . $blockDevice->{name} . ', attribute "' . $item->{name} . '" is failing: "' . $item->{value} . '"';
                        }
                    }
                }
            }
            if( exists( $blockDevice->{'fsuse%' } )) {
                my $fsUsePercent = $blockDevice->{'fsuse%'};
                if( defined( $fsUsePercent )) {
                    my $numVal = $fsUsePercent;
                    $numVal =~ s!%!!;
                    if( $numVal > $ERROR_DISK_PERCENT ) {
                        push @{$json->{problems}}, 'Disk ' . $blockDevice->{name} . ' is almost full: ' . $fsUsePercent;

                    } elsif( $numVal > $WARNING_DISK_PERCENT ) {
                        push @{$json->{warnings}}, 'Disk ' . $blockDevice->{name} . ' is getting full: ' . $fsUsePercent;
                    }
                }
            }

            foreach my $childDevice ( @{$blockDevice->{children}} ) {
                if( exists( $childDevice->{'fsuse%' } )) {
                    my $fsUsePercent = $childDevice->{'fsuse%'};
                    if( defined( $fsUsePercent )) {
                        my $numVal = $fsUsePercent;
                        $numVal =~ s!%!!;
                        if( $numVal > $ERROR_DISK_PERCENT ) {
                            push @{$json->{problems}}, 'Disk ' . $childDevice->{name} . ' is almost full: ' . $fsUsePercent;

                        } elsif( $numVal > $WARNING_DISK_PERCENT ) {
                            push @{$json->{warnings}}, 'Disk ' . $childDevice->{name} . ' is getting full: ' . $fsUsePercent;
                        }
                    }
                }
            }
        }
    }

    return ( $json->{problems}, $json->{warnings} );
}

##
# Provide a full status as JSON. Compare liveJson().
# return: JSON
sub allAsJson {
    # add new methods here
    arch();
    blockDevicesJson();
    channel();
    cpuJson();
    deviceClass();
    failedUnits();
    hardwareNics();
    hostId();
    hostPublicKey();
    hostname();
    lastUpdated();
    liveJson();
    memoryJson();
    nics();
    pacnewFiles();
    problems();
    productJson();
    readySince();
    snapperJson();
    softwareNics();
    uptimeJson();
    virtualization();
    wlanNics();

    return $json;
}

##
# Live status as JSON. Compare allAsJson().
# return: JSON
sub liveAsJson {
    # add new methods here
    arch();
    blockDevicesJson();
    channel();
    cpuJson();
    deviceClass();
    failedUnits();
    hardwareNics();
    hostId();
    hostPublicKey();
    hostname();
    lastUpdated();
    liveJson();
    memoryJson();
    nics();
    pacnewFiles();
    problems();
    productJson();
    readySince();
    snapperJson();
    softwareNics();
    uptimeJson();
    virtualization();
    wlanNics();

    return $json;
}

##
# Helper method to determine the disk usage of a partition
# $device: the device, e.g. /dev/sda1
# $fstype: the file system type, e.g. btrfs
# $mountpoint: the mount point, e.g. /var
# return: a JSON hash showing usage
sub _usageAsJson {
    my $device     = shift;
    my $fstype     = shift;
    my $mountpoint = shift;

    my $ret = {};
    if( 'btrfs' eq $fstype && $mountpoint ) {
        # even if it is btrfs, if it's not mounted, we need to fall back to df
        my $out;
        UBOS::Utils::myexec( "btrfs filesystem df -h '$mountpoint'", undef, \$out );
        foreach my $line ( split "\n", $out ) {
            if( $out =~ m!^(\s+),\s*(\S+):\S*total=([^,]+),\S*used=(\S*)$! ) {
                $ret->{lc($1)} = {
                    'allocationprofile' => lc($2),
                    'total' => $3,
                    'used'  => $4
                };
            }
        }
    } else {
        my $out;
        UBOS::Utils::myexec( "df -h '$device' --output=used,size,pcent", undef, \$out );
        my @lines = split( "\n", $out );
        my $data  = pop @lines;
        $data =~ s!^\s+!!;
        $data =~ s!\s+$!!;
        my ( $used, $size, $pcent ) = split( /\s+/, $data );
        $ret->{'used'}  = $used;
        $ret->{'size'}  = $size;
        $ret->{'pcent'} = $pcent;
    }
    return $ret;
}

1;
