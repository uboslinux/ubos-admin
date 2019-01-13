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
); # name is shown separately


# above these we report problems
my $PROBLEM_DISK_PERCENT         = 70;
my $PROBLEM_LOAD_PER_CPU_PERCENT = 70;

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
    my $showCpu         = 0;
    my $showDisks       = 0;
    my $showLastUpdated = 0;
    my $showMemory      = 0;
    my $showPacnew      = 0;
    my $showUptime      = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'debug'        => \$debug,
            'json'         => \$showJson,
            'all'          => \$showAll,
            'detail'       => \$showDetail,
            'cpu'          => \$showCpu,
            'disks'        => \$showDisks,
            'lastupdated'  => \$showLastUpdated,
            'memory'       => \$showMemory,
            'pacnew'       => \$showPacnew,
            'uptime'       => \$showUptime );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || ( $showAll && ( $showPacnew || $showDisks || $showMemory || $showUptime ))
        || ( $showJson && $showDetail )
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $showAll ) {
        $showCpu         = 1;
        $showDisks       = 1;
        $showMemory      = 1;
        $showPacnew      = 1;
        $showUptime      = 1;
        $showLastUpdated = 1;

    } elsif(    !$showCpu
             && !$showDisks
             && !$showMemory
             && !$showPacnew
             && !$showUptime
             && !$showLastUpdated )
    {
        # default
        $showDisks       = 1;
        $showMemory      = 1;
        $showUptime      = 1;
        $showLastUpdated = 1;
    }

    my $json = {
        'hostid'           => UBOS::Host::hostId(),
        'ubos-admin-ready' => UBOS::Host::checkReady()
    }; # We create a JSON file, and either emit that, or format it to text

    my $nCpu;
    my %loads;

    # always get CPU, so we know how many cores
    # don't always display
    if( 1 ) {
        trace( 'Checking CPU' );

        my $out;
        debugAndSuspend( 'Executing lscpu' );
        UBOS::Utils::myexec( "lscpu --json", undef, \$out );
        if( $out ) {
            my $newJson  = UBOS::Utils::readJsonFromString( $out );
            my $addJson = {};

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
                    if( $entry->{field} =~ m!$relevant! ) {
                        $addJson->{$relevants{$relevant}} = $entry->{data};
                    }
                }
            }
            if( $addJson->{ncpu} =~ m!^(\d+)-(\d+)$! ) {
                $nCpu = $2 - $1;
            } else {
                warning( 'Failed to parse nCPU field:', $addJson->{ncpu} );
            }
            if( $showCpu ) {
                $json->{cpu} = $addJson;
            }
        }
    }

    if( $showDisks ) {
        trace( 'Checking disks' );

        my $out;
        debugAndSuspend( 'Executing lsblk' );
        UBOS::Utils::myexec( "lsblk --json --output-all --paths", undef, \$out );
        if( $out ) {
            my $newJson = UBOS::Utils::readJsonFromString( $out );
            $json->{blockdevices} = [];
            foreach my $blockdevice ( @{$newJson->{blockdevices}} ) {
                my $name       = $blockdevice->{name};
                my $fstype     = $blockdevice->{fstype};
                my $mountpoint = $blockdevice->{mountpoint};

                if( $fstype ) {
                    $blockdevice->{usage} = _usageAsJson( $name, $fstype, $mountpoint );
                }

                foreach my $child ( @{$blockdevice->{children}} ) {
                    my $childName       = $child->{name};
                    my $childFstype     = $child->{fstype};
                    my $childMountpoint = $child->{mountpoint};

                    if( $childFstype ) {
                        $child->{usage} = _usageAsJson( $childName, $childFstype, $childMountpoint );
                    }
                }

                push @{$json->{blockdevices}}, $blockdevice;
            }
        }
    }

    if( $showLastUpdated ) {
        trace( 'Determining when last updated' );

        my $lastUpdated = UBOS::Host::lastUpdated();
        $json->{lastupdated} = $lastUpdated;
    }

    if( $showMemory ) {
        trace( 'Checking memory' );

        my $out;
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
    }

    if( $showPacnew ) {
        trace( 'Looking for .pacnew files' );

        my $out;
        debugAndSuspend( 'Executing find for .pacnew files' );
        UBOS::Utils::myexec( "find /boot /etc /usr -name '*.pacnew' -print", undef, \$out );

        if( $out ) {
            my @items = split /\n/, $out;
            $json->{pacnew} = \@items;
        }
    }

    # always get uptime, so we know the load
    # don't always display
    if( 1 ) {
        trace( 'Checking uptime' );

        my $out;
        debugAndSuspend( 'Executing w' );
        UBOS::Utils::myexec( "w -f -u", undef, \$out );

        my $uptime = {};
        $uptime->{users} = [];

        my @lines = split /\n/, $out;
        my $first = shift @lines;

        if( $first =~ m!^\s*(\d+:\d+:\d+)\s*up\s*(.+),\s*(\d+)\s*users?,\s*load\s*average:\s*([^,]+),\s*([^,]+),\s*([^,]+)\s*$! ) {
            $uptime->{time}      = $1;
            $uptime->{uptime}    = $2;
            $uptime->{nusers}    = $3;
            $uptime->{loadavg1}  = $4;
            $uptime->{loadavg5}  = $5;
            $uptime->{loadavg15} = $6;

            $loads{1}  = $uptime->{loadavg1};
            $loads{5}  = $uptime->{loadavg5};
            $loads{15} = $uptime->{loadavg15};
        }

        shift @lines; # remove line "USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT"
        foreach my $line ( @lines ) {
            if( $line =~ m!^\s*(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*?)\s*$! ) {
                push @{$uptime->{users}}, {
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

        if( $showUptime ) {
            $json->{uptime} = $uptime;
        }
    }

    if( $showJson ) {
        UBOS::Utils::writeJsonToStdout( $json );

    } else {
        # will print to console
        my $out  = 'Status: host ' . $json->{hostid} . "\n";
        $out .= '=' x ( length( $out )-1 ) . "\n";

        colPrint( $out );

        my @problems;

        if( keys %loads && $nCpu ) {
            foreach my $period ( keys %loads ) {
                if( $loads{$period} / $nCpu * 100 >= $PROBLEM_LOAD_PER_CPU_PERCENT ) {
                    push @problems,
                            'High CPU load: '
                            . join( ' ', map { $loads{$_} . " ($_ min)" }
                                        sort { $a <=> $b }
                                        keys %loads )
                            . " with $nCpu CPUs.";
                    last;
                }
            }
        } else {
            push @problems, 'Failed to determine loads and/or number CPUs';
        }

        $out = "Ready:\n";
        if( exists( $json->{'ubos-admin-ready'} ) && exists( $json->{'ubos-admin-ready'} )) {
            $out .= '    since: ' . _formatTimeStamp( $json->{'ubos-admin-ready'} ) . "\n";
        } else {
            $out .= "    NOT READY\n";
        }

        if( exists( $json->{lastupdated} )) {
            $out .= '    last updated: ' . _formatTimeStamp( $json->{lastupdated} ) . "\n";
        }

        if( exists( $json->{cpu} )) {
            $out .= "CPU:\n";
            $out .= '    number:         ' . $json->{cpu}->{ncpu} . "\n";
            $out .= '    virtualization: ' . $json->{cpu}->{virttype} . "\n";
        }

        if( exists( $json->{uptime} )) {
            my $uptime = $json->{uptime};
            $out .= "Uptime:\n";
            $out .= '    for:      ' . $uptime->{uptime} . "\n";
            $out .= '    load avg: ' . $uptime->{loadavg1}  . ' (1 min) '
                                     . $uptime->{loadavg5}  . ' (5 min) '
                                     . $uptime->{loadavg15} . " (15 min)\n";

            if( $showDetail ) {
                $out .= '    users:    ' .  $uptime->{nusers} . "\n";
            }
        }

        if( exists( $json->{blockdevices} )) {
            $out .= "Disks:\n";
            foreach my $blockDevice ( @{$json->{blockdevices}} ) {
                $out .= "    " . $blockDevice->{name} . "\n";
                foreach my $att ( sort keys %$blockDevice ) {
                    my $val = $blockDevice->{$att};
                    if( _printDiskAtt( $att, $val, $showDetail )) {
                        $out .= "        $att: $val\n";
                    }
                    if( $att eq 'fsuse%' && defined( $val )) {
                        my $numVal = $val;
                        $numVal =~ s!%!!;
                        if( $numVal > $PROBLEM_DISK_PERCENT ) {
                            push @problems, 'Disk ' . $blockDevice->{name} . ' is almost full: ' . $val;
                        }
                    }
                }
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
        if( exists( $json->{memory} )) {
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

        if( exists( $json->{pacnew} )) {
            $out .= "Pacnew:\n";

            if( $showDetail ) {
                $out .= "    Changed config files:\n";
                $out .= join( '', map( "        $_\n", @{$json->{pacnew}} ));
            } else {
                $out .= "    Number of changed config files: " . ( 0 + @{$json->{pacnew}} ) . "\n";
            }
        }

        if( @problems ) {
            colPrintWarning( "\nProblems:\n" . join( "", map { "    * $_\n" } @problems ) . "\n" );
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
    if( 'btrfs' eq $fstype ) {
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
    [--disks] [--lastupdated] [--memory] [--pacnew] [--uptime]
SSS
    If any of the optional arguments are given, only report on the
    specified subjects:
    * disks:       report on attached disks and their usage.
    * lastupdated: report when the device was last updated
    * memory:      report how much RAM and swap memory is being used.
    * pacnew:      report on manually modified configuration files.
    * uptime:      report how long the device has been up since last boot.
HHH
            <<SSS => <<HHH
    --all
SSS
    Report on all subjects
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--json' => <<HHH,
    Use JSON as the output format, instead of human-readable text.
HHH
            '--detail' => <<HHH,
    Show all detail. Must not be used together with --json.
HHH
        }
    };
}

1;
