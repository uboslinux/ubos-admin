#!/usr/bin/perl
#
# Command that asks the user about the site they want to create, and
# then deploys the site.
# then deploys the site.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Commands::Createsite;

use Cwd;
use File::Basename;
use File::Temp;
use Getopt::Long qw( GetOptionsFromArray );
use Term::ANSIColor;
use UBOS::Host;
use UBOS::Installable;
use UBOS::Logging;
use UBOS::Networking::NetConfigUtils;
use UBOS::Terminal;
use UBOS::UpdateBackup;
use UBOS::Utils;

##
# Execute this command.
# return: 1 if ok, 0 if error
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $verbose       = 0;
    my $logConfigFile = undef;
    my $debug         = undef;
    my $askAll        = 0;
    my $tls           = 0;
    my $selfSigned    = 0;
    my $letsEncrypt   = 0;
    my $out           = undef;
    my $force         = 0;
    my $tor           = 0;
    my $fromTemplate  = undef;
    my $quiet         = 0;
    my $dryRun;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'verbose+'                     => \$verbose,
            'logConfig=s'                  => \$logConfigFile,
            'debug'                        => \$debug,
            'askForAllCustomizationPoints' => \$askAll,
            'tls'                          => \$tls,
            'selfsigned'                   => \$selfSigned,
            'letsencrypt'                  => \$letsEncrypt,
            'tor'                          => \$tor,
            'out=s'                        => \$out,
            'force'                        => \$force,
            'from-template=s'              => \$fromTemplate,
            'quiet'                        => \$quiet,
            'dry-run|n'                    => \$dryRun );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile, $debug );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile )
        || ( $selfSigned && !$tls )
        || ( $letsEncrypt && !$tls )
        || ( $tor && $letsEncrypt )
        || ( $selfSigned && $letsEncrypt ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( $out && -e $out && !$force ) {
        fatal( 'Output file exists already. Use --force to overwrite.' );
    }

    if( !$dryRun && $< != 0 ) {
        fatal( "This command must be run as root" );
    }

    my $jsonTemplate = undef;
    if( $fromTemplate ) {
        unless( -r $fromTemplate ) {
            fatal( 'Template file does not exist or cannot be read:', $fromTemplate );
        }
        $jsonTemplate = UBOS::Utils::readJsonFromFile( $fromTemplate );
        unless( $jsonTemplate ) {
            fatal();
        }
    }

    my $oldSites        = UBOS::Host::sites();
    my $starWarningDone = 0;

    if( !$tor && grep { '*' eq $_->hostname } values %$oldSites ) {
        if( $dryRun ) {
            warning( "There is already a site with hostname * (any). You will not be able to deploy the site you are creating on this device." );
            $starWarningDone = 1;
        } else {
            fatal( 'There is already a site with hostname * (any), so no other site can be created.' );
        }
    }

    if( !$jsonTemplate && !$quiet ) {
        colPrintAskSection( "First a few questions about the website that you are about to create:\n" );
    }

# Determine hostname

    my $hostname = undef;
    unless( $tor ) {
        outer: while( 1 ) {
            if( $jsonTemplate && exists( $jsonTemplate->{hostname} )) {
                $hostname = $jsonTemplate->{hostname};
                if( UBOS::Host::findSiteByHostname( $hostname )) {
                    fatal( 'A site with this hostname is deployed already. Cannot create a new site from this template:', $hostname );
                }
            } else {
                $hostname = askAnswer( "Hostname (or * for any): ", '^[a-z0-9]([-_a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-_a-z0-9]*[a-z0-9])?)*$|^\*$' );
            }

            if( '*' eq $hostname ) {
                if( %$oldSites ) {
                    if( $dryRun ) {
                        unless( $starWarningDone ) {
                            warning( "You can only create a site with hostname * (any) if no other sites exist. You will not be able to deploy the site you are creating on this device." );
                        }
                    } else {
                        error( "You can only create a site with hostname * (any) if no other sites exist." );
                        next outer;
                    }
                }
                if( $tls ) {
                    error( "You cannot create a site with hostname * (any) that is protected by TLS." );
                    next outer;
                }
            } else {
                if( $letsEncrypt ) {
                    if( $hostname =~ m!^\d+\.\d+\.\d+\.\d+$! ) {
                        error( "You cannot specify an IP address as a hostname when using Letsencrypt certificates.\n"
                               . "Use an official hostname, publicly accessible, instead." );
                        next outer;
                    } elsif( $hostname =~ m!\.local$! ) {
                        error( "You cannot specify an mDNS (.local) as a hostname when using Letsencrypt certificates.\n"
                               . "Use an official hostname, publicly accessible, instead." );
                        next outer;
                    }
                }
                foreach my $oldSite ( values %$oldSites ) {
                    if( $oldSite->hostname eq $hostname ) {
                        if( $dryRun ) {
                            warning( "There is already a site with hostname $hostname. You will not be able to deploy the site you are creating on this device." );
                        } else {
                            error( "There is already a site with hostname $hostname." );
                            next outer;
                        }
                    }
                }
            }
            last;
        }
    }

# Determine admin user info

    my $siteId          = undef;
    my $adminUserId     = undef;
    my $adminUserName   = undef;
    my $adminCredential = undef;
    my $adminEmail      = undef;

    if( $jsonTemplate ) {
        if( defined( $jsonTemplate->{siteid} )) {
            $siteId = $jsonTemplate->{siteid};

            if( $oldSites->{$siteId} ) {
                fatal( 'A site with this siteid is deployed already. Cannot create a new site from this template:', $siteId );
            }
        }
        if( defined( $jsonTemplate->{admin} )) {
            if( defined( $jsonTemplate->{admin}->{userid} )) {
                $adminUserId = $jsonTemplate->{admin}->{userid};
            }
            if( defined( $jsonTemplate->{admin}->{username} )) {
                $adminUserName = $jsonTemplate->{admin}->{username};
            }
            if( defined( $jsonTemplate->{admin}->{credential} )) {
                $adminCredential = $jsonTemplate->{admin}->{credential};
            }
            if( defined( $jsonTemplate->{admin}->{email} )) {
                $adminEmail = $jsonTemplate->{admin}->{email};
            }
        }
    }
    unless( $siteId ) {
        $siteId = UBOS::Host::createNewSiteId();
    }
    unless( $adminUserId ) {
        $adminUserId = askAnswer( 'Site admin user id (e.g. admin): ', '^[a-z0-9]+$' );
    }
    unless( $adminUserName ) {
        $adminUserName = askAnswer( 'Site admin user name (e.g. John Doe): ', '\S+' );
    }

    while( !$adminCredential ) {
        while( 1 ) {
            if( $jsonTemplate && defined( $jsonTemplate->{admin} ) && defined( $jsonTemplate->{admin}->{credential} )) {
                $adminCredential = $jsonTemplate->{admin}->{credential};
            } else {
                $adminCredential = askAnswer( 'Site admin user password (e.g. s3cr3t): ', '^\S[\S ]{6,30}\S$', undef, 1 );
                # Use same regex as in Site::_checkJson
            }
            if( $adminCredential =~ m!s3cr3t!i ) {
                error( "Not that one!" );
            } elsif( $adminCredential eq $adminUserId ) {
                error( "Password must be different from username." );
            } elsif( length( $adminCredential ) < 6 ) {
                error( "At least 8 characters please." );
            } else {
                last;
            }
        }
        my $adminCredential2 = askAnswer( 'Repeat site admin user password: ', undef, undef, 1 );
        if( $adminCredential ne $adminCredential2 ) {
            error( "Passwords did not match!" );
            $adminCredential = undef;
        } else {
            last;
        }
    }
    while( !$adminEmail ) {
        $adminEmail = askAnswer( 'Site admin user e-mail (e.g. foo@bar.com): ', '^[a-z0-9._%+-]+@[a-z0-9.-]*[a-z]$' );
        if( $adminEmail =~ m!foo\@bar.com! ) {
            error( "Not that one!" );
            $adminEmail = undef;
        } else {
            last;
        }
    }

# Obtain TLS info

    my $tlsKey;
    my $tlsCrt;
    my $tlsCrtChain;
    my $tlsCaCrt;

    if( $tls ) {
        if( $letsEncrypt ) {
            # nothing here

        } elsif( $selfSigned ) {

            unless( $quiet ) {
                colPrintInfo( "Generating TLS keys...\n" );
            }

            my $tmpDir = UBOS::Host::vars()->getResolve( 'host.tmp', '/tmp' );
            my $dir    = File::Temp->newdir( DIR => $tmpDir );
            chmod 0700, $dir;

            my $err;
            if( UBOS::Utils::myexec( "openssl genrsa -out '$dir/key' 4096 ", undef, undef, \$err )) {
                fatal( 'openssl genrsa failed', $err );
            }
            debugAndSuspend( 'Keys generated, CSR is next' );
            if( UBOS::Utils::myexec( "openssl req -new -key '$dir/key' -out '$dir/csr' -batch -subj '/CN=$hostname'", undef, undef, \$err )) {
                fatal( 'openssl req failed', $err );
            }
            debugAndSuspend( 'CRT generated, CRT is next' );
            if( UBOS::Utils::myexec( "openssl x509 -req -days 3650 -in '$dir/csr' -signkey '$dir/key' -out '$dir/crt'", undef, undef, \$err )) {
                fatal( 'openssl x509 failed', $err );
            }
            $tlsKey = UBOS::Utils::slurpFile( "$dir/key" );
            $tlsCrt = UBOS::Utils::slurpFile( "$dir/crt" );

            debugAndSuspend( 'CRT generated, cleaning up' );
            UBOS::Utils::deleteFile( "$dir/key", "$dir/csr", "$dir/crt" );

        } else {
            # not self-signed
            while( 1 ) {
                $tlsKey = askAnswer( 'SSL/TLS private key file: ' );
                unless( $tlsKey ) {
                    redo;
                }
                unless( -r $tlsKey ) {
                    error( "Cannot find or read file $tlsKey" );
                    redo;
                }
                $tlsKey = UBOS::Utils::slurpFile( $tlsKey );
                unless( $tlsKey =~ m!^-----BEGIN RSA PRIVATE KEY-----.*-----END RSA PRIVATE KEY-----\s*$!s ) {
                    error( "This file does not seem to contain a private key" );
                    redo;
                }
                last;
            }

            while( 1 ) {
                $tlsCrt = askAnswer( 'Certificate file (only domain cert, or entire chain): ' );
                unless( $tlsCrt ) {
                    redo;
                }
                unless( -r $tlsCrt ) {
                    error( "Cannot find or read file $tlsCrt" );
                    redo;
                }
                $tlsCrt = UBOS::Utils::slurpFile( $tlsCrt );
                unless( $tlsCrt =~ m!^-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\s*$!s ) {
                    error( "This file does not seem to contain a certificate" );
                    redo;
                }
                last;
            }

            while( 1 ) {
                $tlsCrtChain = askAnswer( 'Certificate chain file (enter blank if chain was already contained in certificate file): ' );
                unless( $tlsCrtChain ) {
                    $tlsCrtChain = undef;
                    last;
                }
                unless( -r $tlsCrtChain ) {
                    error( "Cannot find or read file $tlsCrtChain" );
                    redo;
                }
                $tlsCrtChain = UBOS::Utils::slurpFile( $tlsCrtChain );
                unless( $tlsCrtChain =~ m!^-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\s*$!s ) {
                    error( "This file does not seem to contain a certificate chain");
                    redo;
                }
                last;
            }

            while( 1 ) {
                $tlsCaCrt = askAnswer( 'Client certificate chain file (or enter blank if none): ' );
                unless( $tlsCaCrt ) {
                    $tlsCaCrt = undef;
                    last;
                }
                unless( -r $tlsCaCrt ) {
                    error( "Cannot find or read file $tlsCaCrt" );
                    redo;
                }
                $tlsCaCrt = UBOS::Utils::slurpFile( $tlsCaCrt );
                unless( $tlsCaCrt =~ m!^-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\s*$!s ) {
                    error( "This file does not seem to contain a certificate chain" );
                    redo;
                }
                last;
            }
        }
    }

# Start putting the new Site Json together -- host, admin, TLS,
# not AppConfigurations yet

    my $newSiteJson = {};
    $newSiteJson->{siteid} = $siteId;

    if( defined( $hostname )) {
        $newSiteJson->{hostname} = $hostname;
    }

    $newSiteJson->{admin}->{userid}     = $adminUserId;
    $newSiteJson->{admin}->{username}   = $adminUserName;
    $newSiteJson->{admin}->{credential} = $adminCredential;
    $newSiteJson->{admin}->{email}      = $adminEmail;

    if( $tls ) {
        if( $letsEncrypt ) {
            $newSiteJson->{tls}->{letsencrypt} = JSON::true;
        }
        if( $tlsKey ) {
            $newSiteJson->{tls}->{key} = $tlsKey;
        }
        if( $tlsCrt ) {
            $newSiteJson->{tls}->{crt} = $tlsCrt;
            if( $tlsCrtChain ) {
                $newSiteJson->{tls}->{crt} .= "\n$tlsCrtChain";
            }
            # not using crtchain any more as it is deprecated in Apache
        }
        if( $tlsCaCrt ) {
            $newSiteJson->{tls}->{cacrt} = $tlsCaCrt;
        }
    }
    if( $tor ) {
        $newSiteJson->{tor} = {};
    }

    if( !$jsonTemplate && !$quiet ) {
        colPrintAskSection( "Now a few questions about the app(s) you are going to deploy to this site:\n" );
    }

    if( $jsonTemplate && defined( $jsonTemplate->{wellknown} )) {
        $newSiteJson->{wellknown} = $jsonTemplate->{wellknown};
    }

# AppConfigurations

    if( $jsonTemplate ) {
        foreach my $appConfig ( @{$jsonTemplate->{appconfigs}} ) {
            my $appConfigId = $appConfig->{appconfigid};
            if( UBOS::Host::findAppConfigurationById( $appConfigId )) {
                fatal( 'An AppConfiguration with this appconfigid is deployed already. Cannot create a new site from this template:', $hostname );
            }

            my $appId  = $appConfig->{appid};
            my @accIds = exists( $appConfig->{accessoryids} ) ? @{$appConfig->{accessoryids}} : ();
            if( UBOS::Host::ensurePackages( [ $appId, @accIds ], $quiet ) < 0 ) {
                fatal( 'Cannot find installable:', $@ );
            }

            my $app = UBOS::App->new( $appId );
            unless( $app ) {
                fatal( 'Package exists but is not an app:', $appId );
            }

            my $custPointValues = {};
            my %accs            = (); # map name->Accessory

            my %currentAccs;
            map { $currentAccs{$_} = $_ } @accIds;
            while( %currentAccs ) {
                # accessories can require other accessories, and so forth
                my %nextAccs;

                my @currentAccList = keys %currentAccs;
                if( UBOS::Host::ensurePackages( \@currentAccList, $quiet ) >= 0 ) {
                    foreach my $currentAccId ( @currentAccList ) {
                        my $acc = UBOS::Accessory->new( $currentAccId );
                        unless( $acc ) {
                            fatal( 'Package exists but is not an accessory: ', $currentAccId );
                        }
                        # don't repeat accessories
                        map {
                            unless( exists( $accs{$_} )) {
                                $nextAccs{$_} = $_;
                            }
                        } $acc->requires;

                        $accs{$acc->packageName} = $acc;
                    }
                    %currentAccs = %nextAccs;
                    %nextAccs    = ();
                }
            }
            foreach my $acc ( values %accs ) {
                if( !$acc->canBeUsedWithApp( $appId ) ) {
                    fatal( 'Accessory', $acc->packageName(), 'cannot be used here as it does not belong to app', $appId );
                }
            }
            _askForCustomizationPoints(
                    $custPointValues,
                    exists( $appConfig->{customizationpoints} ) ? $appConfig->{customizationpoints} : undef,
                    [ $app, values %accs ],
                    $askAll );

            my $appConfigJson = {};
            $appConfigJson->{appconfigid} = $appConfigId;
            $appConfigJson->{appid}       = $appId;

            if( defined( $jsonTemplate->{context} )) {
                $appConfigJson->{context} = $jsonTemplate->{context};
            }

            if( %accs ) {
                $appConfigJson->{accessoryids} = [];
                map { push @{$appConfigJson->{accessoryids}}, $_; } keys %accs;
            }

            if( keys %$custPointValues ) {
                $appConfigJson->{customizationpoints} = $custPointValues;
            }
            unless( exists( $newSiteJson->{appconfigs} )) {
                $newSiteJson->{appconfigs} = [];
            }
            push @{$newSiteJson->{appconfigs}}, $appConfigJson;
        }
    } else {
        # not from template
        my $counter = 'First';
        my %contextPaths = ();

        while( 1 ) {
            my $appId;
            my %accs = ();

            while( 1 ) {
                $appId = askAnswer( $counter . " app to run (or leave empty when no more apps): ", '^[-._a-z0-9]+$|^$' );
                if( !$appId || UBOS::Host::ensurePackages( $appId, $quiet ) >= 0 ) {
                    last;
                }
                if( $@ =~ m!unless you are root! ) {
                    fatal( 'To download this package, you need root privileges. Please re-run as root' );
                }
                if( $@ =~ m!The requested URL returned error: 404! ) {
                    fatal( 'Before this package can be installed, you need to run "ubos-admin update". Then try again.' );
                }
                error( $@ );
            }
            unless( $appId ) {
                last;
            }

            my $app = UBOS::App->new( $appId );
            unless( $app ) {
                error( 'Package exists but is not an app:', $appId );
            }

            my $context         = undef;
            my $custPointValues = {};

            my $defaultContext = $app->defaultContext;
            my $fixedContext   = $app->fixedContext;
            if( defined( $defaultContext )) {
                colPrint( "App $appId suggests context path " . ( $defaultContext ? $defaultContext : '<empty string> (i.e. root of site)' ) . "\n" );
                while( 1 ) {
                    $context = askAnswer( 'Enter context path: ' );

                    if( !UBOS::AppConfiguration::isValidContext( $context )) {
                        error( "Invalid context path. A valid context path is either empty or starts with a slash; no spaces or additional slashes" );
                    } elsif( $context eq '' && keys %contextPaths > 0 ) {
                        error( "Cannot put an app at the root context path if there is another app at the same site" );
                    } elsif( exists( $contextPaths{$context} )) {
                        error( "There is already an app at this context path" );
                    } else {
                        $contextPaths{$context} = $context;
                        last;
                    } # we abort the loop as soon as there's an app at the root context
                }
            } elsif( defined( $fixedContext )) {
                if( exists( $contextPaths{$fixedContext} )) {
                    error( "App $appId has an unchangeable context path of $fixedContext, but another app is already at this path. Cannot install here." );
                    next;
                } elsif( '' eq $fixedContext && keys %contextPaths > 0 ) {
                    error( "App $appId must be installed at the root of the site. This means no other app can run at this site, but at least one is here already." );
                    next;
                }
                $context = $fixedContext;
            }

            while( 1 ) {
                my $askUserAgain = 0;
                my $accessories = askAnswer( "Any accessories for $appId? Enter list: " );
                $accessories =~ s!^\s+!!;
                $accessories =~ s!\s+$!!;

                my %currentAccs;
                map { $currentAccs{$_} = $_ } split( /[\s,]+/, $accessories );
                ACCS: while( %currentAccs && !$askUserAgain ) {
                    # accessories can require other accessories, and so forth
                    my %nextAccs;

                    my @currentAccList = keys %currentAccs;
                    if( UBOS::Host::ensurePackages( \@currentAccList, $quiet ) >= 0 ) {
                        foreach my $currentAccId ( @currentAccList ) {
                            my $acc = UBOS::Accessory->new( $currentAccId );
                            unless( $acc ) {
                                error( 'Package exists but it not an accessory. Please re-enter:', $currentAccId );
                                last ACCS;
                            }

                            # don't repeat accessories
                            map {
                                unless( exists( $accs{$_} )) {
                                    $nextAccs{$_} = $_;
                                }
                            } $acc->requires;

                            $accs{$acc->packageName} = $acc;
                        }
                        %currentAccs = %nextAccs;
                        %nextAccs    = ();

                    } else {
                        if( $@ =~ m!unless you are root! ) {
                            fatal( 'To download a needed package, you need root privileges. Please re-run as root' );
                        }
                        if( $@ =~ m!The requested URL returned error: 404! ) {
                            fatal( 'Before this package can be installed, you need to run "ubos-admin update". Then try again.' );
                        }
                        error( $@ );
                        $askUserAgain = 1;
                    }
                }

                unless( $askUserAgain ) {
                    last;
                }
            }

            foreach my $acc ( values %accs ) {
                if( !$acc->canBeUsedWithApp( $appId ) ) {
                    fatal( 'Accessory', $acc->packageName(), 'cannot be used here as it does not belong to app', $appId );
                }
            }
            _askForCustomizationPoints(
                    $custPointValues,
                    undef,
                    [ $app, values %accs ],
                    $askAll );

            my $appConfigJson = {};
            $appConfigJson->{appconfigid} = UBOS::Host::createNewAppConfigId();
            $appConfigJson->{appid}       = $appId;

            if( defined( $context )) {
                $appConfigJson->{context} = $context;
            }
            if( %accs ) {
                $appConfigJson->{accessoryids} = [];
                map { push @{$appConfigJson->{accessoryids}}, $_; } keys %accs;
            }

            if( keys %$custPointValues ) {
                $appConfigJson->{customizationpoints} = $custPointValues;
            }
            unless( exists( $newSiteJson->{appconfigs} )) {
                $newSiteJson->{appconfigs} = [];
            }
            push @{$newSiteJson->{appconfigs}}, $appConfigJson;

            if( defined( $context ) && $context eq '' ) {
                last;
            }
            $counter = 'Next';
        }
    }

# Output JSON

    my $ret = 1;
    if( $out ) {
        UBOS::Utils::writeJsonToFile( $out, $newSiteJson );

    } elsif( $dryRun ) {
        print UBOS::Utils::writeJsonToString( $newSiteJson );

    }

# Deploy

    unless( $dryRun ) {
        my $newSite = UBOS::Site->new( $newSiteJson );
        unless( $newSite ) {
            fatal( $@ );
        }

        my $prerequisites = {};
        if( $tor ) {
            $prerequisites->{'tor'} = 'tor';
        }
        $newSite->addDependenciesToPrerequisites( $prerequisites );
        if( UBOS::Host::ensurePackages( $prerequisites, $quiet ) < 0 ) {
            fatal( $@ );
        }

        foreach my $newAppConfig ( @{$newSite->appConfigs} ) {
            unless( $newAppConfig->checkCompleteCustomizationPointValues()) {
                fatal( $@ );
            }
        }

        $newSite->checkDeployable();

        unless( $quiet ) {
            colPrint( "Deploying...\n" );
        }

        # May not be interrupted, bad things may happen if it is
        UBOS::Host::preventInterruptions();

        info( 'Setting up placeholder sites' );

        my $suspendTriggers = {};
        debugAndSuspend( 'Setting up placeholder for site', $newSite->siteId() );
        $ret &= $newSite->setupPlaceholder( $suspendTriggers ); # show "coming soon"

        debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
        UBOS::Host::executeTriggers( $suspendTriggers );

        my $deployUndeployTriggers = {};
        debugAndSuspend( 'Deploy site', $newSite->siteId() );
        $ret &= $newSite->deploy( $deployUndeployTriggers );
        $ret &= $newSite->runInstallers();

        UBOS::Networking::NetConfigUtils::updateOpenPorts();

        debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
        UBOS::Host::executeTriggers( $deployUndeployTriggers );

        info( 'Resuming sites' );

        my $resumeTriggers = {};
        debugAndSuspend( 'Resume site', $newSite->siteId() );
        $ret &= $newSite->resume( $resumeTriggers ); # remove "upgrade in progress page"
        debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
        UBOS::Host::executeTriggers( $resumeTriggers );

        if( $out ) {
            # Need to be at the end, so tor info has been inserted
            UBOS::Utils::writeJsonToFile( $out, $newSiteJson );
        }

        if( $ret ) {
            $hostname = $newSite->hostname(); # tor site might have generated the hostname
            if( $tls ) {
                colPrint( "Installed site $siteId at https://$hostname/\n" );
            } else {
                colPrint( "Installed site $siteId at http://$hostname/\n" );
            }
        } else {
            error( "Createsite failed." );
        }
    }
    return $ret;
}

