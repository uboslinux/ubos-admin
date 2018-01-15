#!/usr/bin/perl
#
# Manages the configuration of the host using a config drive, called the
# ubos staff.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

#
# Comments:
# Cannot check that device is removable: some USB disks have that at 0
# We accept partitions or entire disks
# We also accept a directory called /UBOS-STAFF, to support containerization
#

use strict;
use warnings;

package UBOS::StaffManager;

use File::Temp;
use UBOS::Host;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Utils;

my $LABEL = 'UBOS-STAFF';

##
# Invoked during boot.
# 1. Initialize the configuration if there's a staff device attached
# 2. Deploy site templates if needed
sub performBootActions {
    trace( 'StaffManager::initializeIfNeeded' );

    unless( UBOS::Host::vars()->get( 'host.readstaffonboot', 1 )) {
        return;
    }

    my $device = guessStaffDevice();

    my $target = undef;
    my $init   = 0;
    if( $device ) {
        trace( 'Staff device:', $device );

        if( mountDevice( $device, \$target )) {
            error( 'Failed to mount:', $device, $target );
            return;
        }
        $init = 1;

    } else {
        # container/cloud case
        if( -d "/$LABEL" ) {
            $target = "/$LABEL";
            # don't init
        } else {
            trace( 'No staff device found' );
            return;
        }
    }

    if( $init && UBOS::Host::vars()->get( 'host.initializestaffonboot', 1 )) {
        if( _generateShepherdKeyPair( $target )) {
            error( 'Generation of shepherd key pair on staff device failed:', $device, $target );
        }
    }

    if( loadCurrentConfiguration( $target )) {
        error( 'Loading current configuration failed from', $device, $target );
    }

    if( saveCurrentConfiguration( $target )) {
        error( 'Saving current configuration failed to', $device, $target );
    }

    if( $device ) {
        if( unmountDevice( $device, $target )) {
            error( 'Failed to unmount:', $device, $target );
        }
    }

    return;
}

##
# Check that a candidate device is indeed a staff device
# $device: the candidate device, may be disk or partition
# $ignoreLabel: if 1, do not check for UBOS-STAFF label
# return: the $device if partition, or the partition device on $device, or undef
sub checkStaffDevice {
    my $device      = shift;
    my $ignoreLabel = shift;

    trace( 'StaffManager::checkStaffDevice', $device, $ignoreLabel );

    unless( -b $device ) {
        $@ = 'Not a valid UBOS staff device: ' . $device;
        return undef;
    }

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "lsblk --pairs --output NAME,TYPE,FSTYPE,LABEL '$device'", undef, \$out, \$err )) {
        fatal( 'lsblk on device failed:', $device, $out, $err );
    }
    my $ret;

    # NAME="sda" TYPE="disk" FSTYPE="" LABEL=""
    # NAME="sda1" TYPE="part" FSTYPE="ext4" LABEL=""
    # NAME="sda2" TYPE="part" FSTYPE="vfat" LABEL=""

    while( $out =~ m!NAME="([^"]+)"\s+TYPE="([^"]+)"\s+FSTYPE="([^"]+)"\s+LABEL="([^"]+)"!g ) {
        my( $name, $type, $fstype, $label ) = ( "/dev/$1", $2, $3, $4 );
        unless( $fstype eq 'vfat' ) {
            next;
        }
        if( !$ignoreLabel && $label ne $LABEL ) {
            next;
        }
        if( $ret ) {
            $@ = 'More than one partition suitable as UBOS staff found: ' . $ret . ' ' . $name;
            return undef;
        }
        $ret = $name;
    }
    unless( $ret ) {
        $@ = 'No partition suitable as UBOS staff found on: ' . $device;
    }

    return $ret;
}

