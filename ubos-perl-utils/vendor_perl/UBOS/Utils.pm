#!/usr/bin/perl
#
# Collection of utility methods.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::Utils;

use Cwd qw( abs_path );
use Exporter qw( import );
use File::Spec;
use File::Temp;
use Net::Ping;
use JSON;
use Lchown;
use POSIX;
use Time::Local qw( timegm );
use UBOS::Logging;

our @EXPORT = qw( readJsonFromFile readJsonFromStdin readJsonFromString
                  writeJsonToFile writeJsonToStdout writeJsonToString
                  myexec saveFile slurpFile );
my $jsonParser = JSON->new->relaxed->pretty->allow_nonref->utf8();

my $PACMAN_CONF_SEP      = '### DO NOT EDIT ANYTHING BELOW THIS LINE, UBOS WILL OVERWRITE ###';
my $CHANNEL_FILE         = '/etc/ubos/channel';
my $SKU_FILE             = '/etc/ubos/product';
my @VALID_CHANNELS       = qw( dev red yellow green );
my @VALID_ARCHS          = qw( x86_64 armv6h armv7h aarch64 );
my @VALID_DEVICE_CLASSES = qw( pc vbox ec2 rpi rpi2 rpi4 espressobin odroid-xu3 container docker );

my $_now           = time(); # Time the script(s) started running, use now() to access
my $_deviceClass   = undef;  # Allocated as needed
my $_osReleaseInfo = undef;  # Allocated as needed

##
# Obtain the UNIX system time when the script(s) started running.
# return: the UNIX system time
sub now {
    return $_now;
}

##
# Read and parse JSON from a file
# $from: file to read from
# $cannotParseFileErrorFunc: invoke this function when an error occurs parsing the file
# $cannotReadFileErrorFunc: invoke this function when an error occurs reading the file
# $msg: if an error occurs, use this error message
# return: JSON object
sub readJsonFromFile {
    my $file = shift;
    my $cannotParseFileErrorFunc = shift || sub { error( 'JSON parsing error in file', shift ); };
    my $cannotReadFileErrorFunc  = shift || sub { error( 'Cannot read file:', shift ); };

    my $fileContent = slurpFile( $file, $cannotReadFileErrorFunc );
    unless( $fileContent ) {
        return undef;
    }

    my $json;
    eval {
        $json = $jsonParser->decode( $fileContent );
    } or $cannotParseFileErrorFunc->( $@ );

    return $json;
}

##
# Read and parse JSON from STDIN
# return: JSON object
# $msg: if an error occurs, use this error message
sub readJsonFromStdin {
    my $msg  = shift || 'JSON parsing error from <stdin>';

    local $/;
    my $fileContent = <STDIN>;

    my $json;
    eval {
        $json = $jsonParser->decode( $fileContent );
    } or error( $msg, ':', $@ );

    return $json;
}

##
# Read and parse JSON from String
# $string: the JSON string
# $msg: if an error occurs, use this error message
# return: JSON object
sub readJsonFromString {
    my $string = shift;
    my $msg    = shift || 'JSON parsing error';

    my $json;
    eval {
        $json = $jsonParser->decode( $string );
    } or error( $msg, ':', $@ );

    return $json;
}

##
# Write a JSON file.
# $filename: the name of the file to create/write
# $json: the JSON object to write
# $mask: permissions on the file
# $uname: owner of the file
# $gname: group of the file
# return: 1 if successful
sub writeJsonToFile {
    my $fileName = shift;
    my $json     = shift;
    my $mask     = shift;
    my $uname    = shift;
    my $gname    = shift;

    saveFile( $fileName, $jsonParser->encode( $json ), $mask, $uname, $gname );
}

##
# Write JSON to STDOUT
# $json: the JSON object to write
sub writeJsonToStdout {
    my $json = shift;

    print $jsonParser->encode( $json );
}

##
# Write JSON to string
# $json: the JSON object to write
sub writeJsonToString {
    my $json = shift;

    return $jsonParser->encode( $json );
}

##
# Replace all string values in JSON that start with @ with the content of the
# file whose filename is the remainder of the value.
# $json: the JSON that may contain @-values
# $dir: the directory to which relative paths are relative to
sub insertSlurpedFiles {
    my $json = shift;
    my $dir  = shift;
    my $ret;

    if( ref( $json ) eq 'ARRAY' ) {
        $ret = [];
        foreach my $item ( @$json ) {
            push @$ret, insertSlurpedFiles( $item, $dir );
        }

    } elsif( ref( $json ) eq 'HASH' ) {
        $ret = {};
        foreach my $name ( keys %$json ) {
            my $value = $json->{$name};

            $ret->{$name} = insertSlurpedFiles( $value, $dir );
        }

    } elsif( ref( $json ) ) {
        $ret = $json;

    } elsif( defined( $json )) {
        # string
        if( $json =~ m!^\@(/.*)$! ) {
            $ret = slurpFile( $1 );
        } elsif( $json =~ m!^\@(.*)$! ) {
            $ret = slurpFile( "$dir/$1" );
        } else {
            $ret = $json;
        }
    } else {
        $ret = undef;
    }
    return $ret;
}

