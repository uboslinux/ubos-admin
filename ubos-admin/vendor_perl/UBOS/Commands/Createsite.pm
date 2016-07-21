#!/usr/bin/perl
#
# Command that asks the user about the site they want to create, and
# then deploys the site.
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
# return: desired exit code
sub run {
    my $cmd  = shift;
    my @args = @_;

    my $askAll        = 0;
    my $tls           = 0;
    my $selfSigned    = 0;
    my $letsEncrypt   = 0;
    my $out           = undef;
    my $verbose       = 0;
    my $quiet         = 0;
    my $logConfigFile = undef;
    my $dryRun;

    my $parseOk = GetOptionsFromArray(
            \@args,
            'askForAllCustomizationPoints' => \$askAll,
            'tls'                          => \$tls,
            'selfsigned'                   => \$selfSigned,
            'letsencrypt'                  => \$letsEncrypt,
            'out=s',                       => \$out,
            'verbose+'                     => \$verbose,
            'quiet',                       => \$quiet,
            'logConfig=s'                  => \$logConfigFile,
            'dry-run|n'                    => \$dryRun );

    UBOS::Logging::initialize( 'ubos-admin', $cmd, $verbose, $logConfigFile );
    info( 'ubos-admin', $cmd, @_ );

    if(    !$parseOk
        || @args
        || ( $verbose && $logConfigFile )
        || ( $selfSigned && !$tls )
        || ( $letsEncrypt && !$tls )
        || ( $selfSigned && $letsEncrypt ))
    {
        fatal( 'Invalid invocation:', $cmd, @_, '(add --help for help)' );
    }

    if( !$dryRun && $< != 0 ) {
        fatal( "This command must be run as root" ); 
    }

    my $oldSites = UBOS::Host::sites();

    unless( $quiet ) {
        print "** First a few questions about the website that you are about to create:\n";
    }
    if( keys %$oldSites == 1 && '*' eq (( values %$oldSites )[0])->hostname ) {
        if( $dryRun ) {
            print "WARNING: There is already a site with hostname * (any). You will not be able to deploy the site you are creating on this device.\n";
        } else {
            fatal( 'There is already a site with hostname * (any), so no other site can be created.' );
        }
    }

    my $hostname = undef;
    outer: while( 1 ) {
        $hostname = ask( "Hostname (or * for any): ", '^[a-z0-9]([-_a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-_a-z0-9]*[a-z0-9])?)*$|^\*$' );

        if( '*' eq $hostname ) {
            if( %$oldSites ) {
                if( $dryRun ) {
                    print "WARNING: There is already a site with hostname * (any). You will not be able to deploy the site you are creating on this device.\n";
                } else {
                    print "You can only create a site with hostname * (any) if no other sites exist.\n";
                    next outer;
                }
            }
        } else {
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

    my $siteId        = UBOS::Host::createNewSiteId();
    my $adminUserId   = ask( 'Site admin user id (e.g. admin): ', '^[a-z0-9]+$' );
    my $adminUserName = ask( 'Site admin user name (e.g. John Doe): ' );
    my $adminCredential;
    my $adminEmail;

    while( 1 ) {
        $adminCredential = ask( 'Site admin user password (e.g. s3cr3t): ', '^[\S ]+$', undef, 1 );
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

            my $dir = File::Temp->newdir();
            chmod 0700, $dir;
    
            my $err;
            if( UBOS::Utils::myexec( "openssl genrsa -out '$dir/key' 4096 ", undef, undef, \$err )) {
                fatal( 'openssl genrsa failed', $err );
            }
            if( UBOS::Utils::myexec( "openssl req -new -key '$dir/key' -out '$dir/csr' -batch", undef, undef, \$err )) {
                fatal( 'openssl req failed', $err );
            }
            if( UBOS::Utils::myexec( "openssl x509 -req -days 3650 -in '$dir/csr' -signkey '$dir/key' -out '$dir/crt'", undef, undef, \$err )) {
                fatal( 'openssl x509 failed', $err );
            }
            $tlsKey = UBOS::Utils::slurpFile( "$dir/key" );
            $tlsCrt = UBOS::Utils::slurpFile( "$dir/crt" );

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
                $tlsCrt = ask( 'Certificate file: ' );
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
                $tlsCrtChain = ask( 'Certificate chain file: ' );
                unless( $tlsCrtChain ) {
                    redo;
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
    $newSiteJson->{siteid}   = $siteId;
    $newSiteJson->{hostname} = $hostname;

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
        }
        if( $tlsCrtChain ) {
            $newSiteJson->{tls}->{crtchain} = $tlsCrtChain;
        }
        if( $tlsCaCrt ) {
            $newSiteJson->{tls}->{cacrt} = $tlsCaCrt;
        }
    }

    unless( $quiet ) {
        print "** Now a few questions about the app(s) you are going to deploy to this site:\n";
    }

    my %contextPaths = ();
    my $counter = 'First';
    while( 1 ) {
        my $appId = ask( $counter . " app to run (or leave empty when no more apps): ", '^[-._a-z0-9]+$|^$' );
        unless( $appId ) {
            last;
        }

        UBOS::Host::ensurePackages( $appId, $quiet );

        my $app = UBOS::App->new( $appId );

        my $context         = undef;
        my @accs            = ();
        my $custPointValues = {};

        my $defaultContext = $app->defaultContext;
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
        }

        my $accessories = ask( "Any accessories for $appId? Enter list: " );
        $accessories =~ s!^\s+!!;
        $accessories =~ s!\s+$!!;
        my @accList = split( /\s+,?\s*/, $accessories );
        if( @accList ) {
            UBOS::Host::ensurePackages( \@accList, $quiet );

            foreach my $accId ( @accList ) {
                my $acc = UBOS::Accessory->new( $accId );

                push @accs, $acc;
            }
        }

        foreach my $installable ( $app, @accs ) {
            my $custPoints = $installable->customizationPoints;
            if( $custPoints ) {
                my $knownCustomizationPointTypes = $UBOS::Installable::knownCustomizationPointTypes;
                my @sortedCustPointNames         = _sortCustomizationPoints( $custPoints );

                foreach my $custPointName ( @sortedCustPointNames ) {
                    my $custPointDef = $custPoints->{$custPointName};

                    if( !$askAll && !$custPointDef->{required} ) {
                        next;
                    }
                    unless( $UBOS::Installable::knownCustomizationPointTypes->{$custPointDef->{type}}->{ask} ) {
                        next; # can't ask for things that cannot be entered at the keyboard
                    }
                    my $value = ask(
                            (( $installable == $app ) ? 'App ' : 'Accessory ' )
                            . $installable->packageName
                            . ( $askAll ? ' supports' : ' requires' )
                            . " a value for $custPointName: " );

                    my $custPointValidation = $knownCustomizationPointTypes->{ $custPointDef->{type}};
                    unless( $custPointValidation->{valuecheck}->( $value )) {
                        fatal( $custPointValidation->{valuecheckerror} );
                    }
                    $custPointValues->{$installable->packageName}->{$custPointName}->{value} = $value;
                }
            }
        }
        
        my $appConfigJson = {};
        $appConfigJson->{appconfigid} = UBOS::Host::createNewAppConfigId();
        $appConfigJson->{appid}       = $appId;
        
        if( defined( $context )) {
            $appConfigJson->{context} = $context;
        }
        if( @accs ) {
            $appConfigJson->{accessories} = [];
            map { push @{$appConfigJson->{accessoryids}}, $_->packageName; } @accs;
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
    if( $dryRun ) {
        if( $out ) {
            UBOS::Utils::writeJsonToFile( $out, $newSiteJson );
        } else {
            print UBOS::Utils::writeJsonToString( $newSiteJson );
        }

    } else {
        if( $out ) {
            UBOS::Utils::writeJsonToFile( $out, $newSiteJson );
        }

        my $newSite = UBOS::Site->new( $newSiteJson );

        my $prerequisites = {};
        $newSite->addDependenciesToPrerequisites( $prerequisites );
        UBOS::Host::ensurePackages( $prerequisites, $quiet );

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
        $ret &= $newSite->setupPlaceholder( $suspendTriggers ); # show "coming soon"
        UBOS::Host::executeTriggers( $suspendTriggers );

        if( $newSite->hasLetsEncryptTls() && !$newSite->hasLetsEncryptCerts()) {
            info( 'Obtaining letsencrypt certificate' );

            my $success = $newSite->obtainLetsEncryptCertificate();
            unless( $success ) {
                warning( 'Failed to obtain letsencrypt certificate for site', $newSite->hostname, '(', $newSite->siteId, '). Deploying site without TLS.' );
                $newSite->unsetLetsEncryptTls;
            }
            $ret &= $success;
        }

        my $deployUndeployTriggers = {};
        $ret &= $newSite->deploy( $deployUndeployTriggers );
        UBOS::Host::executeTriggers( $deployUndeployTriggers );

        info( 'Resuming sites' );

        my $resumeTriggers = {};
        $ret &= $newSite->resume( $resumeTriggers ); # remove "upgrade in progress page"
        UBOS::Host::executeTriggers( $resumeTriggers );

        info( 'Running installers' );
        # no need to run any upgraders

        foreach my $appConfig ( @{$newSite->appConfigs} ) {
            $ret &= $appConfig->runInstaller();
        }

        if( $ret ) {
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
        <<SSS => <<HHH,
    [--verbose | --logConfig <file>] [--quiet] [--askForAllCustomizationPoints] [--tls [--selfsigned | --letsencrypt]] [--out <file>]
SSS
    Interactively define and install a new site that runs any number of apps.
    If --tls is provided, the site will be secured with SSL. If additionally
    --selfsigned is provided, a self-signed certificate is automatically set
    up. If additionally --letsencrypt is provided, letsencrypt.org will be
    used to automatically setup a certificate; otherwise, keys and certificates
    need to be entered manually.
    If --out is provided, also save the created Site JSON to a file. Adding
    --quiet will skip progress messages.
HHH
        <<SSS => <<HHH
    [--verbose | --logConfig <file>] [--quiet] [--askForAllCustomizationPoints] [--tls [--selfsigned | --letsencrypt]] [--out <file>] ( --dry-run | -n )
SSS
    Interactively define a new site, but instead of installing,
    print the Site JSON file for the site, which then can be deployed
    using 'ubos-admin deploy'.
    If --tls is provided, the site will be secured with SSL. If additionally
    --selfsigned is provided, a self-signed certificate is automatically set
    up. If additionally --letsencrypt is provided, letsencrypt.org will be
    used to automatically setup a certificate; otherwise, keys and certificates
    need to be entered manually.
    If --out is provided, the created Site JSON will be saved to a file instead
    of writing it to stdout. Adding --quiet will skip progress messages.
HHH
    };
}

1;
