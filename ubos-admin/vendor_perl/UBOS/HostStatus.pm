#!/usr/bin/perl
#
# Factors out determining the status of the current device.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::HostStatus;

use UBOS::Logging;
use UBOS::Utils;

# above these we report problems
my $PROBLEM_DISK_PERCENT         = 70;
my $PROBLEM_LOAD_PER_CPU_PERCENT = 70;

my $PRODUCT_FILE                 = '/etc/ubos/product.json';

##
# Construct the status json for this device
# return: JSON
sub statusJson {

    my $json = {
        'arch'             => UBOS::Utils::arch(),
        'deviceclass'      => UBOS::Utils::deviceClass(),
        'hostid'           => UBOS::Host::hostId(),
        'ubos-admin-ready' => UBOS::Host::checkReady(),
        'problems'         => []
    };
    my $out;

    trace( 'Detect virtualization first' );

    UBOS::Utils::myexec( 'systemd-detect-virt', undef, \$out );
    $out =~ s!^\s+!!;
    $out =~ s!\s+$!!;
    if( $out ne 'none' ) {
        $json->{systemd_detect_virt} = $out;
    }

    trace( 'Checking CPU' );

    my $nCpu;
    my %loads;

    debugAndSuspend( 'Executing lscpu' );
    UBOS::Utils::myexec( "lscpu --json", undef, \$out );
    if( $out ) {
        my $newJson  = UBOS::Utils::readJsonFromString( $out );

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
        $nCpu = $json->{cpu}->{ncpu};
    }

    trace( 'Obtaining channel' );
    my $channel = UBOS::Utils::slurpFile( '/etc/ubos/channel' );
    $channel =~ s!^\s+!!;
    $channel =~ s!\s+$!!;
    $json->{channel} = $channel;

    trace( 'Checking disks' );

    debugAndSuspend( 'Executing lsblk' );
    UBOS::Utils::myexec( "lsblk --json --output-all --paths", undef, \$out );
    if( $out ) {
        my $newJson = UBOS::Utils::readJsonFromString( $out );

        my $smartCmd = ( -x '/usr/bin/smartctl' && exists( $json->{systemd_detect_virt} ) ) ? '/usr/bin/smartctl -H -j' : undef;

        $json->{blockdevices} = [];
        foreach my $blockdevice ( @{$newJson->{blockdevices}} ) {
            if( $blockdevice->{type} eq 'rom' ) {
                next;
            }
            my $name       = $blockdevice->{name};
            my $fstype     = $blockdevice->{fstype};
            my $mountpoint = $blockdevice->{mountpoint};

            if( $fstype ) {
                $blockdevice->{usage} = _usageAsJson( $name, $fstype, $mountpoint );
            }

            if( $smartCmd ) {
                UBOS::Utils::myexec( "$smartCmd $name", undef, \$out );
                my $smartJson = UBOS::Utils::readJsonFromString( $out );
                if( $smartJson && exists( $smartJson->{smart_status} )) {
                    $blockdevice->{smart} = $smartJson;

                    if(    exists( $smartJson->{smart_status} )
                        && (    !exists( $smartJson->{smart_status}->{passed} )
                             || !$smartJson->{smart_status}->{passed} ))
                    {
                        # Not sure exactly what the output will be
                        push @{$json->{problems}}, 'Disk ' . $name . ' status is not "passed".';
                    }

                    if(    exists( $smartJson->{ata_smart_attributes} )
                        && exists( $smartJson->{ata_smart_attributes}->{table} ))
                    {
                        foreach my $item ( @{$smartJson->{ata_smart_attributes}->{table}} ) {
                            if(    exists( $item->{when_failed} )
                                && $item->{when_failed}
                                && $item->{when_failed} ne 'past' )
                            {
                               push @{$json->{problems}}, 'Disk ' . $name . ', attribute "' . $item->{name} . '" is failing: "' . $item->{value} . '"';
                            }
                        }
                    }
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

            my $fusePercent = $blockdevice->{'fuse%'};
            if( defined( $fusePercent )) {
                my $numVal = $fusePercent;
                $numVal =~ s!%!!;
                if( $numVal > $PROBLEM_DISK_PERCENT ) {
                    push @{$json->{problems}}, 'Disk ' . $name . ' is almost full: ' . $fusePercent;
                }
            }

            foreach my $child ( @{$blockdevice->{children}} ) {
                my $childName       = $child->{name};
                my $childFstype     = $child->{fstype};
                my $childMountpoint = $child->{mountpoint};

                if( $childFstype ) {
                    $child->{usage} = _usageAsJson( $childName, $childFstype, $childMountpoint );
                }

                my $childFusePercent = $child->{'fuse%'};
                if( defined( $childFusePercent )) {
                    my $numVal = $childFusePercent;
                    $numVal =~ s!%!!;
                    if( $numVal > $PROBLEM_DISK_PERCENT ) {
                        push @{$json->{problems}}, 'Disk ' . $childName . ' is almost full: ' . $childFusePercent;
                    }
                }
            }

            push @{$json->{blockdevices}}, $blockdevice;
        }
    }

    trace( 'Determinig failed system services' );

    $json->{failedservices} = [];

    UBOS::Utils::myexec( 'systemctl --quiet --failed --full --plain --no-legend', undef, \$out );
    foreach my $line ( split( /\n/, $out )) {
        if( $line =~ m!^(.+)\.service! ) {
            my $failedService = $1;
            push @{$json->{failedservices}}, $failedService;
        }
    }

    trace( 'Determining when last updated' );

    my $lastUpdated = UBOS::Host::lastUpdated();
    $json->{lastupdated} = $lastUpdated;

    trace( 'Checking memory' );

    debugAndSuspend( 'Executing free' );
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

    trace( 'Looking for .pacnew files' );

    debugAndSuspend( 'Executing find for .pacnew files' );
    UBOS::Utils::myexec( "find /boot /etc /usr -name '*.pacnew' -print", undef, \$out );

    if( $out ) {
        my @items = split /\n/, $out;
        $json->{pacnew} = \@items;
    } else {
        $json->{pacnew} = [];
    }

    trace( 'Checking uptime' );

    debugAndSuspend( 'Executing w' );
    UBOS::Utils::myexec( "w -f -u", undef, \$out );

    $json->{uptime} = {};
    $json->{uptime}->{users} = [];

    @lines    = split /\n/, $out;
    my $first = shift @lines;

    if( $first =~ m!^\s*(\d+:\d+:\d+)\s*up\s*(.+),\s*(\d+)\s*users?,\s*load\s*average:\s*([^,]+),\s*([^,]+),\s*([^,]+)\s*$! ) {
        $json->{uptime}->{time}      = $1;
        $json->{uptime}->{uptime}    = $2;
        $json->{uptime}->{nusers}    = $3;
        $json->{uptime}->{loadavg1}  = $4;
        $json->{uptime}->{loadavg5}  = $5;
        $json->{uptime}->{loadavg15} = $6;

        $loads{1}  = $json->{uptime}->{loadavg1};
        $loads{5}  = $json->{uptime}->{loadavg5};
        $loads{15} = $json->{uptime}->{loadavg15};

        if( $nCpu ) {
            foreach my $period ( keys %loads ) {
                if( $loads{$period} / $nCpu * 100 >= $PROBLEM_LOAD_PER_CPU_PERCENT ) {
                    push @{$json->{problems}},
                            'High CPU load: '
                            . join( ' ', map { $loads{$_} . " ($_ min)" }
                                        sort { $a <=> $b }
                                        keys %loads )
                            . " with $nCpu CPUs.";
                    last;
                }
            }
        } else {
            push @{$json->{problems}}, 'Failed to determine loads and/or number CPUs';
        }
    }

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

    trace( 'Determine product' );
    if( -e $PRODUCT_FILE ) {
        $json->{product} = UBOS::Utils::readJsonFromFile( $PRODUCT_FILE );
    } else {
        $json->{product} = {
            'name' => 'UBOS'
        };
    }

    trace( 'Host public key' );
    $json->{publickey} = UBOS::Host::hostPublicKey();

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

    return $json;
}

1;
