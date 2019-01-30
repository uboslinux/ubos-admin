#!/usr/bin/perl
#
# Superclass of all installable items e.g. Apps, Accessories.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Installable;

use fields qw(json packageName atAppConfigVarsAtCheck atAppConfigVars );

use UBOS::Host;
use UBOS::Logging;
use UBOS::Utils qw( readJsonFromFile );
use JSON;
use MIME::Base64;

##
# The known customization point types, validation routines, and error messages.
# valuecheck returns two values:
#  1. a boolean (ok or not)
#  2. a cleaned-up version of the value
our $knownCustomizationPointTypes = {
    'string' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift;

            my $ok = !ref( $v ) && $v !~ /\n/;
            # Don't check regex here: error reporting becomes difficult
            return ( $ok, $v );
        },
        'valuecheckerror' => 'string value without newlines required',
        'isFile' => 0
    },
    'email' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            my $ok = !ref( $v ) && $v =~ /^[A-Z0-9._%+-]+@[A-Z0-9.-]*[A-Z]$/i;
            return ( $ok, $v );
        },
        'valuecheckerror' => 'valid e-mail address required',
        'isFile' => 0
    },
    'url' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            my $ok = !ref( $v ) && $v =~ m!^https?://\S+$!;
            return ( $ok, $v );
        },
        'valuecheckerror' => 'valid http or https URL required',
        'isFile' => 0
    },
    'text' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            my $ok = !ref( $v );
            return ( $ok, $v );
        },
        'valuecheckerror' => 'name of a readable file required',
        'isFile' => 1
    },
    'password' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            my $ok = !ref( $v ) && $v =~ /^\S{4,}$/;
            return ( $ok, $v );
        },
        'valuecheckerror' => 'value must be at least four characters long and not contain white space',
        'isFile' => 0
    },
    'boolean' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            if( ref( $v ) =~ m/^JSON.*[Bb]oolean$/ ) {
                return ( 1, $v ? JSON::true : JSON::false );
            } elsif( ref( $v )) {
                return ( 0, $v );
            } elsif( $v eq 'true' ) {
                return ( 1, JSON::true );
            } elsif( $v eq 'false' ) {
                return ( 1, JSON::false );
            } elsif( $v eq '1' ) {
                return ( 1, JSON::true );
            } elsif( $v eq '0' ) {
                return ( 1, JSON::false );
            } else {
                return ( 0, $v );
            }
        },
        'valuecheckerror' => 'value must be true or false',
        'isFile' => 0
    },
    'integer' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            my $ok = !ref( $v ) && $v =~ /^-?[0-9]+$/;
            return ( $ok, $v );
        },
        'valuecheckerror' => 'value must be a whole number',
        'isFile' => 0
    },
    'positiveinteger' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            my $ok = !ref( $v ) && $v =~ /^[1-9][0-9]*$/;
            return ( $ok, $v );
        },
        'valuecheckerror' => 'value must be a positive, whole number',
        'isFile' => 0
    },
    'positiveintegerorzero' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            my $ok = !ref( $v ) && $v =~ /^[0-9]+$/;
            return ( $ok, $v );
        },
        'valuecheckerror' => 'value must be a positive, whole number or 0',
        'isFile' => 0
    },
    'image' => {
        'valuecheck' => sub {
            my $v             = shift;
            my $custPointJson = shift; # ignored

            return ( 1, $v ); # don't really know
        },
        'valuecheckerror' => 'name of a readable image file required',
        'isFile' => 1
    }
};

##
# Constructor.
# $packageName: unique identifier of the package
# $manifestFileReader: pointer to a method that knows how to read the manifest file
sub new {
    my $self               = shift;
    my $packageName        = shift;
    my $manifestFileReader = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }

    my $json = $manifestFileReader->( $packageName );
    unless( $json ) {
        return undef;
    }

    $self->{json}                   = $json;
    $self->{packageName}            = $packageName;
    $self->{atAppConfigVars}        = {};
    $self->{atAppConfigVarsAtCheck} = {};

    return $self;
}

