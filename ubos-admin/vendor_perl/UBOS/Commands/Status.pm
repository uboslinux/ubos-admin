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
use UBOS::HostStatus;
use UBOS::Lock;
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

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    unless( UBOS::Lock::acquire() ) {
        colPrintError( "$@\n" );
        exit -2;
    }

    my $verbose         = 0;
    my $logConfigFile   = undef;
    my $debug           = undef;
    my $showJson        = 0;
    my $showAll         = 0;
    my $showArch        = 0;
    my $showDetail      = 0;
    my $showChannel     = 0;
    my $showCpu         = 0;
    my $showDisks       = 0;
    my $showFailed      = 0;
    my $showLastUpdated = 0;
    my $showLive        = 0;
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
            'arch'           => \$showArch,
            'detail'         => \$showDetail,
            'channel'        => \$showChannel,
            'cpu'            => \$showCpu,
            'disks'          => \$showDisks,
            'failed'         => \$showFailed,
            'live'           => \$showLive,
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

    my $showAspect =    $showArch     || $showChannel || $showCpu
                     || $showDisks    || $showFailed  || $showLastUpdated
                     || $showLive     || $showMemory  || $showPacnew
                     || $showProblems || $showProduct || $showReady
                     || $showSmart    || $showVirt    || $showUptime;

    if(    !$parseOk
        || ( $showAll  && $showAspect )
        || ( $showJson && ( $showAll || $showAspect ))
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    my $json = UBOS::HostStatus::statusJson();

    if( $showSmart && exists( $json->{systemd_detect_virt} )) {
        fatal( 'Cannot show S.M.A.R.T. disk health in a virtualized system' );
    }

    if( $showAll ) {
        $showArch        = 1;
        $showChannel     = 1;
        $showCpu         = 1;
        $showDisks       = 1;
        $showFailed      = 1;
        $showLastUpdated = 1;
        $showLive        = 1;
        $showMemory      = 1;
        $showPacnew      = 1;
        $showProblems    = 1;
        $showProduct     = 1;
        $showReady       = 1;
        $showSmart       = !exists( $json->{systemd_detect_virt} );
        $showVirt        = 1;
        $showUptime      = 1;

    } elsif( !$showAspect ) {
        # default
        $showChannel     = 1;
        $showDisks       = 1;
        $showLastUpdated = 1;
        $showLive        = 1;
        $showMemory      = 1;
        $showProblems    = 1;
        $showProduct     = 1;
        $showReady       = 1;
        $showSmart       = !exists( $json->{systemd_detect_virt} );
        $showUptime      = 1;
    }

    unless( $showFailed ) {
        # don't report twice
        push @{$json->{problems}}, map { 'System service ' . $_ . ' has failed.' } @{$json->{failedservices}};
    }

    # now display (or not)

    unless( @{$json->{problems}} ) {
        delete $json->{problems};
    }

    if( $showJson ) {
        UBOS::Utils::writeJsonToStdout( $json );

    } else {
        # will print to console
        my $out  = 'Status: ' . $json->{hostid} . "\n";
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
        if( $showLive ) {
            $out .= "UBOS Live:\n";
            if( exists( $json->{live}->{installed} )) {
                $out .= '    Installed:      ' . ( $json->{live}->{installed} ? 'yes' : 'no' ) . "\n";
            } else {
                $out .= '    Installed:      ' . '?' . "\n";
            }
            if( exists( $json->{live}->{active} )) {
                $out .= '    Active:         ' . ( $json->{live}->{active} ? 'yes' : 'no' ) . "\n";
            } else {
                $out .= '    Active:         ' . '?' . "\n";
            }
        }
        if( $showArch ) {
            if( exists( $json->{arch} )) {
                $out .= 'Arch:               ' . $json->{arch} . "\n";
            }
            if( exists( $json->{deviceclass} )) {
                $out .= 'Device class:       ' . $json->{deviceclass} . "\n";
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

    if( $ts ) {
        if( $ts =~ m!^(\d\d\d\d)(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)! ) {
            return "$1/$2/$3 $4:$5:$6";
        } else {
            return $ts; # best we can do
        }
    } else {
        return '<never>';
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
    [--channel] [--cpu] [--disks] [--failed] [--live] [--lastupdated] [--memory] [--pacnew] [--ready] [--uptime]
SSS
    If any of the optional arguments are given, only report on the
    specified subjects:
    * channel:        report on the UBOS release channel used by this device.
    * cpu:            report on the CPUs available.
    * arch:           report on the arch and device class.
    * disks:          report on attached disks and their usage.
    * failed:         report on daemons that have failed.
    * lastupdated:    report when the device was last updated.
    * live:           report on UBOS Live status.
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