##
# Guess the name of the staff device
# return: device, or undef
sub guessStaffDevice {

    trace( 'StaffManager::guessStaffDevice' );

    my $out;
    my $err;
    if( UBOS::Utils::myexec( "lsblk --pairs --output NAME,TYPE,FSTYPE,LABEL", undef, \$out, \$err )) {
        fatal( 'lsblk failed:', $out, $err );
    }

    my $ret;

    # NAME="sda" TYPE="disk" FSTYPE="" LABEL=""
    # NAME="sda1" TYPE="part" FSTYPE="ext4" LABEL=""
    # NAME="sda2" TYPE="part" FSTYPE="vfat" LABEL=""

    while( $out =~ m!NAME="([^"]+)"\s+TYPE="([^"]+)"\s+FSTYPE="([^"]+)"\s+LABEL="([^"]+)"!g ) {
        my( $name, $type, $fstype, $label ) = ( "/dev/$1", $2, $3, $4 );
        unless( $fstype eq 'vfat' ) {
            next;
        }
        unless( $label eq $LABEL ) {
            next;
        }
        if( $ret ) {
            $@ = 'More than one suitable partition found: ' . $ret . ' ' . $name;
            return undef;
        }
        $ret = $name;
    }
    unless( $ret ) {
        $@ = 'No suitable partition found.';
    }

    return $ret;
}

##
# Save current configuration to this directory
# $target: the target directory for the save (root directory of stick)
# return: number of errors
sub saveCurrentConfiguration {
    my $target = shift;

    trace( 'StaffManager::saveCurrentConfiguration', $target );

    my $keyFingerprint = UBOS::Host::gpgHostKeyFingerprint();
    my $sshDir         = "flock/$keyFingerprint/ssh";
    my $infoDir        = "flock/$keyFingerprint/device-info";

    unless( -d "$target/$sshDir" ) {
        UBOS::Utils::mkdirDashP( "$target/$sshDir" );
    }
    unless( -d "$target/$infoDir" ) {
        UBOS::Utils::mkdirDashP( "$target/$infoDir" );
    }

    # Host ssh key info
    foreach my $pubKeyFile ( glob "/etc/ssh/ssh_host_*.pub" ) {
#HostKey /etc/ssh/ssh_host_rsa_key
#HostKey /etc/ssh/ssh_host_dsa_key
#HostKey /etc/ssh/ssh_host_ecdsa_key
#HostKey /etc/ssh/ssh_host_ed25519_key
        my $shortPubKeyFile = $pubKeyFile;
        $shortPubKeyFile =~ s!^(.*/)!!;

        my $pubKey = UBOS::Utils::slurpFile( $pubKeyFile );
        UBOS::Utils::saveFile( "$target/$sshDir/$shortPubKeyFile", $pubKey );
    }

    # Add networking info
    my $deviceClass = UBOS::Host::deviceClass();
    my $nics        = UBOS::Host::nics();
    my $deviceJson  = {
        'arch'        => UBOS::Utils::arch(),
        'hostid'      => $keyFingerprint,
    };
    if( $deviceClass ) {
        $deviceJson->{deviceclass} = $deviceClass;
    }
    foreach my $nic ( keys %$nics ) {
        $deviceJson->{nics}->{$nic}->{ipv4address} = [ UBOS::Host::ipAddressesOnNic( $nic ) ];
        $deviceJson->{nics}->{$nic}->{macaddress}  = UBOS::Host::macAddressOfNic( $nic );
        foreach my $entry ( qw( type operational )) { # not all entries
            $deviceJson->{nics}->{$nic}->{$entry} = $nics->{$nic}->{$entry};
        }
    }

    UBOS::Utils::writeJsonToFile( "$target/$infoDir/device.json", $deviceJson );

    return 0;
}