##
# Execute a command, and optionally read/write standard stream to/from strings
# $cmd: the command
# $inContent: optional string containing what will be sent to stdin
# $outContentP: optional reference to variable into which stdout output will be written
# $errContentP: optional reference to variable into which stderr output will be written.
#               if this has the same non-null value as $outContentP, both streams will be
#               redirected together
# $tee: if true and outContentP and errContentP are the same, print to stdout as well as the variable
# return: value of the system() command: 0 generally indicates success
sub myexec {
    my $cmd         = shift;
    my $inContent   = shift;
    my $outContentP = shift;
    my $errContentP = shift;
    my $tee         = shift;

    my $inFile;
    my $outFile;
    my $errFile;

    $cmd = "( $cmd )"; # in case it is several commands

    if( $tee && ( !defined( $outContentP ) || $outContentP != $errContentP )) {
        $tee = 0;
    }
    if( $inContent ) {
        $inFile = File::Temp->new();
        print $inFile $inContent;
        close $inFile;

        $cmd .= " <" . $inFile->filename;
    }
    if( $tee ) {
        $outFile = File::Temp->new();
        $cmd = '( set -o pipefail; ' . $cmd . ' |& tee ' . $outFile->filename . ' )';
        # Otherwise we get tee's status code.

    } else {
        if( defined( $outContentP )) {
            $outFile = File::Temp->new();
            $cmd .= " >" . $outFile->filename;
        }
        if( defined( $errContentP )) {
            if( defined( $outContentP ) && $outContentP == $errContentP ) {
                $cmd .= " 2>&1";
                $errContentP = undef;
            } else {
                $errFile = File::Temp->new();
                $cmd .= " 2>" . $errFile->filename;
            }
        }
    }

    trace( 'Exec:', $cmd );

    system( $cmd );
    my $ret = $?;

    if( defined( $outContentP ) && defined( $outFile )) {
        ${$outContentP} = slurpFile( $outFile->filename );
    }
    if( defined( $errContentP ) && defined( $errFile )) {
        ${$errContentP} = slurpFile( $errFile->filename );
    }

    if( $ret == -1 || $ret & 127 ) {
        error( 'Failed to execute', $cmd, "(error code $ret):", $! );
    }
    return $ret;
}

##
# Slurp the content of a file
# $filename: the name of the file to read
# $cannotReadFileErrorFunc: invoke this function when an error occurs reading the file
# return: the content of the file
sub slurpFile {
    my $filename                = shift;
    my $cannotReadFileErrorFunc = shift || sub { error( 'Cannot read file:', shift ); };

    trace( 'slurpFile(', $filename, ')' );

    local $/;
    if( open( my $fh, '<', $filename )) {
        my $fileContent = <$fh>;
        close $fh;

        return $fileContent;

    } else {
        $cannotReadFileErrorFunc->( $filename );
        return undef;
    }
}

