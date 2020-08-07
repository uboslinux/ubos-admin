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
use UBOS::Logging;
use UBOS::Terminal;
use UBOS::Utils;

# report on those disk fields
my %defaultDiskFields = ();
map { $defaultDiskFields{$_} = 1; } qw (
    size
    mountpoint
    fsuse%
    fssize
    type
    smart_status_passed
);

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
    my $showPublicKey   = 0;
    my $showReady       = 0;
    my $showSmart       = 0;
    my $showSnapper     = 0;
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
            'publickey'      => \$showPublicKey,
            'ready'          => \$showReady,
            'smart'          => \$showSmart,
            'snapper'        => \$showSnapper,
            'virtualization' => \$showVirt,
            'uptime'         => \$showUptime );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    my $showAspect =    $showArch     || $showChannel || $showCpu
                     || $showDisks    || $showFailed  || $showLastUpdated
                     || $showLive     || $showMemory  || $showPacnew
                     || $showProblems || $showProduct || $showPublicKey
                     || $showReady    || $showSmart   || $showSnapper
                     || $showVirt     || $showUptime;

    if(    !$parseOk
        || ( $showAll  && $showAspect )
        || ( $showJson && ( $showAll || $showAspect ))
        || @args
        || ( $verbose && $logConfigFile ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $showSmart && UBOS::HostStatus::virtualization()) {
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
        $showSmart       = !UBOS::HostStatus::virtualization(),
        $showSnapper     = 1;
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
        $showSmart       = !UBOS::HostStatus::virtualization();
        $showUptime      = 1;
    }

    my $ret = 1;

    if( $showJson ) {
        UBOS::Utils::writeJsonToStdout( UBOS::HostStatus::allAsJson() );

    } else {
        # will print to console
        my $out  = 'Host: ' . UBOS::HostStatus::hostId() . "\n";
        $out .= '=' x ( length( $out )-1 ) . "\n";

        colPrint( $out );

        $out = ''; # reset $out

        if( $showProduct ) {
            my $productJson = UBOS::HostStatus::productJson();

            $out .= "Product:\n";
            if( exists( $productJson->{name} )) {
                $out .= '    Name:           ' . $productJson->{name} . "\n";
            } else {
                $out .= '    Name:           ' . '?' . "\n";
            }
            if( exists( $productJson->{vendor} )) {
                $out .= '    Vendor:         ' . $productJson->{vendor} . "\n";
            }
            if( exists( $productJson->{sku} )) {
                $out .= '    SKU:            ' . $productJson->{sku} . "\n";
            }
        }
        if( $showLive ) {
            my $liveJson = UBOS::HostStatus::liveJson();

            $out .= "UBOS Live:\n";
            if( exists( $liveJson->{installed} )) {
                $out .= '    Installed:      ' . ( $liveJson->{installed} ? 'yes' : 'no' ) . "\n";
            } else {
                $out .= '    Installed:      ' . '?' . "\n";
            }
            if( exists( $liveJson->{active} )) {
                $out .= '    Active:         ' . ( $liveJson->{active} ? 'yes' : 'no' ) . "\n";
            } else {
                $out .= '    Active:         ' . '?' . "\n";
            }
        }
        if( $showArch ) {
            my $arch        = UBOS::HostStatus::arch();
            my $deviceClass = UBOS::HostStatus::deviceClass();
            if( $arch ) {
                $out .= 'Arch:               ' . $arch . "\n";
            }
            if( $deviceClass ) {
                $out .= 'Device class:       ' . $deviceClass . "\n";
            }
        }
        if( $showVirt ) {
            my $virtualization = UBOS::HostStatus::virtualization();
            if( $virtualization ) {
                $out .= 'Virtualization:     ' . $virtualization. "\n";
            } else {
                $out .= 'Virtualization:     ' . 'None' . "\n";
            }
        }

        if( $showReady ) {
            $out .= "Ready:\n";
            my $readySince = UBOS::HostStatus::readySince();
            if( $readySince ) {
                $out .= '    since:          ' . _formatTimeStamp( $readySince ) . "\n";
            } else {
                $out .= "    NOT READY\n";
            }
        }

        if( $showLastUpdated ) {
            my $lastUpdated = UBOS::HostStatus::lastUpdated();
            if( $lastUpdated ) {
                $out .= 'Last updated:       ' . _formatTimeStamp( $lastUpdated ) . "\n";
            } else {
                $out .= 'Last updated:       ' . 'Never' . "\n";
            }
        }

        if( $showChannel ) {
            $out .= 'Channel:            ' . UBOS::HostStatus::channel() . "\n";
        }

        if( $showCpu ) {
            my $cpuJson = UBOS::HostStatus::cpuJson();
            $out .= "CPU:\n";
            $out .= '    number:         ' . $cpuJson->{ncpu} . "\n";
            if( exists( $cpuJson->{virttype} )) {
                $out .= '    virtualization: ' . $cpuJson->{virttype} . "\n";
            }
        }

        if( $showUptime ) {
            my $uptimeJson = UBOS::HostStatus::uptimeJson();
            $out .= "Uptime:\n";
            $out .= '    for:            ' . $uptimeJson->{uptime} . "\n";
            $out .= '    load avg:       ' . $uptimeJson->{loadavg1}  . ' (1 min) '
                                           . $uptimeJson->{loadavg5}  . ' (5 min) '
                                           . $uptimeJson->{loadavg15} . " (15 min)\n";

            if( $showDetail ) {
                $out .= '    users:    ' .  $uptimeJson->{nusers} . "\n";
            }
        }

        if( $showPublicKey ) {
            $out .= "Host public key:\n";
            $out .= UBOS::HostStatus::hostPublicKey() . "\n";
        }

        if( $showDisks || $showSmart ) {
            $out .= "Disks:\n";
            my $blockDevicesJson = UBOS::HostStatus::blockDevicesJson();

            foreach my $blockDevice ( @$blockDevicesJson ) {
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

        if( $showSnapper ) {
            $out .= "Snapper configurations:\n";
            my $snapperJson = UBOS::HostStatus::snapperJson();
            if( $snapperJson && keys %$snapperJson > 0 ) {
                foreach my $configName ( sort keys %$snapperJson ) {
                    $out .= "    $configName\n";
                    foreach my $snapData ( @{$snapperJson->{$configName}} ) {
                        # we assume they are sorted already

                        $out .= sprintf( '        %3d | %6s', $snapData->{number}, $snapData->{type} );

                        if( defined( $snapData->{'pre-number'} )) {
                            $out .= sprintf( ' | %3d', $snapData->{number} );
                        } else {
                            $out .= ' |    ';
                        }
                        $out .= sprintf( ' | %19s', $snapData->{date} );
                        if( defined( $snapData->{'cleanup'} )) {
                            $out .= sprintf( ' | %8s', $snapData->{cleanup} );
                        } else {
                            $out .= ' |         ';
                        }
                        $out .= "\n";
                    }
                }

            } else {
                $out .= "    None\n";
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
            my $memoryJson = UBOS::HostStatus::memoryJson();

            foreach my $memcat ( @memcats ) {
                my $mem = $memoryJson->{$memcat};
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
            my $failedServices = UBOS::HostStatus::failedServices();

            $out .= "Failed system services:\n";
            if( @$failedServices ) {
                foreach my $service ( @$failedServices ) {
                    $out .= "    $service\n";
                }
                $ret = 0;

            } else {
                $out .= "    None\n";
            }
        }

        if( $showPacnew ) {
            my $pacnewFiles = UBOS::HostStatus::pacnewFiles();

            $out .= "Changed config files (.pacnew):\n";
            if( @$pacnewFiles ) {
                if( $showDetail ) {
                    $out .= join( '', map( "        $_\n", @$pacnewFiles ));
                } else {
                    $out .= "    " . ( 0 + @$pacnewFiles ) . "\n";
                }
            } else {
                $out .= "    None\n";
            }
        }

        if( $showProblems ) {
            my $problems = UBOS::HostStatus::problems();

            unless( $showFailed ) {
                # don't report twice
                push @$problems, map { 'System service ' . $_ . ' has failed.' } @{UBOS::HostStatus::failedServices()};
            }

            $out .= "Problems:\n";
            if( @$problems ) {
                $out .= join( "", map { "    * $_\n" } @$problems ) . "\n";
                $ret = 0;
            } else {
                $out .= "    None\n";
            }
        }

        colPrint( $out );
    }

    return $ret;
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
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Report on the status of this device.
SSS
        'cmds' => {
            <<SSS => <<HHH,
    [--arch] [--channel] [--cpu] [--disks] [--failed] [--lastupdated] [--live] [--memory] [--pacnew] [--problems] [--product] [--publickey] [--ready] [--smart] [--uptime] [--virtualization]
SSS
    If any of the optional arguments are given, only report on the
    specified subjects:
    * arch:           arch and device class
    * channel:        UBOS release channel used by this device
    * cpu:            CPUs available
    * disks:          attached disks and their usage
    * failed:         daemons that have failed
    * lastupdated:    when the device was last updated
    * live:           UBOS Live status
    * memory:         how much RAM and swap memory is being used
    * pacnew:         manually modified configuration files
    * problems:       any detected problems
    * product:        product identifier
    * publickey:      the host's public key
    * ready:          whether the device is ready or not
    * smart:          disk health via S.M.A.R.T
    * snapper:        snapper snapshots
    * uptime:         how long the device has been up since last boot
    * virtualization: use of virtualization
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