##
# Completely erase all files in a directory and initialize with the staff structure
# $dir: the directory
# $shepherdKey: public ssh key for the shepherd, if any
# $wifis: hash of WiFi network client information
# $siteTemplates: hash of template name to site template JSON
# return: number of errors
sub initDirectoryAsStaff {
    my $dir           = shift;
    my $shepherdKey   = shift;
    my $wifis         = shift;
    my $siteTemplates = shift;

    my $errors = 0;

    # Delete existing content first
    unless( opendir( DIR, $dir )) {
        ++$errors;
        error( $! );
    }

    my @toDelete;
    while( my $file = readdir( DIR )) {
        if( $file ne '.' && $file ne '..' ) {
            push @toDelete, "$dir/$file";
        }
    }
    closedir( DIR );

    UBOS::Utils::deleteRecursively( @toDelete );

    # Now put new files in
    UBOS::Utils::mkdirDashP( "$dir/shepherd/ssh" );
    UBOS::Utils::saveFile( "$dir/shepherd/ssh/README", <<CONTENT );
This directory holds the public ssh key of the shepherd account. The file
must be named "id_rsa.pub" (no quotes). It may also hold the corresponding
private key, named "id_rsa" (no quotes).

For details, go to https://ubos.net/staff

CONTENT

    if( $shepherdKey ) {
        # no need to care about permissions, this is DOS
        UBOS::Utils::saveFile( "$dir/shepherd/ssh/id_rsa.pub", "$shepherdKey\n" );
    }

    UBOS::Utils::mkdirDashP( "$dir/wifi" );
    foreach my $ssid ( keys %$wifis ) {
        my $values  = $wifis->{$ssid};
        my $content = join( '', map { $_ . '="' . _escape( $values-{$_} ) . '"' . "\n" } %$values );
        UBOS::Utils::saveFile( "$dir/wifi/$ssid.conf", $content );
    }
    UBOS::Utils::saveFile( "$dir/wifi/README", <<CONTENT );
This directory can hold information about one or more WiFi networks.
Each WiFi network must be described in a separate file and must be named
<ssid>.conf if <ssid> is the SSID of the network.

For details, go to https://ubos.net/staff

CONTENT

    UBOS::Utils::mkdirDashP( "$dir/site-templates" );
    foreach my $siteTemplateName ( keys %$siteTemplates ) {
        my $siteTemplateJson = $siteTemplates->{$siteTemplateName};

        UBOS::Utils::writeJsonToFile( "$dir/site-templates/$siteTemplateName.json", $siteTemplateJson );
    }
    UBOS::Utils::saveFile( "$dir/site-templates/README", <<CONTENT );
This directory can hold one or more Site JSON templates, which will be instantiated
and deployed upon boot.

For details, go to https://ubos.net/staff

CONTENT

    return $errors;
}

##
# Label a device as being a staff device
# $device: the device
# return: number of errors
sub labelDeviceAsStaff {
    my $device = shift;

    my $out;
    my $errors = 0;

    if( UBOS::Utils::myexec( "dosfslabel '$device'", undef, \$out )) {
        error( 'Cannot read DOS filesystem label from device:', $device );
        ++$errors;
    }
    unless( $out =~ m!$LABEL! ) {
        # There might be a lot more output than just the label, such as
        # error messages. Unfortunately they are printed to stdout with
        # no clear distinction between label and message

        if( UBOS::Utils::myexec( "dosfslabel '$device' $LABEL" )) {
            error( 'Cannot change DOS filesystem label of device:', $device );
        }
    }

    return $errors;
}

##
# If this is a valid staff device, but it does not have a key for the shepherd,
# generate a key pair.
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub _generateShepherdKeyPair {
    my $target = shift;

    trace( 'StaffManager::_generateShepherdKeyPair', $target );

    my $errors = 0;
    unless( -e "$target/shepherd/ssh/id_rsa.pub" ) {
        unless( -d "$target/shepherd/ssh" ) {
            UBOS::Utils::mkdirDashP( "$target/shepherd/ssh" );
        }

        my $out;
        my $err;
        if( UBOS::Utils::myexec( "ssh-keygen -N '' -f '$target/shepherd/ssh/id_rsa'", undef, \$out, \$err )) {
            error( 'SSH key generation failed:', $out, $err );
            $errors += 1;
        }
    }
    return $errors;
}