##
# Save content to a file. If the desired owner of the file is not the current
# user, this will write to a temp file, and then move the temp file in
# $filename: the name of the file to create/write
# $content: the content of the file
# $mask: permissions on the file
# $uname: owner of the file
# $gname: group of the file
# return: 1 if successful
sub saveFile {
    my $filename = shift;
    my $content  = shift;
    my $mask     = shift;
    my $uname    = shift;
    my $gname    = shift;

    unless( defined( $content )) {
        warning( 'Undefined content (usually programming error) when attempting to save file', $filename );
        $content = '';
    }

    my $uid = getUid( $uname );
    my $gid = getGid( $gname );

    unless( defined( $mask )) {
        $mask = 0644;
    }
    # more efficient if trace isn't on

    my $ret;
    if( $< == 0 || ( $uid == $< && $gid == $( )) {
        # This is faster -- for root, or for creating one's own files

        trace( sub { ( 'saveFile-as-root-or-owner(', $filename, length( $content ), 'bytes, mask', sprintf( "%o", $mask ), ', uid', $uid, ', gid', $gid, ')' ) } );
        unless( sysopen( F, $filename, O_CREAT | O_WRONLY | O_TRUNC )) {
            error( "Could not write to file $filename:", $! );
            return 0;
        }

        print F $content;
        close F;

        chmod $mask, $filename;

        if( $uid >= 0 || $gid >= 0 ) {
            chown $uid, $gid, $filename;
        }
        $ret = 1;

    } else {
        # Write to a temp file, and them move it in place as root

        trace( sub { ( 'saveFile-as-non-owner(', $filename, length( $content ), 'bytes, mask', sprintf( "%o", $mask ), ', uid', $uid, ', gid', $gid, ')' ) } );
        my $temp = File::Temp->new( UNLINK => 1 );
        print $temp $content;
        close $temp;

        my $cmd = sprintf( 'sudo install -m%o', $mask );
        if( $uname ) {
            $cmd .= ' -o' . $uname;
        }
        if( $gname ) {
            $cmd .= ' -g' . $gname;
        }

        $ret = ( 0 == UBOS::Utils::myexec( $cmd . " '" . $temp->filename . "' '$filename'" ));

        unlink( $temp );
    }

    return $ret;
}

##
# Delete one or more files
# @files: the files to delete
# return: 1 if successful
sub deleteFile {
    my @files = @_;

    trace( 'deleteFile(', @files, ')' );

    my $ret = 1;
    foreach my $f ( @files ) {
        if( -f $f || -l $f ) {
            unless( unlink( $f )) {
                error( "Failed to delete file $f:", $! );
                $ret = 0;
            }
        } elsif( -e $f ) {
            error( "Cannot delete file $f, it isn't a file or symlink" );
            $ret = 0;
        } else {
            error( "Cannot delete file $f, it doesn't exist" );
            $ret = 0;
        }
    }
    return $ret;
}

##
# Make a directory
# $filename: path to the directory
# $mask: permissions on the directory
# $uname: owner of the directory
# $gname: group of the directory
# return: 1 if successful
sub mkdir {
    my $filename = shift;
    my $mask     = shift;
    my $uid      = getUid( shift );
    my $gid      = getGid( shift );

    unless( defined( $mask )) {
        $mask = 0755;
    }

    if( -d $filename ) {
        warning( 'Directory exists already', $filename );
        return 1;
    }
    if( -e $filename ) {
        error( 'Failed to create directory, something is there already:', $filename );
        return 0;
    }

    trace( 'Creating directory', $filename );

    my $ret = CORE::mkdir $filename;
    unless( $ret ) {
        error( "Failed to create directory $filename:", $! );
    }

    chmod $mask, $filename;

    if( $uid >= 0 || $gid >= 0 ) {
        chown $uid, $gid, $filename;
    }

    return $ret;
}

##
# Make a directory, and parent directories if needed
# $filename: path to the directory
# $mask: permissions on the directory
# $uid: owner of the directory (name or uid)
# $gid: group of the directory (name or gid)
# $parentMask: permissions on any created parent directories
# $parentUid: owner of any created parent directories (name or uid)
# $parentGid: group of any created parent directories (name or gid)
# return: 1 if successful, or if the directory existed already
sub mkdirDashP {
    my $filename   = shift;
    my $mask       = shift;
    my $uid        = getUid( shift );
    my $gid        = getGid( shift );
    my $parentMask = shift;
    my $parentUid  = shift;
    my $parentGid  = shift;

    unless( defined( $mask )) {
        $mask = 0755;
    }
    unless( defined( $parentMask )) {
        $parentMask = $mask;
    }
    if( defined( $parentUid )) {
        $parentUid = getUid( $parentUid );
    } else {
        $parentUid = $uid;
    }
    if( defined( $parentGid )) {
        $parentGid = getGid( $parentGid );
    } else {
        $parentGid = $gid;
    }

    if( -d $filename ) {
        warning( 'Directory exists already', $filename );
        return 1;
    }
    if( -e $filename ) {
        error( 'Failed to create directory, something is there already:', $filename );
        return 0;
    }

    my $soFar = '';
    if( $filename =~ m!^/! ) {
        $soFar = '/';
    }
    foreach my $component ( split /\//, $filename ) {
        unless( $component ) {
            next;
        }
        if( $soFar && $soFar !~ m!/$! ) {
            $soFar .= '/';
        }
        $soFar .= $component;
        unless( -d $soFar ) {
            trace( 'Creating directory', $soFar );

            my $ret = CORE::mkdir $soFar;
            unless( $ret ) {
                error( "Failed to create directory $soFar:", $! );
                return $ret;
            }

            if( $filename eq $soFar ) {
                chmod $mask, $soFar;

                if( $uid >= 0 || $gid >= 0 ) {
                    chown defined( $uid ) ? $uid : -1, defined( $gid ) ? $gid : -1, $soFar;
                }
            } else {
                chmod $parentMask, $soFar;

                if( $parentUid >= 0 || $parentGid >= 0 ) {
                    chown defined( $parentUid ) ? $parentUid : -1, defined( $parentGid ) ? $parentGid : -1, $soFar;
                }
            }
        }
    }
    return 1;
}

##
# Make a symlink
# $oldfile: the destination of the symlink
# $newfile: the symlink to be created
# $uid: owner username
# $gid: group username
sub symlink {
    my $oldfile = shift;
    my $newfile = shift;
    my $uid     = getUid( shift );
    my $gid     = getGid( shift );

    trace( 'Symlink', $oldfile, $newfile );

    my $ret = symlink $oldfile, $newfile;
    if( $ret ) {
        if( $uid >= 0 || $gid >= 0 ) {
            lchown $uid, $gid, $newfile;
        }
    } else {
        error( 'Failed to symlink', $oldfile, $newfile );
    }

    return $ret;
}

##
# Resolve the target of a symbolic link to an absolute path.
# If this is not a symbolic link, resolve the path to an absolute path
# $path: the path
# return: the absolute path for $path, or its target if $path is a symbolic link
sub absReadlink {
    my $path = shift;

    my $ret;
    if( -l $path ) {
        if( $path =~ m!^(.*)/[^/]+$! ) {
            $ret = File::Spec->rel2abs( readlink( $path ), $1 );
        } else {
            $ret = File::Spec->rel2abs( readlink( $path ), '' );
        }
    } else {
        $ret = File::Spec->rel2abs( $path );
    }
    $ret = abs_path( $ret );
    return $ret;
}

##
# Delete one or more directories. They must be empty first
# @dirs: the directories to delete
# return: 1 if no error
sub rmdir {
    my @dirs = @_;

    trace( 'Delete directories:', @dirs );

    my $ret = 1;
    foreach my $d ( @dirs ) {
        if( -d $d ) {
            unless( CORE::rmdir( $d )) {
                error( "Failed to delete directory $d:", $! );
                $ret = 0;
            }
        } elsif( -e $d ) {
            error( 'Cannot delete directory. File exists but isn\'t a directory:', $d );
            $ret = 0;
        } else {
            warning( 'Cannot delete directory, does not exist:', $d );
            next;
        }
    }
    return $ret;
}

##
# Delete one ore mor files or directories recursively.
# @files: the files or directories to delete recursively
sub deleteRecursively {
    my @files = @_;

    my $ret = 1;
    if( @files ) {
        trace( 'Recursively delete files:', @files );

        if( myexec( 'rm -rf ' . join( ' ', map { "'$_'" } @files ))) {
            $ret = 0;
        }
    }
    return $ret;
}

##
# Copy a directory tree recursively to some other place
# $from: source directory
# $to: destination directory
# return: 1 if success
sub copyRecursively {
    my $from = shift;
    my $to   = shift;

    if( myexec( "cp -d -r -p --reflink=auto '$from' '$to'" )) {
        return 0;
    } else {
        return 1;
    }
}

##
# Move a file or directory tree
# $from: old name
# $to: new name
# return: 1 if success
sub move {
    my $from = shift;
    my $to   = shift;

    if( myexec( "mv '$from' '$to'" )) {
        return 0;
    } else {
        return 1;
    }
}

##
# Determine whether the provided directory is empty
# $dir: the directory
# return: 1 if empty
sub isDirEmpty {
    my $dir = shift;

    my $ret = 1;
    if( opendir( DIR, $dir )) {
        while( my $entry = readdir DIR ) {
            if( $entry ne '.' && $entry ne '..' ) {
                $ret = 0;
                last;
            }
        }
        closedir DIR;

    } else {
        error( "Not a directory:", $dir );
        $ret = 0;
    }

    return $ret;
}

##
# Read all files matching a pattern in a directory.
# $pattern: the file name pattern, e.g. '\.pm$'
# $dir: directory to look in
# return: hash of file name to file content
sub readFilesInDirectory {
    my $dir     = shift;
    my $pattern = shift;

    my $ret = {};

    opendir( DIR, $dir ) || error( $! );

    while( my $file = readdir( DIR )) {
        if( !$pattern || $file =~ m/$pattern/ ) {
            my $fileName = "$dir/$file";
            my $content  = UBOS::Utils::slurpFile( $fileName );

            $ret->{$file} = $content;
        }
    }
    closedir( DIR );

    return $ret;
}

##
# Obtain all Perl module files in a particular parent package.
# $parentPackage: name of the parent package
# $regex: a regex for the module files to be read, not counting the .pm extension, of any if not given
# $inc: the path to search, or @INC if not given
# return: hash of file name to package name
sub findPerlModuleNamesInPackage {
    my $parentPackage = shift;
    my $regex         = shift || '.+';
    my $inc           = shift || \@INC;

    my $parentDir = $parentPackage;
    $parentDir =~ s!::!/!g;

    my $ret = {};

    foreach my $inc2 ( @$inc ) {
        my $parentDir2 = "$inc2/$parentDir";

        if( -d $parentDir2 ) {
            opendir( DIR, $parentDir2 ) || error( $! );

            while( my $file = readdir( DIR )) {
               if( $file =~ m!^($regex)\.pm$! ) {
                   my $fileName    = "$parentDir2/$file";
                   my $packageName = $parentPackage . '::' . $1;

                   $ret->{$fileName} = $packageName;
               }
            }

            closedir(DIR);
        }
    }
    return $ret;
}

##
# Find the short, lowercase names of all Perl module files in a particular package.
# $parentPackage: name of the parent package
# $regex: a regex for the module files to be read, not counting the .pm extension, of any if not given
# $inc: the path to search, or @INC if not given
# return: hash of short package name to full package name
sub findPerlShortModuleNamesInPackage {
    my $parentPackage = shift;
    my $regex         = shift;
    my $inc           = shift;

    my $full = findPerlModuleNamesInPackage( $parentPackage, $inc );
    my $ret  = {};

    foreach my $fileName ( keys %$full ) {
        my $packageName = $full->{$fileName};

        my $shortName = $packageName;
        $shortName =~ s!^.*::!!;
        $shortName =~ s!([A-Z])!-lc($1)!ge;
        $shortName =~ s!^-!!;

        $ret->{$shortName} = $packageName;
    }

    return $ret;
}

##
# Find the package names of all Perl files matching a pattern in a directory.
# $dir: directory to look in
# $pattern: the file name pattern, e.g. '\.pm$'
# return: hash of file name to package name
sub findModulesInDirectory {
    my $dir     = shift;
    my $pattern = shift || '\.pm$';

    my $ret = {};

    opendir( DIR, $dir ) || error( $! );

    while( my $file = readdir( DIR )) {
        if( $file =~ m/$pattern/ ) {
            my $fileName = "$dir/$file";
            my $content  = UBOS::Utils::slurpFile( $fileName );

            if( $content =~ m!package\s+([a-zA-Z0-9:_]+)\s*;! ) {
                my $packageName = $1;

                $ret->{$file} = $packageName;
            }
        }
    }
    closedir( DIR );

    return $ret;
}

##
# Invoke callbacks found in a particular directory. Each callback
# is a file containing one or more lines, each of which is the name
# of the class on which the method should be invoked, plus optional arguments.
# that are passed to the method after the @args provided to this method.
# This currently does not know how to handle escapes or spaces in arguments.
# Does nothing if the directory does not exist.
# $dir: the directory in which the callbacks are to be found.
# $forward: if true, iterate over the directory in forward direction; backwards otherwise
# $method: the method to invoke
# @args: the arguments to pass, if any
# return: 1 if ok, 0 if fail
sub invokeCallbacks {
    my $dir     = shift;
    my $forward = shift;
    my $method  = shift;
    my @args    = @_;

    trace( 'invokeCallbacks(', $dir, $forward, $method, @args, ')' );

    unless( -d $dir ) {
        return 1;
    }

    my @files            = <$dir/*>;
    my $content          = join( "\n", map { slurpFile( $_ ) } grep { -f $_ } @files );
    my @packagesWithArgs = grep { $_ }
                           map { my $s = $_; $s =~ s!#.*$!! ; $s =~ s!^\s+!! ; $s =~ s!\s+$!! ; $s }
                           split /\n/, $content;

    unless( $forward ) {
        @packagesWithArgs = reverse @packagesWithArgs;
    }

    my $ret = 1;
    foreach my $packageWithArgs ( @packagesWithArgs ) {
        my( $package, @packageArgs ) = split /\s+/, $packageWithArgs;
        $ret &= UBOS::Utils::invokeMethod( $package . '::' . $method, @args, @packageArgs );
    }
    return $ret;
}

##
# Get numerical user id, given user name. If already numerical, pass through.
# $uname: the user name
# return: numerical user id
sub getUid {
    my $uname = shift;

    my $uid;
    if( !$uname ) {
        $uid = $<; # default is current user
    } elsif( $uname =~ /^[0-9]+$/ ) {
        $uid = $uname;
    } else {
        my @uinfo = getpwnam( $uname );
        unless( @uinfo ) {
            error( 'Cannot find user. Using \'nobody\' instead:', $uname );
            @uinfo = getpwnam( 'nobody' );
        }
        $uid = $uinfo[2];
    }
    return $uid;
}

##
# Get numerical group id, given group name. If already numerical, pass through.
# $uname: the group name
# return: numerical group id
sub getGid {
    my $gname = shift;

    my $gid;
    if( !$gname ) {
        $gid = $(; # default is current group
    } elsif( $gname =~ /^[0-9]+$/ ) {
        $gid = $gname;
    } else {
        my @ginfo = getgrnam( $gname );
        unless( @ginfo ) {
            error( 'Cannot find group. Using \'nogroup\' instead:',  $gname );
            @ginfo = getgrnam( 'nogroup' );
        }
        $gid = $ginfo[2];
    }
    return $gid;
}

##
# Get user name, given numerical user id. If already a string, pass through.
# $uid: user id
# return: user name
sub getUname {
    my $uid = shift;

    if( !defined( $uid )) {
        $uid = $<; # default is current user
    }
    my $uname;
    if( $uid =~ /^[0-9]+$/ ) {
        $uname = getpwuid( $uid );
        unless( $uname ) {
            error( 'Cannot find user. Using \'nobody\' instead:', $uid );
            $uname = 'nobody';
        }
    } else {
        $uname = $uid;
    }
    return $uname;
}

##
# Get group name, given numerical group id. If already a string, pass through.
# $gid: group id
# return: group name
sub getGname {
    my $gid = shift;

    if( !defined( $gid )) {
        $gid = $(; # default is current group
    }
    my $gname;
    if( $gid =~ /^[0-9]+$/ ) {
        $gname = getgrgid( $gid );
        unless( $gname ) {
            error( 'Cannot find group. Using \'nogroup\' instead:', $gid );
            $gname = 'nogroup';
        }
    } else {
        $gname = $gid;
    }
    return $gname;
}

##
# Make sure an OS user with the provided userId exists.
# If not, create the user with the specified group(s).
# Disable password-based login
# $userId: user id
# $groupIds: zero or more groups
# $comment: the comment for the /etc/passwd file
# $homeDir: desired location of home directory
# return: success or fail
#
# DEPRECATED in favor of systemd-sysusers
sub ensureOsUser {
    my $userId   = shift;
    my $groupIds = shift;
    my $comment  = shift;
    my $homeDir  = shift || "/home/$userId";

    my $out;
    my $err;
    if( myexec( "getent passwd $userId", undef, \$out, \$err )) {

        trace( 'Creating user', $userId );

        debugAndSuspend( 'Creating user', $userId );
        if( myexec( "sudo useradd -e '' -c '$comment' -m -U $userId -d $homeDir", undef, undef, \$err )) {
            error( 'Failed to create user', $userId, ', error:', $err );
            return 0;
        }

        if( defined( $groupIds ) && @$groupIds ) {
            trace( 'Adding user to groups:', $userId, @$groupIds );

            debugAndSuspend( 'Adding groups', @$groupIds );
            if( myexec( "sudo usermod -a -G " . join(',', @$groupIds ) . " $userId", undef, undef, \$err )) {
                error( 'Failed to add user to groups:', $userId, @$groupIds, 'error:', $err );
                return 0;
            }
        }
        if( myexec( "sudo chown -R $userId $homeDir" )) {
            error( 'Failed to chown home dir of user', $userId, $homeDir );
            return 0;
        }
        # lock the account by setting an impossible password
        if( myexec( "sudo passwd -l $userId", \$out, \$out )) {
            error( 'Failed to disable login for', $userId, ':', $out );
        }
    }
    return 1;
}

##
# Generate a random identifier
# $length: length of identifier
# return: identifier
sub randomIdentifier {
    my $length = shift || 8;

    my $ret    = '';
    for( my $i=0 ; $i<$length ; ++$i ) {
        $ret .= ("a".."z")[rand 26];
    }
    return $ret;
}

##
# Generate a random password
# $length: length of password
# return: password
sub randomPassword {
    my $length = shift || 8;

    my $ret = '';
    for( my $i=0 ; $i<$length ; ++$i ) {
        $ret .= ("a".."z", "A".."Z", 0..9)[rand 62];
    }
    return $ret;
}

##
# Generate a random hex number
# $length: length of hex number
# return: hex number
sub randomHex {
    my $length = shift || 8;

    my $ret = '';
    for( my $i=0 ; $i<$length ; ++$i ) {
        $ret .= (0..9, "a".."f")[rand 16];
    }
    return $ret;
}

##
# Generate a string of random bytes
# $length: number of bytes
# return: string of random bytes
sub randomBytes {
    my $length = shift || 8;

    my $ret = '';
    for( my $i=0 ; $i<$length ; ++$i ) {
        $ret .= chr( rand 256 );
    }
    return $ret;
}
##
# Escape a single quote in a string
# $raw: string to be escaped
# return: escaped string
sub escapeSquote {
    my $raw = shift;

    $raw =~ s/'/\\'/g;

    return $raw;
}

##
# Escape a double quote in a string
# $raw: string to be escaped
# return: escaped string
sub escapeDquote {
    my $raw = shift;

    $raw =~ s/"/\\"/g;

    return $raw;
}

##
# Trim whitespace from the start and end of a string
# $raw: string to be trimmed
# return: trimmed string
sub trim {
    my $raw = shift;

    $raw =~ s/^\s*//g;
    $raw =~ s/\s*$//g;

    return $raw;
}

##
# Convert line feeds into a space.
# $raw: string to be converted
# return: converted string
sub cr2space {
    my $raw = shift;

    $raw =~ s/\s+/ /g;

    return $raw;
}

##
# Format time consistently
# return: formatted time
sub time2string {
    my $time = shift;

    my ( $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst ) = gmtime( $time );
    my $ret = sprintf "%.4d%.2d%.2d-%.2d%.2d%.2d", ($year+1900), ( $mon+1 ), $mday, $hour, $min, $sec;
    return $ret;
}

##
# Parse formatted timed correctly
# $s: the string produced by time2string
# return: UNIX time
sub string2time {
    my $s = shift;
    my $ret;

    if( $s =~ m!^(\d\d\d\d)(\d\d)(\d\d)-(\d\d)(\d\d)(\d\d)$! ) {
        $ret = timegm( $6, $5, $4, $3, $2-1, $1-1900 );
    } else {
        error( "Cannot parse time string $s" );
    }

    return $ret;
}

##
# Escape characters in URL. Inspired by http://cpansearch.perl.org/src/GAAS/URI-1.60/URI/Escape.pm,
# which does not seem to come with Arch.
sub uri_escape {
    my $s = shift;

    $s =~ s!([^-A-Za-z0-9\._~])!sprintf("%%%02X",ord($1))!ge;

    return $s;
}

##
# Regenerate the /etc/pacman.conf file. If a repository gets added,
# the next pacman command must be to sync with the added repository,
# otherwise a pacman error will occur.
# $pacmanConfFile: the pacman config file, or default if not provided.
# $pacmanRepoDir: directory containing the repository fragement statements.
#    This allows ubos-install to invoke this for staged images
# $channel: use this as the value for $channel in the repo URLs, or, if not
#    given, use value of /etc/ubos/channel
sub regeneratePacmanConf {
    my $pacmanConfFile = shift || '/etc/pacman.conf';
    my $pacmanRepoDir  = shift || '/etc/pacman.d/repositories.d';
    my $channel        = shift;

    unless( $channel ) {
        $channel = channel();
    }

    my $pacmanConf    = slurpFile( $pacmanConfFile );
    my $oldPacmanConf = $pacmanConf;

    if( $pacmanConf =~ m!^(.*?)$PACMAN_CONF_SEP!s ) {
        # zap the trailer
        $pacmanConf = $1;
    }

    $pacmanConf =~ s!\s+$!!; # zap white space at end
    $pacmanConf .= "\n\n" . $PACMAN_CONF_SEP . "\n";

    my @repoFiles = glob( "$pacmanRepoDir/*" );
    @repoFiles = sort @repoFiles;

    foreach my $repoFile ( @repoFiles ) {
        my $toAdd = UBOS::Utils::slurpFile( $repoFile );
        $toAdd =~ s!#.*$!!gm; # remove comments -- will confuse the user
        $toAdd =~ s!^\s+!!gm; # leading white space
        $toAdd =~ s!\s+$!!gm; # trailing white space
        $toAdd =~ s!\$channel!$channel!g;

        $pacmanConf .= "\n" . $toAdd . "\n";
    }

    unless( $pacmanConf eq $oldPacmanConf ) {
        UBOS::Utils::saveFile( $pacmanConfFile, $pacmanConf );
    }
}

##
# Generate/update /etc/issue
# $deviceClass: the device class
# $channel: the channel
# $target: root directory of the file system
# return: number of errors
sub regenerateEtcIssue {
    my $deviceClass = shift || deviceClass();
    my $channel     = shift || channel();
    my $target      = shift || '';

    my $errors = 0;
    my $issue = <<ISSUE;

+--------------------------------------------------------------------------+
|                                                                          |
|                           Welcome to UBOS (R)                            |
|                                                                          |
|                                ubos.net                                  |
|                                                                          |
ISSUE
    $issue .= sprintf( "|%74s|\n", "device class: $deviceClass, channel: $channel " );
    $issue .= <<ISSUE;
+--------------------------------------------------------------------------+

ISSUE

    my $advice = <<ADVICE;
Note: run 'sudo ubos-admin update' to get the latest version.
      and: frequent backups with 'sudo ubos-admin backup' are recommended.

ADVICE
    unless( UBOS::Utils::saveFile( $target . '/etc/issue',     $issue . $advice, 0644, 'root', 'root' )) {
        ++$errors;
    }
    unless( UBOS::Utils::saveFile( $target . '/etc/issue.net', $issue,           0644, 'root', 'root' )) {
        ++$errors;
    }
    return $errors;
}

##
# Determine whether a candidate channel name is indeed a valid channel.
# If so, return the canonical name of the valid channel.
# $channelCandidate: the candidate name for the channel
# return: channel name, or undef
sub isValidChannel {
    my $channelCandidate = shift;

    unless( $channelCandidate ) {
        return undef;
    }

    $channelCandidate = lc( $channelCandidate );
    foreach my $channel ( @VALID_CHANNELS ) {
        if( $channel eq $channelCandidate ) {
            return $channel;
        }
    }
    return undef;
}

##
# Determine the arch of this system
sub arch {

    my $ret;
    UBOS::Utils::myexec( 'uname -m', undef, \$ret );
    $ret =~ s!^\s+!!;
    $ret =~ s!\s+$!!;
    $ret =~ s!(armv[67])l!$1h!;

    return $ret;
}

##
# Determine whether a candidate arch name is a valid arch.
# If so, return the canonical name of the valid arch.
# $archCandidate: the candidate name for the arch
# return: arch name, or undef
sub isValidArch {
    my $archCandidate = shift;

    unless( $archCandidate ) {
        return undef;
    }

    my $cand = lc( $archCandidate );
    foreach my $arch ( @VALID_ARCHS ) {
        if( $arch eq $cand ) {
            return $arch;
        }
    }

    $@ = 'Not a valid arch: ' . $archCandidate;
    return undef;
}

##
# Determine whether a candidate device class name is a valid device class.
# If so, return the canonical name of the valid device class.
# $deviceClassCandidate: the candidate name for the device class
# return: device class name, or undef
sub isValidDeviceClass {
    my $deviceClassCandidate = shift;

    unless( $deviceClassCandidate ) {
        return undef;
    }

    my $cand = lc( $deviceClassCandidate );
    foreach my $deviceClass ( @VALID_DEVICE_CLASSES ) {
        if( $deviceClass eq $cand ) {
            return $deviceClass;
        }
    }

    $@ = 'Not a valid device class: ' . $deviceClassCandidate;
    return undef;
}

##
# Determine whether this is a valid hostname
# $hostname: the hostname
# return: hostname, or undef
sub isValidHostname {
    my $hostname = shift;

    if( ref( $hostname )) {
        error( 'Supposed hostname is not a string:', ref( $hostname ));
        return undef;
    }

    unless( $hostname =~ m!^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|-){0,61}[0-9A-Za-z])?)*\.?$|^\*$! ) {
        # regex originally from http://stackoverflow.com/a/1420225/200304
        $@ = 'Not a valid hostname: ' . $hostname;
        return undef;
    }
    return $hostname;
}