##
# Obtain a Variables object for this Installable at a particular AppConfiguration.
# $appConfig: the AppConfiguration
# $doIt: if 1, deploy; if 0, only check. We keep two separate Variables objects
#        around so placeholder values during check do not contaminate the deploy
# return: the Variables object
sub obtainInstallableAtAppconfigVars {
    my $self      = shift;
    my $appConfig = shift;
    my $doIt      = shift;

    my $entry = $doIt ? 'atAppConfigVars' : 'atAppConfigVarsAtCheck';

    my $appConfigId = $appConfig->appConfigId();
    unless( exists( $self->{$entry}->{$appConfigId} )) {
        my $hierarchicalMap = $self->_createHierarchicalMapAtAppconfigVars( $appConfig );

        $self->{$entry}->{$appConfigId} = UBOS::Variables->new(
                $appConfig->vars()->name() . ",Installable=" . $self->packageName() . "($entry)",
                $hierarchicalMap,
                $appConfig );
    }
    return $self->{$entry}->{$appConfigId};
}

##
# Factored out creation of the hierarchical map for obtainInstallableAtAppconfigVars.
# This allows subclasses to add to it.
# $appConfig: the AppConfiguration
sub _createHierarchicalMapAtAppconfigVars {
    my $self      = shift;
    my $appConfig = shift;

    my $appConfigId     = $appConfig->appConfigId();
    my $packageName     = $self->packageName;
    my $hierarchicalMap = {
        "package" => {
            "name" => $packageName
        }
    };

    my $appConfigCustPoints = $appConfig->customizationPoints();
    my $appConfigParsDir    = $appConfig->vars()->getResolve( 'host.appconfigparsdir' );

    foreach my $custPointName ( keys %{$appConfigCustPoints->{$packageName}} ) {
        my $data = $appConfigCustPoints->{$packageName}->{$custPointName}->{value};

        my $installableCustPoints = $self->{json}->{customizationpoints}->{$custPointName};
        if( !exists( $installableCustPoints->{private} ) || !$installableCustPoints->{private} ) {
            # do not generate the file if customizationpoint is declared private
            my $filename = "$appConfigParsDir/$appConfigId/$packageName/$custPointName";
            $hierarchicalMap->{installable}->{customizationpoints}->{$custPointName}->{filename} = $filename;
        }
        $hierarchicalMap->{installable}->{customizationpoints}->{$custPointName}->{value} = $data;
    }
    return $hierarchicalMap;
}

##
# Determine the package name
# return: the package name
sub packageName {
    my $self = shift;

    return $self->{packageName};
}

##
# Determine the user-friendly name
# $locale: the locale
# return: user-friendly name
sub name {
    my $self   = shift;
    my $locale = shift;

    return $self->_l10nInfo( 'name', $locale, $self->packageName );
}

##
# Determine a user-friendly tagline
# locale: the locale
# return: user-friendly tagline, or undef
sub tagline {
    my $self   = shift;
    my $locale = shift;

    return $self->_l10nInfo( 'tagline', $locale );
}

##
# Obtain this Installable's JSON
# return: JSON
sub installableJson {
    my $self = shift;

    return $self->{json};
}

##
# Determine the customization points defined for this installable
# return: map from name to has as in application JSON, or undef
sub customizationPoints {
    my $self = shift;

    if( exists( $self->{json}->{customizationpoints} )) {
        return $self->{json}->{customizationpoints};
    } else {
        return undef;
    }
}

##
# Determine the role names that this Installable has information about
# return: array of role names
sub roleNames {
    my $self = shift;

    my $rolesJson = $self->{json}->{roles};
    if( $rolesJson ) {
        my @roleNames = keys %$rolesJson;
        return \@roleNames;
    } else {
        return [];
    }
}

##
# Determine the JSON AppConfigurationItems in the role with this name
# $roleName: name of the role
# return: array of JSON AppConfigurationItems
sub appConfigItemsInRole {
    my $self     = shift;
    my $roleName = shift;

    my $ret = $self->{json}->{roles}->{$roleName}->{appconfigitems};
    return $ret;
}

##
# Determine whether this Installable needs a particular role
# $role: the role to check for
# return: true or false
sub needsRole {
    my $self = shift;
    my $role = shift;

    my $ret = $self->{json}->{roles}->{$role->name()};
    return $ret ? 1 : 0;
}

##
# Determine the set of other installables that must also be deployed at the
# same AppConfiguration.
# return: array (usually empty)
sub requires {
    my $self = shift;

    return ();
}

##
# Helper method to find a localized attribute in the info section
# $att: name of the attribute in the info section
# $locale: the locale
# $default: the default to return, if otherwise not found
# return: value of the attribute
sub _l10nInfo {
    my $self    = shift;
    my $att     = shift;
    my $locale  = shift;
    my $default = shift;

    if( defined( $self->{json}->{info} )) {
        my $info = $self->{json}->{info};
        my @keys = _localeToKeys( $locale );

        foreach my $key ( @keys ) {
            if( defined( $info->{$key}->{$att} )) {
                return $info->{$key}->{$att};
            }
        }
    }
    return $default;
}

