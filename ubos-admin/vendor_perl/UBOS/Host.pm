#!/usr/bin/perl
#
# Represents the local host.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Host;

use File::Basename;
use UBOS::Apache2;
use UBOS::Logging;
use UBOS::Roles::apache2;
use UBOS::Roles::generic;
use UBOS::Roles::mysql;
use UBOS::Roles::postgresql;
use UBOS::Roles::tomcat8;
use UBOS::Site;
use UBOS::Terminal;
use UBOS::Tor;
use UBOS::Utils qw( readJsonFromFile myexec );
use UBOS::Variables;
use Socket;
use Sys::Hostname qw();

my $HOST_CONF_FILE          = '/etc/ubos/config.json';

my $SITE_JSON_DIR           = vars()->getResolve( 'host.sitejsondir' );
my $AFTER_BOOT_FILE         = vars()->getResolve( 'host.afterbootfile' );
my $READY_FILE              = '/run/ubos-admin-ready';
my $LAST_UPDATE_FILE        = '/etc/ubos/last-ubos-update'; # not /var, as /var might move from system to system
my $HOSTNAME_CALLBACKS_DIR  = '/etc/ubos/hostname-callbacks';
my $STATE_CALLBACKS_DIR     = '/etc/ubos/state-callbacks';

my $_hostVars               = undef; # allocated as needed
my $_rolesOnHostInSequence  = undef; # allocated as needed
my $_rolesOnHost            = undef; # allocated as needed
my $_sites                  = undef; # allocated as needed
my $_currentState           = undef;

##
# Obtain the Variables object for the Host.
# return: Variables object
sub vars {
    unless( $_hostVars ) {
        my $raw = readJsonFromFile( $HOST_CONF_FILE );
        unless( $raw ) {
            fatal();
        }
        my $now = UBOS::Utils::now();

        $raw->{hostname}        = Sys::Hostname::hostname;
        $raw->{now}->{unixtime} = $now;
        $raw->{now}->{tstamp}   = UBOS::Utils::time2string( $now );

        $_hostVars = UBOS::Variables->new( 'Host', $raw );
    }
    return $_hostVars;
}

##
# Determine this host's hostname.
# return: hostname
sub hostname {
    return vars()->getResolve( 'hostname' );
}

##
# Obtain the location for temporary files. This will also create the
# configured tmp directory if it does not exist yet.
# return: path
sub tmpdir {
    my $ret = vars()->getResolve( 'host.tmpdir', '/ubos/tmp' );
    unless( -d $ret ) {
        UBOS::Utils::mkdirDashP( $ret );
    }
    return $ret;
}

##
# Determine all Sites currently installed on this host.
# return: hash of siteId to Site
sub sites {
    unless( $_sites ) {
        $_sites = {};

        if( -d $SITE_JSON_DIR ) {
            my @siteJsons = ();

            if ( $< == 0 ) {
                # If we are root, we read the full files, otherwise the public files
                foreach my $f ( <"$SITE_JSON_DIR/*-full.json"> ) {
                    my $siteJson = readJsonFromFile( $f );
                    if( $siteJson ) {
                        push @siteJsons, $siteJson;
                    } else {
                        fatal();
                    }
                }
            } else {
                foreach my $f ( <"$SITE_JSON_DIR/*-world.json"> ) {
                    my $siteJson = readJsonFromFile( $f );
                    if( $siteJson ) {
                        push @siteJsons, $siteJson;
                    } else {
                        fatal();
                    }
                }
            }

            # Clean up LetsEncrypt TLS info in case we still have it
            foreach my $siteJson ( @siteJsons ) {
                if( exists( $siteJson->{tls} ) && exists( $siteJson->{tls}->{letsencrypt} ) && $siteJson->{tls}->{letsencrypt} ) {
                    delete $siteJson->{tls}->{key};
                    delete $siteJson->{tls}->{crt};
                    # not cacrt
                }
            }

            # Instantiate Site objects
            foreach my $siteJson ( @siteJsons ) {
                my $site = UBOS::Site->new( $siteJson, 0, $< > 0 ); # Skip filesystem checks for non-root -- may not have rights
                if( $site ) {
                    $_sites->{$site->siteId()} = $site;
                } else {
                    fatal( $@ );
                }
            }
        }
    }
    return $_sites;
}

##
# Find a particular Site in the provided hash, or currently installed on this host.
# $siteId: the Site identifier
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site, or undef
sub findSiteById {
    my $siteId = shift;
    my $sites  = shift || sites();

    return $sites->{$siteId};
}

##
# Find a particular Site in the provided hash, or currently installed on this host,
# by a complete or partial siteid match.
# $id: the complete or partial Site identifier
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site, or undef
sub findSiteByPartialId {
    my $id    = shift;
    my $sites = shift || sites();

    my $ret;
    if( $id =~ m!^(.*)\.\.\.$! ) {
        my $partial    = $1;
        my @candidates = ();

        foreach my $siteId ( keys %$sites ) {
            my $site = $sites->{$siteId};

            if( $siteId =~ m!^$partial! ) {
                push @candidates, $site;
            }
        }
        if( @candidates == 1 ) {
            $ret = $candidates[0];

        } elsif( @candidates ) {
            $@ = "There is more than one site whose siteid starts with $partial:\n"
               . join( '', map { $_->siteId . "\n" } @candidates );
            return undef;

        } else {
            $@ = "No site found whose siteid starts with $partial.";
            return undef;
        }

    } else {
        $ret = $sites->{$id};
        unless( $ret ) {
            $@ = "No site found with siteid $id.";
            return undef;
        }
    }
    return $ret;
}