##
# Helper method to read /etc/os-release
# Return: hash with found values (may be empty)
sub _getOsReleaseInfo {
    unless( defined( $_osReleaseInfo )) {
        $_osReleaseInfo = {};

        if( -e '/etc/os-release' ) {
            my $osRelease = UBOS::Utils::slurpFile( '/etc/os-release' );
            while( $osRelease =~ m!^\s*([-_a-zA-Z0-9]+)\s*=\s*\"?([-_ ;:/\.a-zA-Z0-9]*)\"?\s*$!mg ) {
                $_osReleaseInfo->{$1} = $2;
            }
        }
    }
    return $_osReleaseInfo;
}

##
# Determine the device class of this system. Works on UBOS and non-UBOS
# systems.
sub deviceClass {
    if( $_deviceClass ) {
        return $_deviceClass;
    }

    my $osReleaseInfo = _getOsReleaseInfo();
    if( exists( $osReleaseInfo->{'UBOS_DEVICECLASS'} )) {
        $_deviceClass = $osReleaseInfo->{'UBOS_DEVICECLASS'};
    }

    unless( $_deviceClass ) {
        # now we guess

        if( -e '/.dockerenv' ) {
            $_deviceClass = 'docker';

        } else {
            my $out;

            myexec( 'systemd-detect-virt', undef, \$out, undef );
            if( $out =~ m!systemd-nspawn! ) {
                $_deviceClass = 'container';

            } elsif( $out =~ m!xen! ) {
                $_deviceClass = 'ec2';

            } elsif( $out =~ m!oracle! ) {
                $_deviceClass = 'vbox';

            } else {
                myexec( 'uname -a', undef, \$out, undef );
                if( $out =~ m!(alarmpi|raspberry).*armv6l! ) {
                    $_deviceClass = 'rpi';

                } elsif( $out =~ m!(alarmpi|raspberry).*armv7l! ) {
                    $_deviceClass = 'rpi2';

                } elsif( $out =~ m!espressobin.*aarch64! ) {
                    $_deviceClass = 'espressobin';

                } elsif( $out =~ m!x86_64! ) {
                    $_deviceClass = 'pc';
                }
            }
        }
    }
    return $_deviceClass;
}

