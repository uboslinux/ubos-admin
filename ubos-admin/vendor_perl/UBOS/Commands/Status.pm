#!/usr/bin/perl
#
# Command that determines and prints the current status of the device.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Status;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use POSIX;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;

my %defaultDiskFields = ();
map { $defaultDiskFields{$_} = 1; } qw (
    size
    mountpoint
    fsuse%
    fssize
    type
    smart_status_passed
); # name is shown separately


# above these we report problems
my $PROBLEM_DISK_PERCENT         = 70;
my $PROBLEM_LOAD_PER_CPU_PERCENT = 70;
my $PRODUCT_FILE                 = '/etc/ubos/product.json';

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    my $verbose         = 0;
    my $logConfigFile   = undef;
    my $debug           = undef;
    my $showJson        = 0;
    my $showAll         = 0;
    my $showDetail      = 0;
    my $showChannel     = 0;
    my $showCpu         = 0;
    my $showDisks       = 0;
    my $showFailed      = 0;
    my $showLastUpdated = 0;
    my $showMemory      = 0;
    my $showPacnew      = 0;
    my $showProblems    = 0;
    my $showProduct     = 0;
    my $showReady       = 0;
    my $showSmart       = 0;
    my $showVirt        = 0;
    my $showUptime      = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'       => \$verbose,
            'logConfig=s'    => \$logConfigFile,
            'debug'          => \$debug,
            'json'           => \$showJson,
            'all'            => \$showAll,
            'detail'         => \$showDetail,
            'channel'        => \$showChannel,
            'cpu'            => \$showCpu,
            'disks'          => \$showDisks,
            'failed'         => \$showFailed,
            'lastupdated'    => \$showLastUpdated,
            'memory'         => \$showMemory,
            'pacnew'         => \$showPacnew,
            'problems'       => \$showProblems,
            'product'        => \$showProduct,
            'ready'          => \$showReady,
            'smart'          => \$showSmart,
            'virtualization' => \$showVirt,
            'uptime'         => \$showUptime );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    my $isVirt = 0;
    my $out;

    my $json = {
        'hostid'           => UBOS::Host::hostId(),
        'ubos-admin-ready' => UBOS::Host::checkReady(),
        'problems'         => []
    }; # We create a JSON file, and either emit that, or format it to text

    trace( 'Detect virtualization first' );

    UBOS::Utils::myexec( 'systemd-detect-virt', undef, \$out );
    $out =~ s!^\s+!!;
    $out =~ s!\s+$!!;
    $json->{systemd_detect_virt} = $out;
    if( $json->{systemd_detect_virt} ne 'none' ) {
        $isVirt = 1;
    }

    my $showAspect =    $showChannel || $showCpu         || $showDisks
                     || $showFailed  || $showLastUpdated || $showMemory
                     || $showPacnew  || $showProblems    || $showProduct
                     || $showReady   || $showSmart       || $showVirt
                     || $showUptime;

    if(    !$parseOk
        || ( $showAll  && $showAspect )
        || ( $showJson && ( $showAll || $showAspect ))
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }
    if( $showSmart && $isVirt ) {
        fatal( 'Cannot show S.M.A.R.T. disk health in a virtualized system' );
    }

    if( $showAll ) {
        $showChannel     = 1;
        $showCpu         = 1;
        $showDisks       = 1;
        $showFailed      = 1;
        $showLastUpdated = 1;
        $showMemory      = 1;
        $showPacnew      = 1;
        $showProblems    = 1;
        $showProduct     = 1;
        $showReady       = 1;
        $showSmart       = !$isVirt;
        $showVirt        = 1;
        $showUptime      = 1;

    } elsif( !$showAspect ) {
        # default
        $showChannel     = 1;
        $showDisks       = 1;
        $showLastUpdated = 1;
        $showMemory      = 1;
        $showProblems    = 1;
        $showProduct     = 1;
        $showReady       = 1;
        $showSmart       = !$isVirt;
        $showUptime      = 1;
    }

    my $nCpu;
    my %loads;

    trace( 'Checking CPU' );

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

        my $smartCmd = ( -x '/usr/bin/smartctl' && !$isVirt ) ? '/usr/bin/smartctl -H -j' : undef;

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

                } else {
                    warning( 'Failed to parse smartctl json:', $@ );
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
            unless( $showFailed ) {
                # don't report twice
                push @{$json->{problems}}, 'System service ' . $failedService . ' has failed.';
            }
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


    # now display (or not)

    unless( @{$json->{problems}} ) {
        delete $json->{problems};
    }

    if( $showJson ) {
        UBOS::Utils::writeJsonToStdout( $json );

    } else {
        # will print to console
        my $out  = 'Status: host ' . $json->{hostid} . "\n";
        $out .= '=' x ( length( $out )-1 ) . "\n";

        colPrint( $out );

        $out = ''; # reset $out

        if( $showProduct ) {
            $out .= "Product:\n";
            if( exists( $json->{product}->{name} )) {
                $out .= '    Name:           ' . $json->{product}->{name} . "\n";
            } else {
                $out .= '    Name:           ' . '?' . "\n";
            }
            if( exists( $json->{product}->{vendor} )) {
                $out .= '    Vendor:         ' . $json->{product}->{vendor} . "\n";
            }
            if( exists( $json->{product}->{sku} )) {
                $out .= '    SKU:            ' . $json->{product}->{sku} . "\n";
            }
        }
        if( $showVirt ) {
            if( exists( $json->{systemd_detect_virt} )) {
                $out .= 'Virtualization:     ' . $json->{systemd_detect_virt} . "\n";
            } else {
                $out .= 'Virtualization:     ' . '?' . "\n";
            }
        }

        if( $showReady ) {
            $out .= "Ready:\n";
            if( exists( $json->{'ubos-admin-ready'} ) && exists( $json->{'ubos-admin-ready'} )) {
                $out .= '    since:          ' . _formatTimeStamp( $json->{'ubos-admin-ready'} ) . "\n";
            } else {
                $out .= "    NOT READY\n";
            }
        }

        if( $showLastUpdated ) {
            $out .= 'Last updated:       ' . _formatTimeStamp( $json->{lastupdated} ) . "\n";
        }

        if( $showChannel ) {
            $out .= 'Channel:            ' . $json->{channel} . "\n";
        }

        if( $showCpu ) {
            $out .= "CPU:\n";
            $out .= '    number:         ' . $json->{cpu}->{ncpu} . "\n";
            if( exists( $json->{cpu}->{virttype} )) {
                $out .= '    virtualization: ' . $json->{cpu}->{virttype} . "\n";
            }
        }

        if( $showUptime ) {
            my $uptime = $json->{uptime};
            $out .= "Uptime:\n";
            $out .= '    for:            ' . $uptime->{uptime} . "\n";
            $out .= '    load avg:       ' . $uptime->{loadavg1}  . ' (1 min) '
                                           . $uptime->{loadavg5}  . ' (5 min) '
                                           . $uptime->{loadavg15} . " (15 min)\n";

            if( $showDetail ) {
                $out .= '    users:    ' .  $uptime->{nusers} . "\n";
            }
        }

        if( $showDisks || $showSmart ) {
            $out .= "Disks:\n";
            foreach my $blockDevice ( @{$json->{blockdevices}} ) {
                $out .= "    " . $blockDevice->{name} . "\n";
                if( $showDisks ) {
                    foreach my $att ( sort keys %$blockDevice ) {
                        my $val = $blockDevice->{$att};
                        if( _printDiskAtt( $att, $val, $showDetail )) {
                            $out .= "        $att: $val\n";
                        }
                    }
                }
                if( $showSmart ) {
                    # Maybe we need to show more here?
                    if(    exists( $blockDevice->{smart} )
                        && exists( $blockDevice->{smart}->{smart_status} )
                        && exists( $blockDevice->{smart}->{smart_status}->{passed} ))
                    {
                        if( $blockDevice->{smart}->{smart_status}->{passed} ) {
                            $out .= "        S.M.A.R.T. status: passed\n";
                        } else {
                            $out .= "        S.M.A.R.T. status: NOT passed\n";
                        }
                    } else {
                        $out .= "        S.M.A.R.T. status: ?\n";
                    }
                }
                if( $showDisks ) {
                    if( exists( $blockDevice->{children} )) {
                        foreach my $childBlockDevice ( @{$blockDevice->{children}} ) {
                            $out .= "        " . $childBlockDevice->{name} . "\n";
                            foreach my $att ( sort keys %$childBlockDevice ) {
                                my $val = $childBlockDevice->{$att};
                                if( _printDiskAtt( $att, $val, $showDetail )) {
                                    $out .= "            $att: $val\n";
                                }
                            }
                        }
                    }
                }
            }
        }

        if( $showMemory ) {
            $out .= "Memory:             total       used        free        shared      buff/cache  available \n";

            my @memcats;
            if( $showDetail ) {
                @memcats = qw( mem low high swap total );
            } else {
                @memcats = qw( mem swap total );
            }

            foreach my $memcat ( @memcats ) {
                my $mem = $json->{memory}->{$memcat};
                $out .= sprintf(
                        "    %-10s %11s %11s %11s %11s %11s %11s\n",
                        uc( substr( $memcat, 0, 1 )) . substr( $memcat, 1 ) . ':',
                        exists( $mem->{total} )     ? _formatBytes( $mem->{total} )     : '',
                        exists( $mem->{used} )      ? _formatBytes( $mem->{used} )      : '',
                        exists( $mem->{free} )      ? _formatBytes( $mem->{free} )      : '',
                        exists( $mem->{shared} )    ? _formatBytes( $mem->{shared} )    : '',
                        exists( $mem->{buffcache} ) ? _formatBytes( $mem->{buffcache} ) : '',
                        exists( $mem->{available} ) ? _formatBytes( $mem->{available} ) : '');
            }
        }

        if( $showFailed ) {
            $out .= "Failed system services:\n";
            if( @{$json->{failedservices}} ) {
                foreach my $service ( @{$json->{failedservices}} ) {
                    $out .= "    $service\n";
                }
            } else {
                $out .= "    None\n";
            }
        }
        if( $showPacnew ) {
            $out .= "Changed config files (.pacnew):\n";
            if( @{$json->{pacnew}} ) {
                if( $showDetail ) {
                    $out .= join( '', map( "        $_\n", @{$json->{pacnew}} ));
                } else {
                    $out .= "    " . ( 0 + @{$json->{pacnew}} ) . "\n";
                }
            } else {
                $out .= "    None\n";
            }
        }

        if( $showProblems ) {
            $out .= "Problems:\n";
            if( exists( $json->{problems} )) {
                $out .= join( "", map { "    * $_\n" } @{$json->{problems}} ) . "\n";
            } else {
                $out .= "    None\n";
            }
        }

        colPrint( $out );
    }

    return 1;
}

