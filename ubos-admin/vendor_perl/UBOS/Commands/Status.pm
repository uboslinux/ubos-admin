#!/usr/bin/perl
#
# Command that determines and prints the current state of the device.
#
# This file is part of ubos-admin.
# (C) 2012-2015 Indie Computing Corp.
#
# ubos-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Commands::Status;

use Cwd;
use Getopt::Long qw( GetOptionsFromArray );
use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils;

##
# Execute this command.
# return: desired exit code
sub run {
    my @args = @_;

    if ( $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $showJson      = 0;
    my $showAll       = 0;
    my $showPacnew    = 0;
    my $showDisks     = 0;
    my $showMemory    = 0;
    my $showUptime    = 0;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'     => \$verbose,
            'logConfig=s'  => \$logConfigFile,
            'json'         => \$showJson,
            'all'          => \$showAll,
            'pacnew'       => \$showPacnew,
            'disks'        => \$showDisks,
            'memory'       => \$showMemory,
            'uptime'       => \$showUptime );

    UBOS::Logging::initialize( 'ubos-admin', 'status', $verbose, $logConfigFile );

    if( !$parseOk || ( $showAll && ($showPacnew || $showDisks || $showMemory || $showUptime )) || @args || ( $verbose && $logConfigFile )) {
        fatal( 'Invalid invocation: status', @_, '(add --help for help)' );
    }
    if( $showAll ) {
        $showPacnew = 1;
        $showDisks  = 1;

    } elsif( !$showPacnew && !$showDisks && !$showMemory && !$showUptime ) {
        # default
        $showDisks  = 1;
        $showMemory = 1;
        $showUptime = 1;
    }

    my $json = $showJson ? {} : undef;

    if( $showDisks ) {
        debug( 'Checking disks' );

        my $out;
        UBOS::Utils::myexec( "lsblk --json --output-all --paths", undef, \$out );
        if( $out ) {
            my $newJson = UBOS::Utils::readJsonFromString( $out );
            if( $json ) {
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

            } else {
                my $msg = <<MSG;
disks:
MSG
                foreach my $blockdevice ( @{$newJson->{blockdevices}} ) {
                    my $name       = $blockdevice->{name};
                    my $fstype     = $blockdevice->{fstype};
                    my $mountpoint = $blockdevice->{mountpoint};

                    $msg .= "    $name";
                    if( $fstype ) {
                        $msg .= ", fstype $fstype";
                        $msg .= ", used " . _usageAsText( $name, $fstype, $mountpoint );
                    }
                    if( $mountpoint ) {
                        $msg .= ", mounted at $mountpoint";
                    } else {
                        $msg .= ", not mounted";
                    }
                    $msg .= "\n";

                    foreach my $child ( @{$blockdevice->{children}} ) {
                        my $childName       = $child->{name};
                        my $childFstype     = $child->{fstype};
                        my $childMountpoint = $child->{mountpoint};

                        $msg .= "    $childName";
                        if( $childFstype ) {
                            $msg .= ", fstype $childFstype";
                            $msg .= ", " . _usageAsText( $childName, $childFstype, $childMountpoint );

                            if( $childMountpoint ) {
                                $msg .= ", mounted at $childMountpoint";
                            } else {
                                $msg .= ", not mounted";
                            }
                        } else {
                            $msg .= ", no filesystem";
                        }
                        $msg .= "\n";
                    }
                }
                print $msg;
            }
        }
    }

    if( $showMemory ) {
        debug( 'Checking memory' );

        my $out;
        UBOS::Utils::myexec( "free -lht", undef, \$out );

        if( $json ) {
            $json->{memory} = {};

            my @lines = split /\n/, $out;
            my $header = shift @lines;
            $header =~ s!^\s+!!;
            $header =~ s!\s+$!!;
            my @headerFields = split /\s+/, $header;
            foreach my $line ( @lines ) {
                $line =~ s!^\s+!!;
                $line =~ s!\s+$!!;
                my @fields = split /\s+/, $line;
                my $key    = shift @fields;
                my $max    = @headerFields;
                if( $max > @fields ) {
                    $max = @fields;
                }
                for( my $i=0 ; $i<$max ; ++$i ) {
                    $json->{memory}->{$key}->{$headerFields[$i]} = $fields[$i];
                }
            }
        } else {
            my $msg = <<MSG;
memory:
MSG
            $out =~ s!^\s+!!;
            $out =~ s!\s+$!!;
            $out =~ s!\n!\n    !g;
            $msg .= '    ' . $out . "\n";
            print( $msg );
        }
    }

    if( $showUptime ) {
        debug( 'Checking uptime' );

        my $out;
        UBOS::Utils::myexec( "w -f -u", undef, \$out );

        if( $json ) {
            $json->{uptime} = {};
            $json->{uptime}->{users} = [];

            my @lines = split /\n/, $out;
            my $first = shift @lines;

            if( $first =~ m!^\s*(\d+:\d+:\d+)\s*up\s*([^,]+),\s*(\d+)\s*users,\s*load\s*average:\s*([^,]+),\s*([^,]+),\s*([^,]+)\s*$! ) {
                $json->{uptime}->{time}      = $1;
                $json->{uptime}->{uptime}    = $2;
                $json->{uptime}->{nusers}    = $3;
                $json->{uptime}->{loadavg1}  = $4;
                $json->{uptime}->{loadavg5}  = $5;
                $json->{uptime}->{loadavg15} = $6;
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

        } else {
            my $msg = <<MSG;
uptime:
MSG
            $out =~ s!^\s+!!;
            $out =~ s!\s+$!!;
            $out =~ s!\n!\n    !g;
            $msg .= '    ' . $out . "\n";
            print( $msg );
        }
    }

    if( $showPacnew ) {
        debug( 'Looking for .pacnew files' );

        my $out;
        UBOS::Utils::myexec( "find /boot /etc /usr -name '*.pacnew' -print", undef, \$out );

        if( $out ) {
            my @items = split /\n/, $out;
            if( $json ) {
                $json->{pacnew} = \@items;
            } else {
                my $count = scalar @items;
                my $msg = <<MSG;
pacnew:
    Explanation: You manually modified $count configuration file(s) that need an
        upgrade. Because you modified them, UBOS cannot automatically upgrade
        them. Instead, the new versions were saved next to the modified files
        with the extension .pacnew. Please review them, one by one, update them,
        and when you are done, remove the version with the .pacnew extension.
        Here's the list:
MSG
                $msg .= '    ' . join( "\n    ", @items ) . "\n";
                print( $msg );
            }
        }
    }

    if( keys %$json ) {
        UBOS::Utils::writeJsonToStdout( $json );
    }
    return 1;
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
# Helper method to determine the disk usage of a partition
# $device: the device, e.g. /dev/sda1
# $fstype: the file system type, e.g. btrfs
# $mountpoint: the mount point, e.g. /var
# return: a string showing usage
sub _usageAsText {
    my $device     = shift;
    my $fstype     = shift;
    my $mountpoint = shift;

    if( 'btrfs' eq $fstype ) {
        my $out;
        UBOS::Utils::myexec( "btrfs filesystem df -h '$mountpoint'", undef, \$out );
        $out =~ s/\n/; /g;
        return $out;

    } else {
        my $out;
        UBOS::Utils::myexec( "df -h '$device' --output=used,size,pcent", undef, \$out );
        my @lines = split( "\n", $out );
        my $data  = pop @lines;
        $data =~ s!^\s+!!;
        $data =~ s!\s+$!!;
        my ( $used, $size, $pcent ) = split( /\s+/, $data );
        return "used $used of $size ($pcent)";
    }
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [ --json ]
SSS
    Show the status of the device in default format
    --json: show it in JSON format
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [ --json ] --all
SSS
    Show the full status of the device.
    --json: show it in JSON format
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [ --json ] --pacnew
SSS
    Show the modified configuration files on the device that UBOS
    cannot continue to upgrade.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [ --json ] --disks
SSS
    Show the attached disks and their usage.
HHH
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [ --json ] --memory
SSS
    Show memory usage.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [ --json ] --uptime
SSS
    Show how long the system has been up
HHH
    };
}

1;