##
# Helper method to split a locale string into keys to try in sequence
# $locale: the locale string, e.g. en_US
# return: array of keys to try, e.g. ( 'en_US', 'en', 'default' )
sub _localeToKeys {
    my $locale = shift;

    my @ret = ();
    if( $locale ) {
        push @ret, $locale;

        if( $locale =~ m!(.*)_(.*)! ) {
            push @ret, $1;
        }
    }
    push @ret, 'default';
    return @ret;
}

# === Manifest checking routines from here ===

##
# Check validity of the manifest JSON.
# $type: the required value of the type field
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# return: 1 or exits with myFatal error
sub checkManifest {
    my $self                 = shift;
    my $type                 = shift;
    my $skipFilesystemChecks = shift;

    trace( 'Checking manifest for', $self->packageName );

    my $packageName = $self->packageName();
    my $vars = UBOS::Variables->new(
            "Installable=$packageName(Manifest-check)",
            {
                'package' => {
                    'name' => $packageName
                }
            },
            'UBOS::Host' );

    $self->checkManifestStructure( $vars, $skipFilesystemChecks );

    my $json = $self->{json};
    unless( $json->{type} eq $type ) {
        $self->myFatal( 'type must be', $type, 'is:', $json->{type} );
    }

    $self->checkManifestRolesSection( $vars, $skipFilesystemChecks );
    $self->checkManifestCustomizationPointsSection( $vars, $skipFilesystemChecks );
}

##
# Check validity of the manifest JSON's structure.
# $vars: the Variables object to check with
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# return: 1 or exits with fatal error
sub checkManifestStructure {
    my $self                 = shift;
    my $vars                 = shift;
    my $skipFilesystemChecks = shift;

    my $json = $self->{json};

    unless( $json ) {
        fatal( 'No manifest JSON present' );
    }
    unless( ref( $json ) eq 'HASH' ) {
        fatal( 'Manifest JSON must be a JSON hash' );
    }
    unless( $json->{type} ) {
        fatal( 'Manifest JSON: type: missing' );
    }
}

##
# Check validity of the manifest JSON's roles section.
# $vars: the Variables object to check with
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# return: 1 or exits with fatal error
sub checkManifestRolesSection {
    my $self                 = shift;
    my $vars                 = shift;
    my $skipFilesystemChecks = shift;

    my $json = $self->{json};

    if( $json->{roles} ) {
        my $rolesOnHost = UBOS::Host::rolesOnHost();
        my $retentionBuckets = {};

        foreach my $roleName ( keys %{$json->{roles}} ) {
            my $roleJson = $json->{roles}->{$roleName};

            my $role = $rolesOnHost->{$roleName};
            if( $role ) {
                $role->checkAppManifestForRole( $roleName, $self, $roleJson, $retentionBuckets, $skipFilesystemChecks, $vars );
            } # else we ignore roles we don't know
        }
    }
}