##
# Helper method to determine whether to print a block device attribute
# $name: name of the attribute
# $value: value of the attribute
# $showDetail: show detail, or not
# return: true or false
sub _printDiskAtt {
    my $name       = shift;
    my $value      = shift;
    my $showDetail = shift;

    if( ref( $value )) {
        return 0;
    }
    unless( defined( $value )) {
        return 0;
    }
    if( $showDetail ) {
        return 1;
    }
    return $defaultDiskFields{$name};
}

##
# Helper method to format integers with byte sizes with prefix
# $n: the number
# return: formatted
sub _formatBytes {
    my $n = shift;

    my @units = ( '  B', qw( kiB MiB GiB TiB ));
    my $fract = '';
    foreach my $unit ( @units ) {
        if( $n < 1024 ) {
            return "$n$fract $unit";
        }
        my $floor = floor( $n/1024 );
        $fract = floor( 10 * ( $n/1024 - $floor ));
        if( $fract == 0 ) {
            $fract = '';
        } else {
            $fract = ".$fract";
        }
        $n = $floor;
    }
    return "$n$fract " . $units[-1];
}

##
# Format a time stamp
# $ts: time stamp
# return: formatted
sub _formatTimeStamp {
    my $ts = shift;

    if( $ts =~ m!^(\d\d\d\d)(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)! ) {
        return "$1/$2/$3 $4:$5:$6";
    } else {
        return $ts; # best we can do
    }
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

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Report on the status of this device.
SSS
        'cmds' => {
            <<SSS => <<HHH,
    [--channel] [--cpu] [--disks] [--failed] [--lastupdated] [--memory] [--pacnew] [--ready] [--uptime]
SSS
    If any of the optional arguments are given, only report on the
    specified subjects:
    * channel:        report on the UBOS release channel used by this device.
    * cpu:            report on the CPUs available.
    * disks:          report on attached disks and their usage.
    * failed:         report on daemons that have failed.
    * lastupdated:    report when the device was last updated.
    * memory:         report how much RAM and swap memory is being used.
    * pacnew:         report on manually modified configuration files.
    * problems:       report on any detected problems.
    * product:        report on the product.
    * ready:          report whether the device is ready or not.
    * smart:          report on disk health via S.M.A.R.T.
    * virtualization: report on the use of virtualization.
    * uptime:         report how long the device has been up since last boot.
HHH
            <<SSS => <<HHH
    --all
SSS
    Report on all subjects
            <<SSS => <<HHH
    --json
SSS
    Report on all subjects and output JSON
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--detail' => <<HHH,
    Add more detail where available
HHH
        }
    };
}

1;