##
# Determine the current device's kernel package name.
# return: kernel package name, or undef
sub kernelPackageName {
    my $ret;

    my $osReleaseInfo = _getOsReleaseInfo();
    if( exists( $osReleaseInfo->{'UBOS_KERNELPACKAGE'} )) {
        return $osReleaseInfo->{'UBOS_KERNELPACKAGE'};
    }
    return undef;
}

##
# Determine the release channel this device is on.
#
# return: release channel
sub channel {
    my $channel;

    if( -e $CHANNEL_FILE ) {
        $channel = slurpFile( $CHANNEL_FILE );
        $channel =~ s!^\s+!!;
        $channel =~ s!\s+$!!;
        $channel = isValidChannel( $channel );
        unless( $channel ) {
            warning( 'Invalid channel specified, defaulting to yellow:', $CHANNEL_FILE );
            $channel = 'yellow';
        }
    } else {
        warning( 'Cannot read channel file, defaulting to yellow:', $CHANNEL_FILE );
        $channel = 'yellow';
    }
    return $channel;
}

##
# Determine the product SKU of this device.
#
# return: the SKU, or undef if not a product
sub sku {
    my $sku = undef;

    if( -e $SKU_FILE ) {
        $sku = slurpFile( $SKU_FILE );
        $sku =~ s!^\s+!!;
        $sku =~ s!\s+$!!;
    }
    return $sku;
}

