#!/usr/bin/perl
#
# Collection of utility methods.
#
# This file is part of indiebox-admin.
# (C) 2012-2014 Indie Computing Corp.
#
# indiebox-admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# indiebox-admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with indiebox-admin.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package IndieBox::Utils;

use IndieBox::Logging;
use Exporter qw( import myexec );
use File::Temp;
use JSON;
use Lchown;
use POSIX;
use Time::Local qw( timegm );

our @EXPORT = qw( readJsonFromFile readJsonFromStdin readJsonFromString
                  writeJsonToFile writeJsonToStdout writeJsonToString
                  myexec saveFile slurpFile );
my $jsonParser = JSON->new->relaxed->pretty->utf8();

##
# Read and parse JSON from a file
# $from: file to read from
# return: JSON object
sub readJsonFromFile {
    my $file = shift;

    trace( 'readJsonFromFile(', $file, ')' );

    my $fileContent = slurpFile( $file );

    my $json;
    eval {
        $json = $jsonParser->decode( $fileContent );
    } or fatal( 'JSON parsing error in file', $file, ':', $@ );

    return $json;
}

##
# Read and parse JSON from STDIN
# return: JSON object
sub readJsonFromStdin {
    trace( 'readJsonFromStdin()' );

    local $/;
    my $fileContent = <STDIN>;

    my $json;
    eval {
        $json = $jsonParser->decode( $fileContent );
    } or fatal( 'JSON parsing error from <stdin>:', $@ );

    return $json;
}

##
# Read and parse JSON from String
# $string: the JSON string
# return: JSON object
sub readJsonFromString {
    my $string = shift;

    trace( 'readJsonFromString()' );

    my $json;
    eval {
        $json = $jsonParser->decode( $string );
    } or fatal( 'JSON parsing error:', $@ );

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

    trace( 'writeJsonToFile(', $fileName, ')' );

    saveFile( $fileName, $jsonParser->encode( $json ), $mask, $uname, $gname );
}

##
# Write JSON to STDOUT
# $json: the JSON object to write
sub writeJsonToStdout {
    my $json = shift;

    trace( 'writeJsonToStdout()' );

    print $jsonParser->encode( $json );
}

##
# Write JSON to string
# $json: the JSON object to write
sub writeJsonToString {
    my $json = shift;

    trace( 'writeJsonToString()' );

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
        while( my( $name, $value ) = each %$json ) {
            $ret->{$name} = insertSlurpedFiles( $value, $dir );
        }
        
    } elsif( ref( $json ) ) {
        $ret = $json;
        
    } else {
        # string
        if( $json =~ m!^\@(/.*)$! ) {
            $ret = slurpFile( $1 );
        } elsif( $json =~ m!^\@(.*)$! ) {
            $ret = slurpFile( "$dir/$1" );
        } else {
            $ret = $json;
        }
    }
    return $ret;    
}

##
# Execute a command, and optionally read/write standard stream to/from strings
# $cmd: the commaand
# $inContent: optional string containing what will be sent to stdin
# $outContentP: optional reference to variable into which stdout output will be written
# $errContentP: optional reference to variable into which stderr output will be written
sub myexec {
    my $cmd         = shift;
    my $inContent   = shift;
    my $outContentP = shift;
    my $errContentP = shift;

    my $inFile;
    my $outFile;
    my $errFile;

    debug( 'Exec:', $cmd );

    if( $inContent ) {
        $inFile = File::Temp->new();
        print $inFile $inContent;
        close $inFile;

        $cmd .= " <" . $inFile->filename;
    }
    if( defined( $outContentP )) {
        $outFile = File::Temp->new();
        $cmd .= " >" . $outFile->filename;
    }
    if( defined( $errContentP )) {
        $errFile = File::Temp->new();
        $cmd .= " 2>" . $errFile->filename;
    }

    system( $cmd );
    my $ret = $?;

    if( defined( $outContentP )) {
        ${$outContentP} = slurpFile( $outFile->filename );
    }
    if( defined( $errContentP )) {
        ${$errContentP} = slurpFile( $errFile->filename );
    }

    if( $ret == -1 || $ret & 127) {
        error( 'Failed to execute', $cmd, "(error code $ret):", $! );
    }
    return $ret;
}

##
# Slurp the content of a file
# $filename: the name of the file to read
# return: the content of the file
sub slurpFile {
    my $filename = shift;

    trace( 'slurpFile(', $filename, ')' );

    local $/;
    open( my $fh, '<', $filename ) || fatal( 'Cannot read file', $filename );
    my $fileContent = <$fh>;
    close $fh;

    return $fileContent;
}

##
# Save content to a file.
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

    my $uid = getUid( $uname );
    my $gid = getGid( $gname );

    unless( defined( $mask )) {
        $mask = 0644;
    }
    trace( 'saveFile(', $filename, length( $content ), 'bytes, mask', sprintf( "%o", $mask ), ', uid', $uid, ', gid', $gid, ')' );

    unless( sysopen( F, $filename, O_CREAT | O_WRONLY | O_TRUNC )) {
        error( "Could not write to file $filename:", $! );
        return 0;
    }

    if( defined( $content )) {
        print F $content;
    } else {
        # This is usually a programming error
        IndieBox::Logging::warn( 'Undefined content when attempting to save file', $filename );
    }
    close F;

    chmod $mask, $filename;

    if( $uid >= 0 || $gid >= 0 ) {
        chown $uid, $gid, $filename;
    }

    return 1;
}