##
# Handle customization points
# $custPointValues: insert into this Site JSON fragment here
# $custPointValuesFromTemplate: if defined, holds values from the provided site template
# $installables: all the installables at this AppConfiguration
# $askAll: 1 if asking for all customization points
sub _askForCustomizationPoints {
    my $custPointValues             = shift;
    my $custPointValuesFromTemplate = shift;
    my $installables                = shift;
    my $askAll                      = shift;

    foreach my $installable ( @$installables ) {
        my $packageName = $installable->packageName();
        my $custPoints  = $installable->customizationPoints();

        if( $custPoints ) {
            my $knownCustomizationPointTypes = $UBOS::Installable::knownCustomizationPointTypes;
            my @sortedCustPointNames         = _sortCustomizationPoints( $custPoints );

            foreach my $custPointName ( @sortedCustPointNames ) {
                my $custPointDef = $custPoints->{$custPointName};

                if(    $custPointValuesFromTemplate
                    && defined( $custPointValuesFromTemplate->{$packageName} )
                    && defined( $custPointValuesFromTemplate->{$packageName}->{$custPointName} )
                    && defined( $custPointValuesFromTemplate->{$packageName}->{$custPointName}->{value} ))
                {
                    my $value = $custPointValuesFromTemplate->{$packageName}->{$custPointName}->{value};
                    my $custPointValidation = $knownCustomizationPointTypes->{ $custPointDef->{type}};
                    my ( $ok, $cleanValue ) = $custPointValidation->{valuecheck}->( $value, $custPointDef );
                    unless( $ok ) {
                        fatal( 'Cannot create a site based on this template:', $custPointValidation->{valuecheckerror} );
                    }
                    $custPointValues->{$packageName}->{$custPointName}->{value} = $cleanValue;
                    next;
                }

                if( !$askAll && !$custPointDef->{required} ) {
                    next;
                }
                my $isFile = $UBOS::Installable::knownCustomizationPointTypes->{$custPointDef->{type}}->{isFile};
                while( 1 ) {
                    my $blank =    ( 'password' eq $custPointDef->{type} )
                                || (    exists( $custPointDef->{private} )
                                     && $custPointDef->{private}
                                     && 'text' ne $custPointDef->{type} );

                    my $value = askAnswer(
                            (( ref( $installable ) =~ m!App! ) ? 'App ' : 'Accessory ' )
                            . $installable->packageName
                            . ( $askAll ? ' allows' : ' requires' )
                            . " customization for $custPointName"
                            . ( $isFile ? ' (enter filename)' : ' (enter value)' )
                            . ': ',
                            exists( $custPointDef->{regex} ) ? $custPointDef->{regex} : undef,
                            $blank,
                            $blank );

                    if( !$value && !$custPointDef->{required} ) {
                        # allow defaults for non-required values
                        last;
                    }

                    if( $isFile ) {
                        unless( -r $value ) {
                            error( 'Cannot read file:', $value );
                            next;
                        }
                        $value = UBOS::Utils::slurpFile( $value );
                    }

                    my $custPointValidation = $knownCustomizationPointTypes->{ $custPointDef->{type}};
                    my ( $ok, $cleanValue ) = $custPointValidation->{valuecheck}->( $value, $custPointDef );
                    if( $ok ) {
                        $custPointValues->{$installable->packageName}->{$custPointName}->{value} = $cleanValue;
                        last;
                    } else {
                        error( $custPointValidation->{valuecheckerror} );
                    }
                }
            }
        }
    }
}

