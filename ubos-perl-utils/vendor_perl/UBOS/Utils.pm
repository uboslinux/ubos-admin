#!/usr/bin/perl
#
# Collection of utility methods.
#
# This file is part of ubos-perl-utils.
# (C) 2012-2014 Indie Computing Corp.
#
# ubos-perl-utils is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# ubos-perl-utils is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with ubos-perl-utils. If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

package UBOS::Utils;

use Exporter qw( import myexec );
use File::Temp;
use JSON;
use Lchown;
use POSIX;
use Time::Local qw( timegm );
use UBOS::Logging;

our @EXPORT = qw( readJsonFromFile readJsonFromStdin readJsonFromString
                  writeJsonToFile writeJsonToStdout writeJsonToString
                  myexec saveFile slurpFile );
my $jsonParser = JSON->new->relaxed->pretty->allow_nonref->utf8();

##
# Read and parse JSON from a file
# $from: file to read from
# return: JSON object
sub readJsonFromFile {
    my $file = shift;

    my $fileContent = slurpFile( $file );

    my $json;
    eval {
        $json = $jsonParser->decode( $fileContent );
    } or error( 'JSON parsing error in file', $file, ':', $@ );

    return $json;
}

##
# Read and parse JSON from STDIN
# return: JSON object
sub readJsonFromStdin {

    local $/;
    my $fileContent = <STDIN>;

    my $json;
    eval {
        $json = $jsonParser->decode( $fileContent );
    } or error( 'JSON parsing error from <stdin>:', $@ );

    return $json;
}

##
# Read and parse JSON from String
# $string: the JSON string
# return: JSON object
sub readJsonFromString {
    my $string = shift;

    my $json;
    eval {
        $json = $jsonParser->decode( $string );
    } or error( 'JSON parsing error:', $@ );

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
# $errContentP: optional reference to variable into which stderr output will be written.
#               if this has the same non-null value as $outContentP, both streams will be
#               redirected together
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
        if( defined( $outContentP ) && $outContentP == $errContentP ) {
            $cmd .= " 2>&1";
            $errContentP = undef;
        } else {
            $errFile = File::Temp->new();
            $cmd .= " 2>" . $errFile->filename;
        }
    }

    system( $cmd );
    my $ret = $?;

    if( defined( $outContentP )) {
        ${$outContentP} = slurpFile( $outFile->filename );
    }
    if( defined( $errContentP )) {
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
# return: the content of the file
sub slurpFile {
    my $filename = shift;

    debug( 'slurpFile(', $filename, ')' );

    local $/;
    open( my $fh, '<', $filename );
    if( $fh ) {
        my $fileContent = <$fh>;
        close $fh;

        return $fileContent;

    } else {
        error( 'Cannot read file', $filename );
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
    # more efficient if debug isn't on

    my $ret;
    if( $< == 0 || ( $uid == $< && $gid == $( )) {
        # This is faster -- for root, or for creating one's own files

        debug( sub { ( 'saveFile-as-root-or-owner(', $filename, length( $content ), 'bytes, mask', sprintf( "%o", $mask ), ', uid', $uid, ', gid', $gid, ')' ) } );
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
        
        debug( sub { ( 'saveFile-as-non-owner(', $filename, length( $content ), 'bytes, mask', sprintf( "%o", $mask ), ', uid', $uid, ', gid', $gid, ')' ) } );
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

    debug( 'deleteFile(', @files, ')' );

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

    debug( 'Creating directory', $filename );

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

    debug( 'Symlink', $oldfile, $newfile );

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
# Delete one or more directories. They must be empty first
# @dirs: the directories to delete
sub rmdir {
    my @dirs = @_;

    debug( 'Delete directories:', @dirs );

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
        debug( 'Recursively delete files:', @files );

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
sub copyRecursively {
    my $from = shift;
    my $to   = shift;

    if( myexec( "cp -d -r -p '$from' '$to'" )) {
        return 0;
    } else {
        return 1;
    }
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
# $parentPackage: name of the parent package
# $inc: the path to search, or @INC if not given
# return: hash of short package name to full package name
sub findPerlShortModuleNamesInPackage {
    my $parentPackage = shift;
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
            error( 'Cannot find group. Using \'nogroup\' instead.',  $gname );
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
# Invoke the method with the name held in a variable.
# $methodName: name of the method
# @_: arguments to the method
# return: result of the method
sub invokeMethod {
    my $methodName = shift;
    my @args       = @_;

    my $ret;
    if( $methodName =~ m!^(.*)((?:::)|(?:->))(.*)! ) {
        my $packageName     = $1;
        my $operator        = $2;
        my $shortMethodName = $3;

        eval "require $packageName" || warning( "Cannot read $packageName:", $@ );

        if( $operator eq '::' ) {
            $ret = &{\&{$methodName}}( @args );
        } else {
            $ret = $packageName->$shortMethodName( @args );
        }
    } else {
        $ret = &{\&{$methodName}}( @args );
    }

    return $ret;
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