##
# Find a particular Site in the provided hash, or currently installed on this host,
# by its hostname
# $host: hostname
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site
sub findSiteByHostname {
    my $host  = shift;
    my $sites = shift || sites();

    foreach my $siteId ( keys %$sites ) {
        my $site = $sites->{$siteId};

        if( $site->hostname eq $host ) {
            return $site;
        }
    }
    $@ = 'No Site found with hostname '. $host;
    return undef;
}

##
# Find a particular AppConfiguration in the provided hash of sites, or currently installed on this host,
# by a complete app config id match.
sub findAppConfigurationById {
    my $appConfigId = shift;
    my $sites       = shift || sites();

    foreach my $siteId ( keys %$sites ) {
        my $site       = $sites->{$siteId};
        my $appConfigs = $site->appConfigs;

        foreach my $appConfig ( @$appConfigs ) {
            if( $appConfig->appConfigId eq $appConfigId ) {
                return $appConfig;
            }
        }
    }
    return undef;
}

##
# Find a particular AppConfiguration in the provided hash of sites, or currently installed on this host,
# by a complete or partial app config id match.
# $id: the complete or partial app config identifier
# $sites: hash of siteid to Site (defaults to sites installed on host)
# return: the Site, or undef
sub findAppConfigurationByPartialId {
    my $id    = shift;
    my $sites = shift || sites();

    my $ret;
    if( $id =~ m!^(.*)\.\.\.$! ) {
        my $partial    = $1;
        my @candidates = ();

        foreach my $siteId ( keys %$sites ) {
            my $site       = $sites->{$siteId};
            my $appConfigs = $site->appConfigs;

            foreach my $appConfig ( @$appConfigs ) {
                if( $appConfig->appConfigId =~ m!^$partial! ) {
                    push @candidates, [ $appConfig, $site ];
                }
            }
        }
        if( @candidates == 1 ) {
            $ret = $candidates[0][0];

        } elsif( @candidates ) {
            $@ = "There is more than one AppConfiguration whose app config id starts with $partial:\n"
                 . join( "\n", map { $_->[0]->appConfigId() . " (site " . $_->[1]->siteId() . ")" } @candidates );
            return undef;

        } else {
            $@ = "No AppConfiguration found whose app config id starts with $partial.";
            return undef;
        }

    } else {
        foreach my $siteId ( keys %$sites ) {
            my $site = $sites->{$siteId};

            $ret = $site->appConfig( $id );

            if( $ret ) {
                last;
            }
        }
        unless( $ret ) {
            $@ = "No AppConfiguration found with app config id $id.";
            return undef;
        }
    }
    return $ret;
}

##
# Obtain the hostnames of the deployed sites
# return: hash of hostname to hostname
sub hostnamesOfSites {

    my $sites = sites();
    my $existingHostnames = {};

    foreach my $siteId ( keys %$sites ) {
        my $hostname = $sites->{$siteId}->hostname();
        $existingHostnames->{$hostname} = $hostname;
    }

    return $existingHostnames;
}

##
# A site is about to be deployed
# $site: the newly to-be deployed or updated site
sub siteDeploying {
    my $site = shift;

    trace( 'Host::siteDeploying', $site->siteId() );

    UBOS::Utils::invokeCallbacks( $HOSTNAME_CALLBACKS_DIR, 1, 'siteDeploying', $site );
}

##
# A site has been deployed.
# $site: the newly deployed or updated site
sub siteDeployed {
    my $site = shift;

    my $siteId         = $site->siteId;
    my $siteJson       = $site->siteJsonWithoutLetsEncryptCert;
    my $publicSiteJson = $site->publicSiteJson;

    trace( 'Host::siteDeployed', $siteId );

    my $now         = UBOS::Utils::now();
    my $lastUpdated = UBOS::Utils::time2string( $now );

    $siteJson->{lastupdated}       = $lastUpdated;
    $publicSiteJson->{lastupdated} = $lastUpdated;

    unless( -d $SITE_JSON_DIR ) {
        UBOS::Utils::mkdirDashP( $SITE_JSON_DIR );
    }

    UBOS::Utils::writeJsonToFile( "$SITE_JSON_DIR/$siteId-full.json",  $siteJson,       0600, 'root', 'root' );
    UBOS::Utils::writeJsonToFile( "$SITE_JSON_DIR/$siteId-world.json", $publicSiteJson, 0644, 'root', 'root' );

    UBOS::Utils::invokeCallbacks( $HOSTNAME_CALLBACKS_DIR, 1, 'siteDeployed', $site );

    $_sites = undef;
}

##
# A site is about to be undeployed
# $site: the to-be undeployed site
sub siteUndeploying {
    my $site = shift;

    trace( 'Host::siteUndeploying', $site->siteId() );

    UBOS::Utils::invokeCallbacks( $HOSTNAME_CALLBACKS_DIR, 0, 'siteUndeploying', $site );
}

