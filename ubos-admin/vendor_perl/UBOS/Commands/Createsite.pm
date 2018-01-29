#!/usr/bin/perl
#
# Command that asks the user about the site they want to create, and
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
use UBOS::Host;
use UBOS::Installable;
use UBOS::Logging;
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
            'out=s',                       => \$out,
            'force',                       => \$force,
            'quiet',                       => \$quiet,
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

    my $oldSites        = UBOS::Host::sites();
    my $starWarningDone = 0;

    if( !$tor && grep { '*' eq $_->hostname } values %$oldSites ) {
        if( $dryRun ) {
            print "WARNING: There is already a site with hostname * (any). You will not be able to deploy the site you are creating on this device.\n";
            $starWarningDone = 1;
        } else {
            fatal( 'There is already a site with hostname * (any), so no other site can be created.' );
        }
    }

    unless( $quiet ) {
        print "** First a few questions about the website that you are about to create:\n";
    }

    my $hostname = undef;
    unless( $tor ) {
        outer: while( 1 ) {
            $hostname = ask( "Hostname (or * for any): ", '^[a-z0-9]([-_a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-_a-z0-9]*[a-z0-9])?)*$|^\*$' );

            if( '*' eq $hostname ) {
                if( %$oldSites ) {
                    if( $dryRun ) {
                        unless( $starWarningDone ) {
                            print "WARNING: You can only create a site with hostname * (any) if no other sites exist. You will not be able to deploy the site you are creating on this device.\n";
                        }
                    } else {
                        print "You can only create a site with hostname * (any) if no other sites exist.\n";
                        next outer;
                    }
                }
                if( $tls ) {
                    print "You cannot create a site with hostname * (any) that is protected by TLS.\n";
                    next outer;
                }
            } else {
                if( $letsEncrypt ) {
                    if( $hostname =~ m!^\d+\.\d+\.\d+\.\d+$! ) {
                        print "You cannot specify an IP address as a hostname when using Letsencrypt certificates.\n";
                        print "Use an official hostname, publicly accessible, instead.\n";
                        next outer;
                    } elsif( $hostname =~ m!\.local$! ) {
                        print "You cannot specify an mDNS (.local) as a hostname when using Letsencrypt certificates.\n";
                        print "Use an official hostname, publicly accessible, instead.\n";
                        next outer;
                    }
                }
                foreach my $oldSite ( values %$oldSites ) {
                    if( $oldSite->hostname eq $hostname ) {
                        if( $dryRun ) {
                            print "There is already a site with hostname $hostname. You will not be able to deploy the site you are creating on this device.\n";
                        } else {
                            print "There is already a site with hostname $hostname.\n";
                            next outer;
                        }
                    }
                }
            }
            last;
        }
    }

    my $siteId        = UBOS::Host::createNewSiteId();
    my $adminUserId   = ask( 'Site admin user id (e.g. admin): ', '^[a-z0-9]+$' );
    my $adminUserName = ask( 'Site admin user name (e.g. John Doe): ', '\S+' );
    my $adminCredential;
    my $adminEmail;

    while( 1 ) {
        while( 1 ) {
            $adminCredential = ask( 'Site admin user password (e.g. s3cr3t): ', '^\S[\S ]{4,30}\S$', undef, 1 );
            if( $adminCredential =~ m!s3cr3t!i ) {
                print "Not that one!\n";
            } elsif( $adminCredential eq $adminUserId ) {
                print "Password must be different from username.\n";
            } elsif( length( $adminCredential ) < 6 ) {
                print "At least 6 characters please.\n";
            } else {
                last;
            }
        }
        my $adminCredential2 = ask( 'Repeat site admin user password: ', undef, undef, 1 );
        if( $adminCredential ne $adminCredential2 ) {
            print "Passwords did not match!\n";
        } else {
            last;
        }
    }
    while( 1 ) {
        $adminEmail = ask( 'Site admin user e-mail (e.g. foo@bar.com): ', '^[a-z0-9._%+-]+@[a-z0-9.-]*[a-z]$' );
        if( $adminEmail =~ m!foo\@bar.com! ) {
            print "Not that one!\n";
        } else {
            last;
        }
    }

    my $tlsKey;
    my $tlsCrt;
    my $tlsCrtChain;
    my $tlsCaCrt;

    if( $tls ) {
        if( $letsEncrypt ) {
            # nothing here

        } elsif( $selfSigned ) {

            unless( $quiet ) {
                print "Generating TLS keys...\n";
            }

            my $tmpDir = UBOS::Host()->vars( 'host.tmp', '/tmp' );
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
                $tlsKey = ask( 'SSL/TLS private key file: ' );
                unless( $tlsKey ) {
                    redo;
                }
                unless( -r $tlsKey ) {
                    print "Cannot find or read file $tlsKey\n";
                    redo;
                }
                $tlsKey = UBOS::Utils::slurpFile( $tlsKey );
                unless( $tlsKey =~ m!^-----BEGIN RSA PRIVATE KEY-----.*-----END RSA PRIVATE KEY-----\s*$!s ) {
                    print "This file does not seem to contain a private key\n";
                    redo;
                }
                last;
            }

            while( 1 ) {
                $tlsCrt = ask( 'Certificate file (only domain cert, or entire chain): ' );
                unless( $tlsCrt ) {
                    redo;
                }
                unless( -r $tlsCrt ) {
                    print "Cannot find or read file $tlsCrt\n";
                    redo;
                }
                $tlsCrt = UBOS::Utils::slurpFile( $tlsCrt );
                unless( $tlsCrt =~ m!^-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\s*$!s ) {
                    print "This file does not seem to contain a certificate\n";
                    redo;
                }
                last;
            }

            while( 1 ) {
                $tlsCrtChain = ask( 'Certificate chain file (enter blank if chain was already contained in certificate file): ' );
                unless( $tlsCrtChain ) {
                    $tlsCrtChain = undef;
                    last;
                }
                unless( -r $tlsCrtChain ) {
                    print "Cannot find or read file $tlsCrtChain\n";
                    redo;
                }
                $tlsCrtChain = UBOS::Utils::slurpFile( $tlsCrtChain );
                unless( $tlsCrtChain =~ m!^-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\s*$!s ) {
                    print "This file does not seem to contain a certificate chain\n";
                    redo;
                }
                last;
            }

            while( 1 ) {
                $tlsCaCrt = ask( 'Client certificate chain file (or enter blank if none): ' );
                unless( $tlsCaCrt ) {
                    $tlsCaCrt = undef;
                    last;
                }
                unless( -r $tlsCaCrt ) {
                    print "Cannot find or read file $tlsCaCrt\n";
                    redo;
                }
                $tlsCaCrt = UBOS::Utils::slurpFile( $tlsCaCrt );
                unless( $tlsCaCrt =~ m!^-----BEGIN CERTIFICATE-----.*-----END CERTIFICATE-----\s*$!s ) {
                    print "This file does not seem to contain a certificate chain\n";
                    redo;
                }
                last;
            }
        }
    }

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

    unless( $quiet ) {
        print "** Now a few questions about the app(s) you are going to deploy to this site:\n";
    }

    my %contextPaths = ();
    my $counter = 'First';
    while( 1 ) {
        my $appId;
        while( 1 ) {
            $appId = ask( $counter . " app to run (or leave empty when no more apps): ", '^[-._a-z0-9]+$|^$' );
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

        my $context         = undef;
        my %accs            = (); # map name->Accessory
        my $custPointValues = {};

        my $defaultContext = $app->defaultContext;
        my $fixedContext   = $app->fixedContext;
        if( defined( $defaultContext )) {
            print "App $appId suggests context path " . ( $defaultContext ? $defaultContext : '<empty string> (i.e. root of site)' ) . "\n";
            while( 1 ) {
                $context = ask( 'Enter context path: ' );

                if( !UBOS::AppConfiguration::isValidContext( $context )) {
                    print "Invalid context path. A valid context path is either empty or starts with a slash; no spaces or additional slashes\n";
                } elsif( $context eq '' && keys %contextPaths > 0 ) {
                    print "Cannot put an app at the root context path if there is another app at the same site\n";
                } elsif( exists( $contextPaths{$context} )) {
                    print "There is already an app at this context path\n";
                } else {
                    $contextPaths{$context} = $context;
                    last;
                } # we abort the loop as soon as there's an app at the root context
            }
        } elsif( defined( $fixedContext )) {
            if( exists( $contextPaths{$fixedContext} )) {
                print "App $appId has an unchangeable context path of $fixedContext, but another app is already at this path. Cannot install here.\n";
                next;
            } elsif( '' eq $fixedContext && keys %contextPaths > 0 ) {
                print "App $appId must be installed at the root of the site. This means no other app can run at this site, but at least one is here already.\n";
                next;
            }
            $context = $fixedContext;
        }

        while( 1 ) {
            my $askUserAgain = 0;
            my $accessories = ask( "Any accessories for $appId? Enter list: " );
            $accessories =~ s!^\s+!!;
            $accessories =~ s!\s+$!!;

            my %currentAccs;
            map { $currentAccs{$_} = $_ } split( /\s+,?\s*/, $accessories );
            while( %currentAccs && !$askUserAgain ) {
                # accessories can require other accessories, and so forth
                my %nextAccs;

                my @currentAccList = keys %currentAccs;
                if( UBOS::Host::ensurePackages( \@currentAccList, $quiet ) >= 0 ) {
                    foreach my $currentAccId ( @currentAccList ) {
                        my $acc = UBOS::Accessory->new( $currentAccId );

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

        foreach my $installable ( $app, values %accs ) {
            my $custPoints = $installable->customizationPoints;
            if( $custPoints ) {
                my $knownCustomizationPointTypes = $UBOS::Installable::knownCustomizationPointTypes;
                my @sortedCustPointNames         = _sortCustomizationPoints( $custPoints );

                foreach my $custPointName ( @sortedCustPointNames ) {
                    my $custPointDef = $custPoints->{$custPointName};

                    if( !$askAll && !$custPointDef->{required} ) {
                        next;
                    }
                    my $isFile = $UBOS::Installable::knownCustomizationPointTypes->{$custPointDef->{type}}->{isFile};
                    while( 1 ) {
                        my $blank =    ( 'password' eq $custPointDef->{type} )
                                    || ( exists( $custPointDef->{private} ) && $custPointDef->{private} );

                        my $value = ask(
                                (( $installable == $app ) ? 'App ' : 'Accessory ' )
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

    my $ret = 1;
    if( $out ) {
        UBOS::Utils::writeJsonToFile( $out, $newSiteJson );

    } elsif( $dryRun ) {
        print UBOS::Utils::writeJsonToString( $newSiteJson );

    }
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
            $newAppConfig->checkCustomizationPointValues();
        }

        $newSite->checkDeployable();

        unless( $quiet ) {
            print "Deploying...\n";
        }

        # May not be interrupted, bad things may happen if it is
        UBOS::Host::preventInterruptions();

        info( 'Setting up placeholder sites' );

        my $suspendTriggers = {};
        debugAndSuspend( 'Setting up placeholder for site', $newSite->siteId() );
        $ret &= $newSite->setupPlaceholder( $suspendTriggers ); # show "coming soon"

        debugAndSuspend( 'Execute triggers', keys %$suspendTriggers );
        UBOS::Host::executeTriggers( $suspendTriggers );

        if( $newSite->hasLetsEncryptTls() && !$newSite->hasLetsEncryptCerts()) {
            info( 'Obtaining letsencrypt certificate' );
            debugAndSuspend();

            my $success = $newSite->obtainLetsEncryptCertificate();
            unless( $success ) {
                $newSite->unsetLetsEncryptTls;
                $tls = 0;
            }
            # proceed anyway, so don't set $ret
        }

        my $deployUndeployTriggers = {};
        debugAndSuspend( 'Deploy site', $newSite->siteId() );
        $ret &= $newSite->deploy( $deployUndeployTriggers );

        UBOS::Networking::NetConfigUtils::updateOpenPorts();

        debugAndSuspend( 'Execute triggers', keys %$deployUndeployTriggers );
        UBOS::Host::executeTriggers( $deployUndeployTriggers );

        info( 'Resuming sites' );

        my $resumeTriggers = {};
        debugAndSuspend( 'Resume site', $newSite->siteId() );
        $ret &= $newSite->resume( $resumeTriggers ); # remove "upgrade in progress page"
        debugAndSuspend( 'Execute triggers', keys %$resumeTriggers );
        UBOS::Host::executeTriggers( $resumeTriggers );

        info( 'Running installers' );
        # no need to run any upgraders

        foreach my $appConfig ( @{$newSite->appConfigs} ) {
            $ret &= $appConfig->runInstallers();
        }

        if( $out ) {
            # Need to be at the end, so tor info has been inserted
            UBOS::Utils::writeJsonToFile( $out, $newSiteJson );
        }

        if( $ret ) {
            $hostname = $newSite->hostname(); # tor site might have generated the hostname
            if( $tls ) {
                print "Installed site $siteId at https://$hostname/\n";
            } else {
                print "Installed site $siteId at http://$hostname/\n";
            }
        } else {
            error( "Createsite failed." );
        }
    }
    return $ret;
}

##
# Ask the user a question
# $q: the question text
# $regex: regular expression that defines valid input
# $dontTrim: if false, trim whitespace
# $blank: if true, blank terminal echo
sub ask {
    my $q        = shift;
    my $regex    = shift || '.?';
    my $dontTrim = shift || 0;
    my $blank    = shift;

    my $ret;
    while( 1 ) {
        print $q;

        if( $blank ) {
            system('stty','-echo');
        }
        $ret = <STDIN>;
        if( $blank ) {
            system('stty','echo');
            print "\n";
        }
        if( defined( $ret )) { # apparently ^D becomes undef
            unless( $dontTrim ) {
                $ret =~ s!\s+$!!;
                $ret =~ s!^\s+!!;
            }
            if( $ret =~ $regex ) {
                last;
            } else {
                print "(input not valid: regex is $regex)\n";
            }
        }
    }
    return $ret;
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