##
# Determine whether the provided string represents an IPv4 address
# $candidate: the candidate IP address
# return: 0 or 1
sub isIpv4Address {
    my $candidate = shift;

    if( $candidate =~ m!^\d+\.\d+\.\d+\.\d+$! ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine whether the provided string represents an IPv6 address.
# This is not a very strict check, but it is enough to tell IPv6 from
# IPv4 addresses.
# $candidate: the candidate IP address
# return: 0 or 1
sub isIpv6Address {
    my $candidate = shift;

    if( $candidate =~ m!^[0-9a-fA-F:]+$! ) {
        return 1;
    } else {
        return 0;
    }
}

##
# Determine whether we can reach the internet
# $host: hostname to attempt to reach
# return: true or false
sub isOnline {
    my $host = shift || 'depot.ubos.net';
    my $ret = Net::Ping->new( 'icmp' )->ping( $host );

    return $ret;
}

##
# Check the provided directories for dangling symlinks, and if any exist, remove them.
# @dirs: the directories to check
# return: the number of removed symlinks
sub removeDanglingSymlinks {
    my @dirs = @_;

    my @remove = ();
    foreach my $dir ( @dirs ) {
        if( opendir( DIR, $dir )) {
            while( my $entry = readdir DIR ) {
                if( $entry eq '.' || $entry eq '..' ) {
                    next;
                }
                my $fullEntry = "$dir/$entry";
                unless( -l $fullEntry ) {
                    next;
                }
                unless( -e "$fullEntry" ) {
                    push @remove, "$fullEntry";
                }
            }
            closedir DIR;
        } else {
            error( 'Cannot read directory', $dir );
        }
    }
    if( @remove ) {
        deleteFile( @remove );
    }

    return 0 + ( @remove );
}

##
# Invoke the method with the name held in a variable.
# $methodName: name of the method
# @_: arguments to the method
# return: result of the method
sub invokeMethod {
    my $methodName = shift;
    my @args       = @_;

    my @ret;
    if( $methodName =~ m!^(.*)((?:::)|(?:->))(.*)! ) {
        my $packageName     = $1;
        my $operator        = $2;
        my $shortMethodName = $3;

        eval "require $packageName" || warning( "Cannot read $packageName:", $@ );

        if( $operator eq '::' ) {
            @ret = &{\&{$methodName}}( @args );
        } else {
            @ret = $packageName->$shortMethodName( @args );
        }
    } else {
        @ret = &{\&{$methodName}}( @args );
    }

    return wantarray ? @ret : ( @ret ? $ret[0] : undef );
}

##
# Helper method to convert name-value pairs into a string with column format.
# Optionally, the value can be processed before converted to string
# $hash: hash of first column to second column
# $f: optional method to invoke on the second column before printing. Do not print if method returns undef
# $comp: optional comparison method on the keys, for sorting
# return: string
sub hashAsColumns {
    my $hash = shift;
    my $f    = shift || sub { shift; };
    my $comp = shift;

    my $toPrint = {};
    my $indent  = 0;
    foreach my $name ( keys %$hash ) {
        my $obj            = $hash->{$name};
        my $formattedValue = &$f( $obj );

        if( defined( $formattedValue )) {
            $toPrint->{$name} = $formattedValue;

            my $length = length( $name );
            if( $length > $indent ) {
                $indent = $length;
            }
        }
    }

    my @sortedKeys;
    if( defined( $comp )) {
        @sortedKeys = sort $comp keys %$toPrint;
    } else {
        @sortedKeys = sort keys %$toPrint;
    }

    my $s   = ' ' x $indent;
    my $ret = '';
    foreach my $name ( @sortedKeys ) {
        my $formattedValue = $toPrint->{$name};
        $formattedValue =~ s!^\s*!$s!gm;
        $formattedValue =~ s!^\s+!!;
        $formattedValue =~ s!\s+$!!;

        $ret .= sprintf( '%-' . $indent . "s - %s\n", $name, $formattedValue );
    }
    return $ret;
}

1;