##
# Load configuration from this directory
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub loadCurrentConfiguration {
    my $target = shift;

    trace( 'StaffManager::loadCurrentConfiguration', $target );

    my $errors = 0;
    
    $errors += _loadCurrentSshConfiguration( $target );
    $errors += _loadCurrentWiFiConfiguration( $target );
    $errors += _deploySiteTemplates( $target );

    return $errors;
}

##
# Load SSH configuration from this directory
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub _loadCurrentSshConfiguration {
    my $target =shift;
    
    if( -e "$target/shepherd/ssh/id_rsa.pub" ) {
        my $sshKey = UBOS::Utils::slurpFile( "$target/shepherd/ssh/id_rsa.pub" );
        $sshKey =~ s!^\s+!!;
        $sshKey =~ s!\s+$!!;

        unless( setupUpdateShepherd( 0, $sshKey )) {
            return 1;
        }
    }
    return 0;
}

##
# Load WiFi configuration from this directory
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub _loadCurrentWiFiConfiguration {
    my $target = shift;

    my $errors = 0;
    if( -d "$target/wifi" ) {
        my $out;
        if( UBOS::Utils::myexec( "pacman -Qi wpa_supplicant", undef, \$out, \$out )) {
            error( 'Cannot provision WiFi from staff device: package wpa_supplicant is not installed' );
            ++$errors;

        } else {
            my $confs    = UBOS::Utils::readFilesInDirectory( "$target/wifi", '*.conf' );
            my $wlanNics = UBOS::Host::wlanNics();

            if(( keys %$confs ) && ( keys %$wlanNics )) {
                unless( -d "$target/etc/wpa_supplicant" ) {
                    unless( UBOS::Utils::mkdir( "$target/etc/wpa_supplicant" )) {
                        ++$errors;
                    }
                }
                my $content = <<CONTENT;
eapol_version=1
ap_scan=1
fast_reauth=1

CONTENT
                $content .= join( "\n", map { "network={\n" . $_ . "}\n" } values %$confs );
                foreach my $nic ( keys %$wlanNics ) {
                    unless( UBOS::Utils::saveFile( "$target/etc/wpa_supplicant-$nic.conf", $content )) {
                        ++$errors;
                    }

                    if( UBOS::Utils::myexec( 'systemctl is-enabled wpa_supplicant@' . $nic . ' > /dev/null || systemctl enable wpa_supplicant@' . $nic, undef, \$out, \$out )) {
                        ++$errors;
                    }
                    if( UBOS::Utils::myexec( 'systemctl is-active  wpa_supplicant@' . $nic . ' > /dev/null || systemctl start  wpa_supplicant@' . $nic, undef, \$out, \$out )) {
                        ++$errors;
                    }
                }
            }

            # Update regulatory domain
            if( -e "$target/wifi/wireless-regdom" ) {
                unless( UBOS::Utils::copyRecursively( "$target/wifi/wireless-regdom", '/etc/conf.d/wireless-regdom' )) {
                    ++$errors;
                }
            }
        }
    }
    return $errors;
}