##
# A site has been undeployed.
# $site: the undeployed site
sub siteUndeployed {
    my $site = shift;

    my $siteId = $site->siteId;

    trace( 'Host::siteUndeployed', $siteId );

    UBOS::Utils::deleteFile( "$SITE_JSON_DIR/$siteId-world.json" );
    UBOS::Utils::deleteFile( "$SITE_JSON_DIR/$siteId-full.json" );

    $_sites = undef; # before the callback

    UBOS::Utils::invokeCallbacks( $HOSTNAME_CALLBACKS_DIR, 0, 'siteUndeployed', $site );
}

##
# Determine the roles that this host has chosen to use and support. For now, this is
# fixed.
# return: hash of role name to Role
sub rolesOnHost {
    unless( $_rolesOnHost ) {
        my @inSequence = rolesOnHostInSequence();
        $_rolesOnHost = {};
        foreach my $role ( @inSequence ) {
            $_rolesOnHost->{ $role->name } = $role;
        }
    }
    return $_rolesOnHost;
}

##
# Determine the roles that this host has chosen to use and support, in sequence
# of installation: databases before middleware before web server.
# return: the Roles, in sequence
sub rolesOnHostInSequence {
    unless( $_rolesOnHostInSequence ) {
        $_rolesOnHostInSequence = [
                UBOS::Roles::mysql->new,
                UBOS::Roles::postgresql->new,
                UBOS::Roles::generic->new,
                UBOS::Roles::tomcat8->new,
                UBOS::Roles::apache2->new ];
    }
    return @$_rolesOnHostInSequence;
}

##
# Create a new siteid
# return: the siteid
sub createNewSiteId {
    return 's' . UBOS::Utils::randomHex( 40 );
}

##
# Create a new appconfigid
# return: the appconfigid
sub createNewAppConfigId {
    return 'a' . UBOS::Utils::randomHex( 40 );
}

##
# Determine whether this is a valid hostname
# $hostname: the hostname
# return: 1 or 0
sub isValidHostname {
    my $hostname = shift;

    if( ref( $hostname )) {
        error( 'Supposed hostname is not a string:', ref( $hostname ));
        return 0;
    }

    unless( $hostname =~ m!^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?)*\.?$|^\*$! ) {
        # regex originally from http://stackoverflow.com/a/1420225/200304
        return 0;
    }
    return 1;
}