##
# Check validity of the manifest JSON's info section.
# $vars: the Variables object to check with
# $skipFilesystemChecks: if true, do not check the Site or Installable JSONs against the filesystem.
#       This is needed when reading Site JSON files in (old) backups
# return: 1 or exits with fatal error
sub checkManifestCustomizationPointsSection {
    my $self                 = shift;
    my $vars                 = shift;
    my $skipFilesystemChecks = shift;

    my $json = $self->{json};

    if( exists( $json->{customizationpoints} )) {
        unless( ref( $json->{customizationpoints} ) eq 'HASH' ) {
            $self->myFatal( "customizationpoints section: not a JSON object" );
        }
        foreach my $custPointName ( keys %{$json->{customizationpoints}} ) {
            my $custPointJson = $json->{customizationpoints}->{$custPointName};

            unless( $custPointName =~ m/^[a-z][_a-z0-9]*$/ ) {
                $self->myFatal( "customizationpoints section: invalid customizationpoint name: $custPointName" );
            }
            unless( ref( $custPointJson ) eq 'HASH' ) {
                $self->myFatal( "customizationpoints section: customizationpoint $custPointName: not a JSON object" );
            }
            unless( $custPointJson->{type} ) {
                $self->myFatal( "customizationpoints section: customizationpoint $custPointName: no type provided" );
            }
            if( ref( $custPointJson->{type} )) {
                $self->myFatal( "customizationpoints section: customizationpoint $custPointName: field 'type' must be string" );
            }
            my $custPointValidation = $knownCustomizationPointTypes->{ $custPointJson->{type}};
            unless( ref( $custPointValidation )) {
                $self->myFatal( "customizationpoints section: customizationpoint $custPointName: unknown type: " . $custPointJson->{type} );
            }
            if( defined( $custPointJson->{regex} )) {
                if( $custPointJson->{type} ne 'string' && $custPointJson->{type} ne 'password' ) {
                    $self->myFatal( "customizationpoints section: customizationpoint $custPointName: only string and password types may have a regex" );
                }
            }
            unless( defined( $custPointJson->{required} ) ) {
                $self->myFatal( "customizationpoints section: customizationpoint $custPointName: field 'required' must be given" );
            }
            unless( JSON::is_bool( $custPointJson->{required} )) {
                $self->myFatal( "customizationpoints section: customizationpoint $custPointName: field 'required' must be boolean" );
            }
            unless( $custPointJson->{required} ) {
                unless( defined( $custPointJson->{default} )) {
                    $self->myFatal( "customizationpoints section: customizationpoint $custPointName: a default value must be given if required=false" );
                }
                unless( ref( $custPointJson->{default} ) eq 'HASH' ) {
                    $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: not a JSON object" );
                }
                if( exists( $custPointJson->{default}->{value} )) {
                    if( ref( $custPointJson->{default}->{value} ) && 'JSON::PP::Boolean' ne ref( $custPointJson->{default}->{value} )) {
                        $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: no complex value permitted" );
                    }
                    if( $custPointValidation ) {
                        my( $ok, $cleanedValue ) = $custPointValidation->{valuecheck}->( $custPointJson->{default}->{value}, $custPointJson );
                        unless( $ok ) {
                            $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: field 'value': " . $custPointValidation->{valuecheckerror} );
                        }
                    }
                    if( $custPointJson->{default}->{encoding} ) {
                        if( ref( $custPointJson->{default}->{encoding} )) {
                            $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: field 'encoding' must be string" );
                        }
                        if( $custPointJson->{default}->{encoding} ne 'base64' ) {
                            $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: unknown encoding" );
                        }
                    }
                    if( defined( $custPointJson->{default}->{expression} )) {
                        $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: either specify value or expression, not both" );
                    }
                } elsif( defined( $custPointJson->{default}->{expression} )) {
                    if( ref( $custPointJson->{default}->{expression} )) {
                        $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: no complex value permitted for expression" );
                    }
                    if( defined( $custPointJson->{default}->{encoding} )) {
                        $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: if expression is given, do not specify encoding" );
                    }
                } else {
                    $self->myFatal( "customizationpoints section: customizationpoint $custPointName: default: must provide either value or expression" );
                }
            }
        }
    }
}

##
#
##
# Check whether a filename (which may be absolute or relative) refers to a valid file
# $filenameContext: if the filename is relative, this specifies the absolute path it is relative to
# $filename: the absolute or relative filename
# $name: the name
# return: 1 if valid
sub validFilename {
    my $filenameContext = shift;
    my $filename        = shift;
    my $name            = shift;

    my $testFile;
    if( $filename =~ m!^/! ) {
        # is absolute filename
        $testFile = $filename;
    } else {
        $testFile = "$filenameContext/$filename";
    }

    if( $name ) {
        my $localName  = $name;
        $localName =~ s!^.+/!!;

        $testFile =~ s!\$1!$name!g;      # $1: name
        $testFile =~ s!\$2!$localName!g; # $2: just the name without directories
    }

    unless( -e $testFile ) {
        fatal( 'Manifest refers to a file, but file cannot be found:', $testFile );
    }

    return 1; # FIXME
}

##
# Emit customized error message.
# @message: the message, perhaps in several parts
sub myFatal {
    my $self    = shift;
    my @message = @_;

    fatal( "Manifest JSON for package", $self->packageName, ':', @message );
}

##
# Determine whether this is a valid package name.
# $packageName: the package name
# return: 0 or 1
sub isValidPackageName {
    my $packageName = shift;

    unless( defined( $packageName )) {
        return 0;
    }
    if( ref( $packageName )) {
        return 0;
    }
    unless( $packageName =~ m!^[-a-z0-9_.]+$! ) {
        return 0;
    }
    return 1;
}

1;