##
# Deploy Site templates found below this directory. If anything goes
# wrong, we don't do anything at all.
# $target: the target directory from which to read (root directory of stick)
# return: number of errors
sub _deploySiteTemplates {
    my $target = shift;

    my $errors = 0;
    my $ret    = 1;

    if( UBOS::Host::vars()->get( 'host.deploysitetemplatesonboot', 1 )) {
        my $keyFingerprint = UBOS::Host::gpgHostKeyFingerprint();

        my @templateFiles = ();
        foreach my $templateDir (
                "$target/site-templates",
                "$target/flock/$keyFingerprint/site-templates" )
                        # The host-specific templates overwrite the general ones
        {
            if( -d $templateDir ) {
                if( opendir( DIR, "$templateDir" )) {
                    while( my $entry = readdir DIR ) {
                        if( $entry !~ m!^\.! && $entry =~ m!\.json$! ) {
                            # ignore files that start with . (like ., .., and MacOS resource files)
                            push @templateFiles, "$templateDir/$entry";
                        }
                    }
                    closedir DIR;
                } else {
                    error( 'Cannot read from directory:', $templateDir );
                }
            }
        }

        my @sitesFromTemplates = (); # Some may be already deployed, we skip those
        foreach my $templateFile ( @templateFiles ) {

            trace( 'Reading template file:', $templateFile );
            my $json = readJsonFromFile( $templateFile );
            if( $json ) { 
                my $newSite = UBOS::Site->new( $json, 1 );

                if( $newSite ) {
                    push @sitesFromTemplates, $newSite;
                } else {
                    error( 'Failed to create site from:', $templateFile );
                    ++$errors;
                }
            } else {
                ++$errors;
            }
        }
        if( $errors ) {
            return $errors;
        }

        my $oldSites = UBOS::Host::sites();

        # make sure AppConfigIds, SiteIds and hostnames are unique, and that all Sites are deployable
        my $haveIdAlready      = {}; # it's okay that we have an old site by this id
        my $haveHostAlready    = {}; # it's not okay that we have an old site by this hostname if site id is different
        my $haveAnyHostAlready = 0; # true if we have the * (any) host

        foreach my $oldSite ( values %$oldSites ) {
            $haveHostAlready->{$oldSite->hostname} = $oldSite;
            if( '*' eq $oldSite->hostname ) {
                $haveAnyHostAlready = 1;
            }
        }

        my @newSites = (); # only those that had no error
        foreach my $newSite ( @sitesFromTemplates ) {
            my $newSiteId = $newSite->siteId;
            if( $haveIdAlready->{$newSiteId} ) {
                # skip
                next;
            }
            $haveIdAlready->{$newSiteId} = $newSite;

            my $newSiteHostName = $newSite->hostname;
            if( defined( $oldSites->{$newSiteId} )) {
                # do not redeploy
                next;

            } elsif( !$newSite->isTor() ) {
                # site is new and not tor
                if( $newSiteHostName eq '*' ) {
                    if( keys %$oldSites > 0 ) {
                        error( "You can only create a site with hostname * (any) if no other sites exist." );
                        ++$errors;
                        return $errors;
                    }

                } else {
                    if( $haveAnyHostAlready ) {
                        error( "There is already a site with hostname * (any), so no other site can be created." );
                        ++$errors;
                        return $errors;
                    }
                    if( $haveHostAlready->{$newSiteHostName} ) {
                        error( 'There is already a different site with hostname', $newSiteHostName );
                        ++$errors;
                        return $errors;
                    }
                }
            }
            if( defined( $newSiteHostName )) {
                # not tor
                $haveHostAlready->{$newSiteHostName} = $newSite;
            }

            foreach my $newAppConfig ( @{$newSite->appConfigs} ) {
                my $newAppConfigId = $newAppConfig->appConfigId;
                if( $haveIdAlready->{$newAppConfigId} ) {
                    error( 'More than one site or appconfig with id', $newAppConfigId );
                    ++$errors;
                    return $errors;
                }
                $haveIdAlready->{$newSiteId} = $newSite;

                foreach my $oldSite ( values %$oldSites ) {
                    foreach my $oldAppConfig ( @{$oldSite->appConfigs} ) {
                        if( $newAppConfigId eq $oldAppConfig->appConfigId ) {
                            if( $newSiteId ne $oldSite->siteId ) {
                                error(    'Non-unique appconfigid ' . $newAppConfigId
                                        . ' in sites ' . $newSiteId . ' and ' . $oldSite->siteId );
                                ++$errors;
                                return $errors;
                            }
                        }
                    }
                }
            }
            push @newSites, $newSite;
        }

        # May not be interrupted, bad things may happen if it is
        UBOS::Host::preventInterruptions();

        # No backup needed, we aren't redeploying

        info( 'Installing prerequisites' );

        # This is a two-step process: first we need to install the applications that haven't been
        # installed yet, and then we need to install their dependencies

        my $prerequisites = {};
        foreach my $site ( @newSites ) {
            $site->addInstallablesToPrerequisites( $prerequisites );
            if( $site->isTor() ) {
                $prerequisites->{'tor'} = 'tor';
            }
        }
        if( UBOS::Host::ensurePackages( $prerequisites ) < 0 ) {
            error( $@ );
            ++$errors;
            return $errors;
        }

        $prerequisites = {};
        foreach my $site ( @newSites ) {
            $site->addDependenciesToPrerequisites( $prerequisites );
        }
        if( UBOS::Host::ensurePackages( $prerequisites ) < 0 ) {
            error( $@ );
            ++$errors;
            return $errors;
        }

        trace( 'Checking context paths and customization points', $ret );

        foreach my $newSite ( @newSites ) {
            my %contexts = ();
            foreach my $newAppConfig ( @{$newSite->appConfigs} ) {
                # check contexts
                my $context = $newAppConfig->context();
                if( defined( $context )) { # amazonses may not
                    if( exists( $contexts{$context} )) {
                        error(   'Site ' . $newSite->siteId . ': more than one appconfig with context ' . $context );
                        ++$errors;
                        return $errors;
                    }
                }
                if( keys %contexts ) {
                    if( $context eq '' || defined( $contexts{''} ) ) {
                        error(   'Site ' . $newSite->siteId . ': cannot deploy app at root context if other apps are deployed at other contexts' );
                        ++$errors;
                        return $errors;
                    }
                }
                unless( $newAppConfig->checkCustomizationPointValues()) {
                    error( $@ );
                    ++$errors;
                    return $errors;
                }

                my $appPackage = $newAppConfig->app()->packageName();
                foreach my $acc ( $newAppConfig->accessories() ) {
                    if( $appPackage ne $acc->belongsToApp() ) {
                        error( 'Accessory', $acc->packageName(), 'cannot be used in appconfig', $newAppConfig->appConfigId(), 'as it does not belong to app', $appPackage );
                        ++$errors;
                        return $errors;
                    }
                }

                $contexts{$context} = $newAppConfig;
            }
        }

        # Now that we have prerequisites, we can check whether the site is deployable
        foreach my $newSite ( @newSites ) {
            unless( $newSite->checkDeployable()) {
                error( 'New site is not deployable:', $newSite );
                ++$errors;
                return $errors;
            }
        }

        info( 'Setting up placeholder sites or suspending existing sites' );

        my $suspendTriggers = {};
        foreach my $site ( @newSites ) {
            my $oldSite = $oldSites->{$site->siteId};
            if( $oldSite ) {
                debugAndSuspend( 'Suspend site', $oldSite->siteId() );
                $ret &= $oldSite->suspend( $suspendTriggers ); # replace with "upgrade in progress page"
            } else {
                debugAndSuspend( 'Setup placeholder for site', $site->siteId() );
                $ret &= $site->setupPlaceholder( $suspendTriggers ); # show "coming soon"
            }
        }
        debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
        UBOS::Host::executeTriggers( $suspendTriggers );

        my @letsEncryptCertsNeededSites = grep { $_->hasLetsEncryptTls() && !$_->hasLetsEncryptCerts() } @newSites;
        if( @letsEncryptCertsNeededSites ) {
            if( @letsEncryptCertsNeededSites > 1 ) {
                info( 'Obtaining letsencrypt certificates' );
            } else {
                info( 'Obtaining letsencrypt certificate' );
            }
            foreach my $site ( @letsEncryptCertsNeededSites ) {
                debugAndSuspend( 'Obtain letsencrypt certificate for site', $site->siteId() );
                my $success = $site->obtainLetsEncryptCertificate();
                unless( $success ) {
                    warning( 'Failed to obtain letsencrypt certificate for site', $site->hostname, '(', $site->siteId, '). Deploying site without TLS.' );
                    $site->unsetLetsEncryptTls;
                }
                $ret &= $success;
            }
        }

        info( 'Backing up, undeploying and redeploying' );

        my $deployUndeployTriggers = {};
        foreach my $site ( @newSites ) {
            debugAndSuspend( 'Deploying site', $site->siteId() );
            $ret &= $site->deploy( $deployUndeployTriggers );
        }
        UBOS::Networking::NetConfigUtils::updateOpenPorts();

        debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
        UBOS::Host::executeTriggers( $deployUndeployTriggers );

        info( 'Resuming sites' );

        my $resumeTriggers = {};
        foreach my $site ( @newSites ) {
            debugAndSuspend( 'Resuming site', $site->siteId() );
            $ret &= $site->resume( $resumeTriggers ); # remove "upgrade in progress page"
        }
        debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
        UBOS::Host::executeTriggers( $resumeTriggers );

        info( 'Running installers/upgraders' );

        foreach my $site ( @newSites ) {
            foreach my $appConfig ( @{$site->appConfigs} ) {
                debugAndSuspend( 'Running installer for appconfig', $appConfig->appConfigId );
                $ret &= $appConfig->runInstallers();
            }
        }
    }

    if( $errors ) {
        return $errors;
    } else {
        return $ret ? 0 : 1; # kludge
    }
}