##
# Determine whether this is a syntactically valid Site id
# $siteId: the Site id
# return: 1 or 0
sub isValidSiteId {
    my $siteId = shift;

    if( ref( $siteId )) {
        error( 'Supposed siteId is not a string:', ref( $siteId ));
        return 0;
    }
    if( $siteId =~ m/^s[0-9a-f]{40}$/ ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine whether this is a syntactically valid AppConfiguration id
# $appConfigId: the AppConfiguration id
# return: 1 or 0
sub isValidAppConfigId {
    my $appConfigId = shift;

    if( ref( $appConfigId )) {
        error( 'Supposed appConfigId is not a string:', ref( $appConfigId ));
        return 0;
    }
    if( $appConfigId =~ m/^a[0-9a-f]{40}$/ ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Execute the named triggers
# $triggers: array of trigger names
sub executeTriggers {
    my $triggers = shift;

    my @triggerList;
    if( ref( $triggers ) eq 'HASH' ) {
        @triggerList = keys %$triggers;
    } elsif( ref( $triggers ) eq 'ARRAY' ) {
        @triggerList = @$triggers;
    } else {
        fatal( 'Unexpected type:', $triggers );
    }

    # if we do restart, don't also do a reload
    foreach my $s ( 'httpd', 'tomcat8', 'tor' ) {
        if( grep { m!^$s-restart@! } @triggerList ) {
            @triggerList = grep { ! m!$s-reload$! } @triggerList;
        }
    }

    trace( 'Host::executeTriggers:', @triggerList );

    foreach my $trigger ( @triggerList ) {
        if( 'httpd-reload' eq $trigger ) {
            UBOS::Apache2::reload();
        } elsif( 'httpd-restart' eq $trigger ) {
            UBOS::Apache2::restart();
        } elsif( 'tomcat8-reload' eq $trigger ) {
            UBOS::Tomcat8::reload();
        } elsif( 'tomcat8-restart' eq $trigger ) {
            UBOS::Tomcat8::restart();
        } elsif( 'tor-reload' eq $trigger ) {
            UBOS::Tor::reload();
        } elsif( 'tor-restart' eq $trigger ) {
            UBOS::Tor::restart();
        } else {
            warning( 'Unknown trigger:', $trigger );
        }
    }
}

##
# Set the system state
# $newState: name of the new state
# return: number of errors
sub setState {
    my $newState = shift;

    my %permittedStates = (
        'Operational'   => 'operational',
        'InMaintenance' => 'in maintenance',
        'ShuttingDown'  => 'shutting down',
        'Rebooting'     => 'rebooting',
        'Error'         => 'error'
    );
    unless( $permittedStates{$newState} ) {
        error( 'Unknown UBOS state:', $newState );
        return 1;
    }
    info( 'Setting device state to:', $permittedStates{$newState} );

    $_currentState = $newState;

    my $ret = UBOS::Utils::invokeCallbacks( $STATE_CALLBACKS_DIR, 1, 'stateChanged', $newState );
    return $ret;
}

##
# Update all the code currently installed on this host.
# $syncFirst: if true, perform a pacman -Sy; otherwise only a pacman -Su
# $showPackages: if true, show the package files that were installed
# return: if -1, reboot
sub updateCode {
    my $syncFirst    = shift;
    my $showPackages = shift;

    trace( 'Host::updateCode', $syncFirst, $showPackages );

    my $ret = 0;
    my $cmd;
    if( -x '/usr/bin/pacman-db-upgrade' ) {
        $cmd = 'pacman-db-upgrade';
        unless( UBOS::Logging::isTraceActive() ) {
            $cmd .= ' > /dev/null';
        }
        debugAndSuspend( 'Execute pacman-db-upgrade' );
        myexec( $cmd );
    }

    my $out;
    if( myexec( 'pacman-key --list-keys | grep expired', undef, \$out, \$out ) == 0 ) {
        # at least one key is expired

        info( 'Refreshing keys' );

        if( myexec( 'pacman-key --refresh-keys', undef, \$out, \$out )) {
            warning( 'Failed to refresh some expired keys' );
            trace( $out );
        }
    }

    info( 'Updating code' );

    if( $syncFirst ) {
        $cmd = 'pacman -Sy --noconfirm';
        debugAndSuspend( 'Execute pacman -Sy' );
        if( myexec( $cmd, undef, \$out, \$out ) != 0 ) {
            error( 'Command failed:', $cmd, "\n$out" );

        } elsif( UBOS::Logging::isTraceActive() ) {
            colPrint( $out );
        }
    }

    # ubos-admin and the key packages come first
    my @firstUpgraded = ();
    foreach my $pack ( 'archlinux-keyring', 'archlinuxarm-keyring', 'ec2-keyring', 'ubos-admin' ) {
        debugAndSuspend( 'Execute pacman -S ', $pack );
        if( myexec( "pacman -Q $pack 2> /dev/null && pacman -S $pack --noconfirm || true", undef, \$out, \$out ) != 0 ) {
            error( 'Checking/upgrading package failed:', $pack, "\n$out" );
        } elsif( UBOS::Logging::isTraceActive() ) {
            colPrint( $out );
        }
        if( $out ) {
            if( $out !~ m!warning.*reinstalling!i ) {
                push @firstUpgraded, $pack;
            } elsif( $out =~ m!conflict.*Remove!i ) {
                if( myexec( "yes y | pacman -S $pack || true", undef, \$out, \$out ) != 0 ) {
                    error( 'Checking/upgrading package with conflict failed:', $pack, "\n$out" );
                }
            }
        }
    }

    $cmd = 'pacman -Su --noconfirm';
    debugAndSuspend( 'Execute pacman -Su' );
    if( myexec( $cmd, undef, \$out, \$out ) != 0 ) {
        error( 'Command failed:', $cmd, "\n$out" );

    } elsif( UBOS::Logging::isTraceActive() ) {
        colPrint( $out );
    }

    if( $showPackages ) {
        my @lines     = split /\n/, $out;
        my @installed = map { my $s = $_; $s =~ s!^.*installing\s+!!; $s =~ s!\.\.\.\s*!!; $s; } grep /^installing /, @lines;
        my @upgraded  = map { my $s = $_; $s =~ s!^.*upgrading\s+!!;  $s =~ s!\.\.\.\s*!!; $s; } grep /^upgrading / , @lines;

        if( @installed ) {
            colPrint( 'Packages installed: ' . join( ' ', @installed ) . "\n" );
        }
        if( @firstUpgraded || @upgraded ) {
            colPrint( 'Packages upgraded: ' . join( ' ', @firstUpgraded, @upgraded ) . "\n" );
        }
        if( scalar( @firstUpgraded ) + scalar( @installed ) + scalar( @upgraded ) == 0 ) {
            colPrint( "No packages installed or upgraded.\n" );
        }
    }

    if( -x '/usr/bin/pacman-db-upgrade' ) {
        $cmd = 'pacman-db-upgrade';
        unless( UBOS::Logging::isTraceActive() ) {
            $cmd .= ' > /dev/null';
        }
        debugAndSuspend( 'Execute pacman-db-upgrade' );
        myexec( $cmd );
    }

    UBOS::Utils::saveFile( $LAST_UPDATE_FILE, UBOS::Utils::time2string( time() ) . "\n", 0644, 'root', 'root' );

    # if installed kernel package is now different from running kernel: signal to reboot
    my $kernelPackageName = UBOS::Utils::kernelPackageName(); # e.g. 4.20.arch1-1
    if( $kernelPackageName ) { # This will be undef in a container, so a container will never reboot automatically
        my $kernelPackageVersion = packageVersion( $kernelPackageName );
        if( $kernelPackageVersion ) {
            my $kernelVersion;
            myexec( 'uname -r', undef, \$kernelVersion ); # e.g. 4.20.0-arch1-1-ARCH
            $kernelVersion =~ s!^\s+!!;
            $kernelVersion =~ s!\s+$!!;
            $kernelVersion =~ s!-arch!.arch!; # they don't agree on . vs -
                # now we are at: 4.20.0.arch1-1-ARCH
            $kernelVersion =~ s!-ARCH$!!;     # somehow there's a -ARCH at the end
                # now we are at: 4.20.0.arch1-1
            $kernelVersion =~ s!\.0\.arch!.arch!; # take .0 out as package version does not use it (special case: 0)
                # now we are at: 4.20.arch1-1

            if( $kernelPackageVersion ne $kernelVersion && "$kernelPackageVersion-ec2" ne $kernelVersion ) {
                # apparently the EC2 kernel version has a trailing -ec2
                # reboot necessary
                $ret = -1;
            }
        }
    }
    return $ret;
}

##
# Clean package cache
sub purgeCache {

    my $cmd = 'pacman -Sc --noconfirm';
    unless( UBOS::Logging::isTraceActive() ) {
        $cmd .= ' > /dev/null';
    }
    debugAndSuspend( 'Execute pacman -Sc' );

    my $out;
    if( myexec( $cmd, undef, \$out, \$out )) {
        error( $out );
    }
}

##
# Make sure the named packages are installed
# $packages: List or hash of packages
# $quiet: if false, and an actual download needs to be performed, print progress message
# return: number of actually installed packagesm or negative number if error
sub ensurePackages {
    my $packages = shift;
    my $quiet    = shift;

    unless( defined( $quiet )) {
        $quiet = 1;
    }
    my @packageList;
    if( ref( $packages ) eq 'HASH' ) {
        @packageList = keys %$packages;
    } elsif( ref( $packages ) eq 'ARRAY' ) {
        @packageList = @$packages;
    } elsif( ref( $packages )) {
        fatal( 'Unexpected type:', $packages );
    } elsif( defined( $packages )) {
        @packageList = ( $packages );
    } else {
        @packageList = ();
    }

    trace( 'ensurePackages', @packageList );

    # only install what isn't installed yet
    my @filteredPackageList = grep { myexec( "pacman -Q $_ > /dev/null 2>&1" ) } @packageList;

    if( @filteredPackageList ) {
        unless( $quiet ) {
            colPrint( "Downloading packages...\n" );
        }
        my $out;
        my $cmd = 'pacman -S --noconfirm ' . join( ' ', @filteredPackageList );
        unless( UBOS::Logging::isTraceActive() ) {
            $cmd .= ' > /dev/null';
        }
        if ( $< != 0 ) {
            $cmd = 'sudo ' . $cmd;
        }

        debugAndSuspend( 'Execute pacman -S', @filteredPackageList );
        if( myexec( $cmd, undef, \$out, \$out )) {
            $@ = 'Failed to install package(s): ' . join( ' ', @filteredPackageList ) . '. Pacman says: ' . $out;
            if( $out =~ m!conflict.*Remove!i ) {
                $cmd = 'yes y | ' . $cmd;

                if( myexec( $cmd, undef, \$out, \$out )) {
                    $@ = 'Failed to install package(s) with conflict. Pacman says: ' . $out;
                }
            }
            return -1;
        }
    }
    if( @filteredPackageList ) {
        my $cmd = 'systemd-sysusers';
        my $out;
        if( myexec( $cmd, undef, \$out, \$out )) {
            error( 'Command failed:', $cmd, $out );
        }
    }
    return 0 + @filteredPackageList;
}

##
# Install the provided package files
# $packageFiles: List of package files
# $showPackages: if true, show the package files that were installed
# return: number of installed packages
sub installPackageFiles {
    my $packageFiles = shift;
    my $showPackages = shift;

    info( 'Installing packages' );

    my $out;
    my $cmd = 'pacman -U --noconfirm ' . join( ' ', @$packageFiles );
    unless( UBOS::Logging::isTraceActive() ) {
        $cmd .= ' > /dev/null';
    }

    debugAndSuspend( 'Execute pacman -U', @$packageFiles );
    if( myexec( $cmd, undef, \$out, \$out )) {
        error( 'Failed to install package file(s). Pacman says:', $out );
        return 0;
    }
    if( $showPackages ) {
        if( @$packageFiles ) {
            colPrint( 'Packages installed: ' . join( ' ', @$packageFiles ) . "\n" );
        } else {
            colPrint( "No packages installed.\n" );
        }
    }
    return 0 + ( @$packageFiles );
}

##
# Determine the version of an installed package
# $packageName: name of the package
# return: version of the package, or undef
sub packageVersion {
    my $packageName = shift;

    my $cmd = "pacman -Q '$packageName'";
    my $out;
    my $err;
    if( myexec( $cmd, undef, \$out, \$err )) {
        return undef;
    }
    if( $out =~ m!$packageName\s+(\S+)! ) {
        return $1;
    } else {
        error( 'Cannot parse pacman -Q output:', $out );
        return undef;
    }
}

##
# Ensure that snapper is configured. Called during package install only.
#
# return: number of errors
sub ensureSnapperConfig {

    my @targets = _findBtrfsFilesystems();

    my $virt;
    my $err;
    debugAndSuspend( 'Detect virtualization' );
    myexec( 'systemd-detect-virt', undef, \$virt, \$err ); # ignore status code

    $virt =~ s!^\s+!!;
    $virt =~ s!\s+$!!;

    my %snapperSnapshotsOn = ();
    my %snapperQuotaOn      = ();
    map { $snapperSnapshotsOn{$_} = $_; } split( /[,\s]+/, vars()->getResolve( 'host.snappersnapshotson', 'none,xen' ));
    map { $snapperQuotaOn{$_}     = $_; } split( /[,\s]+/, vars()->getResolve( 'host.snapperquotaon',     'none,xen' ));
    # By default, we create snapshots on real hardware and on Xen (Amazon)

    my $errors = 0;
    if( $snapperSnapshotsOn{$virt} ) {
        foreach my $target ( @targets ) {
            my $configName = $target;
            $configName =~ s!/!!g;
            unless( $configName ) {
                $configName = 'root';
            }

            unless( -e "/etc/snapper/configs/$configName" ) {
                debugAndSuspend( 'Execute snapper --config', $configName, 'create-config' );
                if( myexec( "snapper --config '$configName' create-config --template ubos-default '$target'", undef, \$err, \$err )) {
                    error( 'snapper (create-config) failed for config', $configName, $target, $err );
                    ++$errors;
                }
            }
        }

        if( $snapperQuotaOn{$virt} ) {
            debugAndSuspend( 'Execute snapper setup-quota' );

            foreach my $target ( @targets ) {
                my $configName = $target;
                $configName =~ s!/!!g;
                unless( $configName ) {
                    $configName = 'root';
                }

                unless( -e "/etc/snapper/configs/$configName" ) {
                    if( myexec( "snapper --config '$configName' setup-quota", undef, \$err, \$err ) && $err !~ /qgroup already set/ ) {
                        error( "snapper --config '$configName' setup-quota failed:", $err );
                        ++$errors;
                    }
                }
            }
        }
    } else {
        trace( 'Skipping snapper setup:', $virt );
    }

    return $errors;
}

##
# Create a "pre" filesystem snapshot
# return: string to be passed into postSnapshot to perform the corresponding "post" snapshot
sub preSnapshot {

    my @targets = _findBtrfsFilesystems();
    my $ret     = '';
    my $cleanupAlgorithm = vars()->getResolve( 'host.snappercleanupalgorithm', 'timeline' );

    my $sep = '';
    foreach my $target ( @targets ) {
        my $configName = $target;
        $configName =~ s!/!!g;
        unless( $configName ) {
            $configName = 'root';
        }

        if( -e "/etc/snapper/configs/$configName" ) {
            my $cmd  = "snapper --config '$configName'";
            $cmd    .= " create --type pre --print-number";
            $cmd    .= " --cleanup-algorithm '$cleanupAlgorithm'";

            my $snapNumber;
            my $err;
            if( myexec( $cmd, undef, \$snapNumber, \$err )) {
                if( $err =~ m!Unknown config! ) {
                    warning( 'snapper (pre) failed of config', $configName, ':', $err );
                } else {
                    error( 'snapper (pre) failed of config', $configName, ':', $err );
                }
            } else {
                $snapNumber =~ s!^\s+!!;
                $snapNumber =~ s!\s+$!!;
                $ret .= "$sep$target=$snapNumber";
                $sep = ',';
            }
        }
    }
    if( $ret ) {
        return $ret;
    } else {
        return undef;
    }
}

##
# Create a "post" filesystem snapshot
# $preInfo: the return value of preSnapshot from the corresponding "pre" snapshot
sub postSnapshot {
    my $preInfo = shift;

    my $cleanupAlgorithm = vars()->getResolve( 'host.snappercleanupalgorithm', 'timeline' );

    foreach my $item ( split ",", $preInfo ) {
        if( $item =~ m!^(.+)=(\d+)$! ) {
            my $target     = $1;
            my $snapNumber = $2;

            my $configName = $target;
            $configName =~ s!/!!g;
            unless( $configName ) {
                $configName = 'root';
            }

            if( -e "/etc/snapper/configs/$configName" ) {
                my $cmd  = "snapper --config '$configName'";
                $cmd    .= " create --type post --pre-number '$snapNumber'";
                $cmd    .= " --cleanup-algorithm '$cleanupAlgorithm'";

                my $out;
                if( myexec( $cmd, undef, \$out, \$out )) {
                    error( 'snapper (post) failed of config', $configName, ', number', $snapNumber, $out );
                }
            }
        }
    }
}

##
# Determine the btrfs filesystems
# return: array of mount points
sub _findBtrfsFilesystems() {

    my $out;
    if( myexec( "findmnt --json --types btrfs", undef, \$out, \$out )) {
        error( "findmnt failed:", $out );
        return undef;
    }
    my $json = UBOS::Utils::readJsonFromString( $out );

    # {
    #    "filesystems": [
    #       {"target": "/", "source": "/dev/sda2", "fstype": "btrfs", "options": "rw,relatime,space_cache,subvolid=5,subvol=/",
    #          "children": [
    #             {"target": "/home", "source": "/dev/sdb", "fstype": "btrfs", "options": "rw,relatime,space_cache,subvolid=5,subvol=/",
    #                "children": [
    #                   {"target": "/tmp/foo", "source": "/dev/loop0", "fstype": "btrfs", "options": "rw,relatime,space_cache,subvolid=5,subvol=/"}
    #                ]
    #             }
    #          ]
    #       }
    #    ]
    # }

    my @ret = ();
    if( exists( $json->{filesystems} )) {
        foreach my $fs ( @{$json->{filesystems}} ) {
            push @ret, _parseFindMntJson( $fs );
        }
    }
    return @ret;
}

##
# Recursive parsing of findmnt JSON
# $json the JSON fragment
# return: the found mount points
##
sub _parseFindMntJson {
    my $json = shift;

    my @ret = ();
    if( exists( $json->{target} )) {
        push @ret, $json->{target};
    }
    if( exists( $json->{children} )) {
        foreach my $child ( @{$json->{children}} ) {
            push @ret, _parseFindMntJson( $child );
        }
    }
    return @ret;
}

my $dbTypes           = {}; # cache
my $dbDriverInstances = {}; # cache: maps short-name to host:port to instance of driver

##
# Return which database types are available.
# return: hash of short-name to package name
sub _findDatabases {
    unless( %$dbTypes ) {
        my $full = UBOS::Utils::findPerlModuleNamesInPackage( 'UBOS::Databases' );
        foreach my $fileName ( keys %$full ) {
            my $packageName = $full->{$fileName};

            if( $packageName =~ m!::([A-Za-z0-9_]+)Driver$! ) {
                my $shortName = $1;
                $shortName =~ s!([A-Z])!lc($1)!ge;
                $dbTypes->{$shortName} = $packageName;
            }
        }
    }
    return $dbTypes;
}

##
# Return an instance of a database driver for the given short-name
# $shortName: short name of the database type, e.g. 'mysql'
# $dbHost: host on which the database runs
# $dbPort: port on which the database can be reached on that port
# return: database driver, e.g. an instance of UBOS::Databases::MySqlDriver
sub obtainDbDriver {
    my $shortName = shift;
    my $dbHost    = shift;
    my $dbPort    = shift || 'default';

    my $ret = $dbDriverInstances->{$shortName}->{"$dbHost:$dbPort"};
    unless( $ret ) {
        my $dbs = _findDatabases();
        my $db  = $dbs->{$shortName};
        if( $db ) {
            $ret = UBOS::Utils::invokeMethod( $db . '::new', $db, $dbHost, $dbPort );

            if( $dbPort eq 'default' ) {
                $dbDriverInstances->{$shortName}->{"$dbHost:default"} = $ret;
                $dbPort = $ret->defaultPort();
            }
            $dbDriverInstances->{$shortName}->{"$dbHost:$dbPort"} = $ret;
        }
    }
    return $ret;
}

##
# Ensure that pacman has been initialized. This may generate a key pair, which
# means it cannot be pre-installed; it also may take some time, depending on
# how much entropy is available.
sub ensurePacmanInit {
    # If the time is completely off, chances are we are on a Raspberry Pi or
    # such that hasn't connected to the network. In which case we set the system
    # time to the time of the last build
    # The BeagleBone Black apparently initializes with Jan 1, 2000.
    if( time() < 1000000000 ) { # September 2001
        my $osRelease = UBOS::Utils::slurpFile( '/etc/os-release' );
        if( $osRelease =~ m!^BUILD_ID="?(\d\d\d\d)(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)"?$!m ) {
            my( $year, $month, $day, $hour, $min, $sec ) = ( $1, $2, $3, $4, $5, $6 );

            my $ds = sprintf( '%.2d%.2d%.2d%.2d%.4d.%.2d', $month, $day, $hour, $min, $year, $sec );

            myexec( "date $ds" );
        }
    }
    if( -x '/usr/bin/pacman-db-upgrade' ) {
        debugAndSuspend( 'Execute pacman-db-upgrade' );
        myexec( 'pacman-db-upgrade' ); # not sure when this can be removed again
    }

    debugAndSuspend( 'Setup pacman keys' );
    myexec( "pacman-key --init" );

    # We trust the Arch people, Arch Linux ARM, Uplink Labs' EC2 packages and ourselves
    my $err;
    myexec( "pacman -Q archlinux-keyring    > /dev/null 2>&1 && pacman-key --populate archlinux",    undef, undef, \$err );
    myexec( "pacman -Q archlinuxarm-keyring > /dev/null 2>&1 && pacman-key --populate archlinuxarm", undef, undef, \$err );
    myexec( "pacman -Q ec2-keyring          > /dev/null 2>&1 && pacman-key --populate ec2"         , undef, undef, \$err );
    myexec( "pacman-key --populate ubos" );
}

##
# Sign payload with the private key of this host
# $payload: the payload to sign
# return: ( hash used ; the signature for the payload )
sub hostSign {
    my $payload = shift;

    my $out;
    my $err;
    if( myexec( 'GNUPGHOME=/etc/pacman.d/gnupg gpg --clear-sign --armor --local-user pacman@localhost', $payload, \$out, \$err )) {
        error( 'Cannot determine host key', $out, $err );
        return '';
    }
    if( $out =~ m!-+BEGIN PGP SIGNED MESSAGE-+\s?Hash:\s*(\S+)\s.*\s(-+BEGIN PGP SIGNATURE.*-+END PGP SIGNATURE-+)!s ) {
        my $hash      = $1;
        my $signature = $2;

        return( $hash, $signature );

    } else {
        error( 'Failed to parse GPG signature output:', $out );
        return '';
    }
}

##
# Add a command to run after the next boot. The command must be of the
# form "<tag>:<command>" where <tag> is either "bash" or "perleval".
# The bash commands must be bash-executable and will run as root.
# The perleval commands will be executed by eval'ing the command
# from ubos-admin-initialize
# @cmds: one or more commands
sub addAfterBootCommands {
    my @cmds = @_;

    my $afterBoot;
    if( -e $AFTER_BOOT_FILE ) {
        $afterBoot = UBOS::Utils::slurpFile( $AFTER_BOOT_FILE );
    }
    my $afterBootDir = dirname( $AFTER_BOOT_FILE );
    unless( -d $afterBootDir ) {
        UBOS::Utils::mkdirDashP( $afterBootDir );
    }
    foreach my $cmd ( @cmds ) {
        if( $cmd =~ m!^(bash|perleval):! ) {
            $afterBoot .= "$cmd\n";
        } else {
            error( 'Invalid after-boot command syntax:', $cmd );
        }
    }
    UBOS::Utils::saveFile( $AFTER_BOOT_FILE, $afterBoot );
}

##
# If there are commands in the after-boot file, execute them, and then remove
# the file.
# return: number of errors
sub runAfterBootCommandsIfNeeded {

    trace( 'Host::runAfterBootCommandsIfNeeded' );

    my $afterBootFile;
    if( -e $AFTER_BOOT_FILE ) {
        $afterBootFile = $AFTER_BOOT_FILE;
    } elsif( -e '/var/lib/ubos/after-boot' ) {
        # also support old location
        $afterBootFile = '/var/lib/ubos/after-boot';
    } else {
        $afterBootFile = undef;
    }

    my $errors = 0;
    if( $afterBootFile ) {
        my $afterBoot = UBOS::Utils::slurpFile( $afterBootFile );

        my @lines = split( "\n", $afterBoot );
        foreach my $line ( @lines ) {
            if( $line =~ m!^bash:(.*)$! ) {
                my $cmd = $1;
                my $out;
                my $err;
                if( myexec( "/bin/bash", $cmd, \$out, \$err )) {
                    error( "Problem when running after-boot commands. Bash command:\n$cmd\nout: $out\nerr: $err\nscript: $afterBoot");
                    ++$errors;
                }
            } elsif( $line =~ m!^perleval:(.*)$! ) {
                my $cmd = $1;
                unless( eval( $cmd )) {
                    error( "Problem when running after-boot commands. Perl command:\n$cmd\ndollar-bang: $!\ndollar-at: $@\nscript: $afterBoot" );
                    ++$errors;
                }
            }
        }
        UBOS::Utils::deleteFile( $afterBootFile );
    }
    return $errors;
}

##
# Reads manifest files from the default location.
# $packageIdentifier: the package identifier
# return: JSON
sub defaultManifestFileReader {
    my $packageIdentifier = shift;

    my $file = vars()->getResolve( 'package.manifestdir' ) . "/$packageIdentifier.json";

    my $ret = readJsonFromFile( $file );
    if( $ret ) {
        return $ret;
    } else {
        fatal( 'Failed to read or parse manifest file:', $file );
    }
}

#####
# Check whether the system is ready for the command
sub checkReady {

    if( -e $READY_FILE ) {
        my $ret = UBOS::Utils::slurpFile( $READY_FILE );
        $ret =~ s!^\s+!!;
        $ret =~ s!\s+$!!;
        return $ret;
    }
    my $out;
    myexec( 'systemctl is-system-running', undef, \$out );
    if( $out =~ m!starting!i ) {
        error( <<END );
UBOS is not done initializing yet. Please wait until:
    systemctl is-system-running
says "running" or until this message goes away.
END
        return undef;
    }

    my @services = qw( ubos-admin httpd ubos-ready );

    foreach my $service ( @services ) {
        if( myexec( 'systemctl is-failed ' . $service, undef, \$out ) == 0 ) {
            # if is-failed is true, attempt to restart
            if( $< != 0 ) {
                error( "Required service $service has failed. Try invoking your command again using 'sudo'." );
            } else {
                error( "Required service $service has failed. Attempting to restart. Try invoking your command again in a little while." );
                myexec( 'systemctl restart ' . $service );
            }
            return undef;
        }
    }
    foreach my $service ( @services ) {
        if( myexec( 'systemctl is-active ' . $service, undef, \$out )) {
            if( $< != 0 ) {
                error( "Required service $service is not active. Try invoking your command again using 'sudo'." );
            } else {
                error( "Required service $service is not active. Attempting to start. Try invoking your command again in a little while." );
                myexec( 'systemctl start ' . $service );
            }
            return undef;
        }
    }

    if( $< == 0 ) {
        UBOS::Utils::saveFile( $READY_FILE, UBOS::Utils::time2string( time() ) . "\n", 0644, 'root', 'root' );
        my $ret = UBOS::Utils::slurpFile( $READY_FILE );
        $ret =~ s!^\s+!!;
        $ret =~ s!\s+$!!;
        return $ret;
    }
    return '';
}

##
# Determine when the host was last updated using ubos-admin update.
# return: timestamp, or undef
sub lastUpdated {
    my $ret;
    if( -e $LAST_UPDATE_FILE ) {
        $ret = UBOS::Utils::slurpFile( $LAST_UPDATE_FILE );
        $ret =~ s!^\s+!!;
        $ret =~ s!\s+$!!;
    } else {
        $ret = undef;
    }
    return $ret;
}

##
# Set state back to Operational
END {
    if( defined( $_currentState ) && 'InMaintenance' eq $_currentState ) {
        UBOS::Host::setState( 'Operational' );
    }
}

1;