##
# Helper method to sort customization points
# $custPoints: hash of customization point name to info
# return: array of customization points names
sub _sortCustomizationPoints {
    my $custPoints = shift;

    my @ret = sort {
        my $aData = $custPoints->{$a};
        my $bData = $custPoints->{$b};

        # compare index fields if they exist. with index field comes first,
        # otherwise alphabetical
        if( exists( $aData->{index} )) {
            if( exists( $bData->{index} )) {
                return $aData->{index} <=> $bData->{index};
            } else {
                return -1;
            }
        } else {
            if( exists( $bData->{index} )) {
                return 1;
            } else {
                return $a cmp $b;
            }
        }
    } keys %$custPoints;

    return @ret;
}

##
# Return help text for this command.
# return: hash of synopsis to help text
sub synopsisHelp {
    return {
        'summary' => <<SSS,
    Interactively define and install a new website.
SSS
        'detail' => <<DDD,
    This command will ask for all configuration information necessary
    for this site, including which app(s) to run at the site, which
    accessories, hostname, and the like. It can be used to run more than
    one app at a site, as long as the apps' context URLs don't overlap.
DDD
        'cmds' => {
            '' => <<HHH,
    Create the site with a http URL.
HHH
            <<SSS => <<HHH,
    --tls
SSS
    Create the site with a https URL. The user will be prompted for the
    names of files containing the TLS key and certificate chain.
HHH
            <<SSS => <<HHH,
    --tls --selfsigned
SSS
    Create the site with a https URL. UBOS will automatically generate
    a self-signed TLS certificate.
HHH
            <<SSS => <<HHH,
    --tls --letsencrypt
SSS
    Create the site with a https URL. UBOS will automatically contact
    the letsencrypt.org certificate authority and obtain a letsencrypt
    certificate. This only works if 1) the device has a publicly
    reachable IP address, and 2) the public hostname of the site
    correctly resolves to the device.
HHH
            <<SSS => <<HHH,
    --tor
SSS
    Create the site as a Tor hidden service. It will only be accessible
    through The Onion Network using a special Tor browser or router.
    A random .onion hostname will be automatically assigned.
HHH
        },
        'args' => {
            '--verbose' => <<HHH,
    Display extra output. May be repeated for even more output.
HHH
            '--logConfig <file>' => <<HHH,
    Use an alternate log configuration file for this command.
HHH
            '--quiet' => <<HHH,
    Reduce the number of progress messages printed to the terminal.
HHH
            '--askForAllCustomizationPoints' => <<HHH,
    Ask the user for values for all customization points, not just the
    ones that are required and have no default value.
HHH
            '--from-template <file>' => <<HHH,
    Use the provided Site JSON file template as a template and only ask
    for those pieces of information not already provided in the template.
HHH
            '--out <file>' => <<HHH,
    Save the generated Site JSON file locally to file <file>.
HHH
            '--force' => <<HHH,
    If the output file exists already, overwrite instead of aborting.
HHH
            '--dry-run' => <<HHH,
    Do not actually deploy the site. In conjunction with --out, this is
    useful to only generate a Site JSON file without deploying it on the
    current device.
HHH
            '-n' => <<HHH
    Synonyn for --dry-run.
HHH
        }
    };
}

1;