##
# Create or update the shepherd user
# $add: if true, add the keys
# @keys: the public ssh keys that are allowed to log on, if any
# return: 1 if ok
sub setupUpdateShepherd {
    my $add  = shift;
    my @keys = @_;

    if( UBOS::Utils::ensureOsUser( 'shepherd', undef, 'UBOS shepherd user', '/var/shepherd' )) {
        my $authKeyFile = '/var/shepherd/.ssh/authorized_keys';
        unless( -d '/var/shepherd/.ssh' ) {
            UBOS::Utils::mkdir( "/var/shepherd/.ssh", 0700, 'shepherd', 'shepherd' );
        }
        my $authorizedKeys;
        if( $add && -e $authKeyFile ) {
            $authorizedKeys = UBOS::Utils::slurpFile( $authKeyFile );
        }
        if( @keys ) {
            $authorizedKeys .= join( "\n", @keys ) . "\n";
        }

        if( defined( $authorizedKeys )) {
            UBOS::Utils::saveFile( $authKeyFile, $authorizedKeys, 0644, 'shepherd', 'shepherd' );
        }

        unless( UBOS::Utils::saveFile( '/etc/sudoers.d/shepherd', <<'CONTENT', 0600, 'root', 'root' )) {
shepherd ALL = NOPASSWD: \
    /usr/bin/journalctl *, \
    /usr/bin/mkdir *, \
    /usr/bin/mount *, \
    /usr/bin/pacman *, \
    /usr/bin/smartctl *, \
    /usr/bin/systemctl *, \
    /usr/bin/ubos-admin *, \
    /usr/bin/ubos-install *, \
    /usr/bin/umount *, \
    /usr/bin/snapper *, \
    /usr/bin/su *, \
    /bin/bash *
CONTENT
            return 0;
        }
    }
    return 1;
}

##
# Helper method to mount a device
# $device: name of the device, e.g. /dev/sdc1
# $targetP: writes the tmp directory object into this var (not the name)
# return: number of errors
sub mountDevice {
    my $device  = shift;
    my $targetP = shift;
    
    my $tmpDir    = UBOS::Host::vars()->get( 'host.tmp', '/tmp' );
    $$targetP     = File::Temp->newdir( DIR => $tmpDir, UNLINK => 1 );
    my $targetDir = $$targetP->dirname;
    my $errors    = 0;

    debugAndSuspend( 'Mount staff device', $device, 'to', $targetDir );
    if( UBOS::Utils::myexec( "mount -t vfat '$device' '$targetDir'" )) {
        ++$errors;
    }
    return $errors;
}

##
# Helper method to unmount a mounted device
# $device: name of the device, e.g. /dev/sdc1
# $target: the tmp directory object (not the name)
# return: number of errors
sub unmountDevice {
    my $device = shift;
    my $target = shift;

    my $targetDir = $target->dirname;
    my $errors    = 0;

    debugAndSuspend( 'Unmount', $targetDir );
    if( UBOS::Utils::myexec( "umount '$targetDir'" )) {
        ++$errors;
    }

    return $errors;
}

1;