##
# Delete one or more files
# @files: the files to delete
# return: 1 if successful
sub deleteFile {
    my @files = @_;

    trace( 'deleteFile(', join( ", ", @files ), ')' );

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
        IndieBox::Logging::warn( 'Directory exists already', $filename );
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
    unless( $ret ) {
        error( 'Failed to symlink', $oldfile, $newfile );
    }
    if( $uid >= 0 || $gid >= 0 ) {
        lchown $uid, $gid, $newfile;
    }

    return $ret;
}

##
# Delete one or more directories. They must be empty first
# @dirs: the directories to delete
sub rmdir {
    my @dirs = @_;

    trace( 'Delete directories:', join( ', ', @dirs ));

    my $ret = 1;
    foreach my $d ( @dirs ) {
        if( -d $d ) {
            unless( CORE::rmdir( $d )) {
                error( "Failed to delete directory $d:", $! );
                $ret = 0;
            }
        } elsif( -e $d ) {
            error( "Cannot delete directory. File exists but isn't a directory", $d );
            $ret = 0;
        } else {
            IndieBox::Logging::warn( 'Cannot delete directory, does not exist', $d );
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
        trace( 'Recursively delete files:', join( ', ', @files ));

        myexec( 'rm -rf ' . join( ' ', map { "'$_'" } @files ));
    }
    return $ret;
}

##
# Copy a directory tree recursively to some other place
# $from: source directory
# $to: destination directory
sub copyRecursively {
    my $from = shift;
    my $to   = shift;

    debug( 'copyRecursively:', $from, $to );

    myexec( "cp -d -r -p '$from' '$to'" );

    return 1;
}

##
# Read all files matching a pattern in a directory.
# $pattern: the file name pattern, e.g. '\.pm$'
# $dir: directory to look in
# return: hash of file name to file content
sub readFilesInDirectory {
    my $dir     = shift;
    my $pattern = shift || '\.pm$';

    my $ret = {};
    
    opendir( DIR, $dir ) || error( $! );

    while( my $file = readdir( DIR )) {
        if( $file =~ m/$pattern/ ) {
            my $fileName    = "$dir/$file";
            my $content     = IndieBox::Utils::slurpFile( $fileName );

            $ret->{$file} = $content;
        }
    }
    closedir( DIR );

    return $ret;
}

##
# Obtain all Perl module files in a particular parent package.
# $parentPackage: name of the parent package, such as IndieBox::AppConfigurationItems
# $inc: the path to search, or @INC if not given
# return: hash of file name to package name
sub findPerlModuleNamesInPackage {
    my $parentPackage = shift;
    my $inc           = shift || \@INC;

    my $parentDir = $parentPackage;
    $parentDir =~ s!::!/!g;

    my $ret = {};
    
    foreach my $inc2 ( @$inc ) {
        my $parentDir2 = "$inc2/$parentDir";

        if( -d $parentDir2 ) {
            opendir( DIR, $parentDir2 ) || error( $! );

            while( my $file = readdir( DIR )) {
               if( $file =~ m/^(.*)\.pm$/ ) {
                   my $fileName    = "$parentDir2/$file";
                   my $packageName = "$parentPackage::$1";

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
# $parentPackage: name of the parent package, such as IndieBox::AppConfigurationItems
# $inc: the path to search, or @INC if not given
# return: hash of short package name to full package name
sub findPerlShortModuleNamesInPackage {
    my $parentPackage = shift;
    my $inc           = shift;

    my $full = findPerlModuleNamesInPackage( $parentPackage, $inc );
    my $ret  = {};

    while( my( $fileName, $packageName ) = each %$full ) {
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
            my $fileName    = "$dir/$file";
            my $content     = IndieBox::Utils::slurpFile( $fileName );

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
# Get numerical user id, given user name. If already numerical, pass through.
# $uname: the user name
# return: numerical user id
sub getUid {
    my $uname = shift;

    my $uid;
    if( !$uname ) {
        $uid = 0; # default is root
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
        $gid = 0; # default is root
    } elsif( $gname =~ /^[0-9]+$/ ) {
        $gid = $gname;
    } else {
        my @ginfo = getgrnam( $gname );
        unless( @ginfo ) {
            error( 'Cannot find group. Using \'nogroup\' instead.',  $gname );
            @ginfo = getgrnam( 'nogroup' );
        }
        $gid = $ginfo[2];
    }
    return $gid;
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

    my $ret    = '';
    for( my $i=0 ; $i<$length ; ++$i ) {
        $ret .= (0..9, "a".."f")[rand 16];
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
# Format time consistency
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
        fatal( "Cannot parse time string $s" );
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
# Invoke the method with the name held in a variable.
# $methodName: name of the method
# @_: arguments to the method
# return: result of the method
sub invokeMethod {
    my $methodName = shift;
    my @args       = @_;

    if( $methodName =~ m!^(.*)::! ) {
        my $packageName = $1;
        eval "require $packageName" || IndieBox::Logging::warn( "Cannot read $packageName: $@" );
    }

    my $ret = &{\&{$methodName}}( @args );
    return $ret;
}

1;
