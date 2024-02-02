#!/usr/bin/perl
#
# Represents the state of the ratchet upgrade on this device. During upgrades, there are
# two instances of this class:
# 1) represents the state prior to the attempted upgrade. It is read from disk.
# 2) represents the state to which we are attempting to upgrade. The /etc/pacman.conf
#    is generated from this state so the new code can be installed. This state is only
#    written to disk once the upgrade has successfully ended. (If it is needed before
#    that, it is regenerated as often as needed, e.g. after reboot during upgrade.)
#    If the upgrade fails, it is not written to disk, so at the next invocation of update,
#    we still have the same 1), but 2) will be generated to be the same as during the last
#    attempt.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::RatchetState;

use UBOS::Logging;
use UBOS::Utils;

use fields qw( pacmanConfFile repoDir repoHistoriesDir repos upgradeSuccessTs repositoryPositionTs repoHistories isModified );

# pacmanConfFile: location of pacman.conf, e.g. /etc/pacman.conf
# repoDir: directory containing the repository files from which pacman.conf is generated, e.g. /etc/pacman.d/repositories.d
# repos:   maps names of active repos to a hash with the following entries:
#     'server'     => 'https://depot.ubosfiles.net/red/aarch64/os',    # variables replaced
#     'rawcontent' => '...'                                            # raw content of the file in repositories.d
# upgradeSuccessTs: wall clock time when the system was last upgraded successfully
# repositoryPositionTs: timestamp identifying position in the ratchet
# repoHistories: hash from repo name to hash reflecting the JSON content of that repo's history.json file
# isModified: if 0, no need to save the file

my $DEFAULT_PACMAN_CONF_FILE   = '/etc/pacman.conf';
my $DEFAULT_PACMAN_REPO_DIR    = '/etc/pacman.d/repositories.d';
my $DEFAULT_REPO_HISTORIES_DIR = '/etc/ubos/repo-histories.d'; # caches repo's history.json files
my $PACMAN_CONF_SEP            = '### DO NOT EDIT ANYTHING BELOW THIS LINE, UBOS WILL OVERWRITE ###';
my $LAST_UPDATE_FILE           = '/var/ubos/last-ubos-update'; # not /var, as /var might move from system to system -- obsolete
my $LAST_UPDATE_JSON_FILE      = '/etc/ubos/last-ubos-update.json';

##
# Factory method to create a RatchetState from the standard locations in the
# filesystem on a device. This is used during ubos-admin update and the like.
sub load {
    my $self    = shift;

    my $arch    = UBOS::Utils::arch();
    my $channel = UBOS::Utils::channel();

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{pacmanConfFile}   = $DEFAULT_PACMAN_CONF_FILE;
    $self->{repoDir}          = $DEFAULT_PACMAN_REPO_DIR;
    $self->{repoHistoriesDir} = $DEFAULT_REPO_HISTORIES_DIR;
    $self->{repos}            = {};

    my @repoFiles = glob( $self->{repoDir} . '/*' );

    foreach my $repoFile ( @repoFiles ) {
        my $rawRepoFileContent = UBOS::Utils::slurpFile( $repoFile );
        my $repoFileContent    = $rawRepoFileContent;

        $repoFileContent =~ s!#.*$!!gm; # remove comments
        $repoFileContent =~ s!^\s+!!gm; # leading white space
        $repoFileContent =~ s!\s+$!!gm; # trailing white space

        unless( $repoFileContent ) {
            # nothing in it, must be disabled/commented out
            next;
        }
        if( $repoFileContent =~ m!\[([^\]]+)\]\sServer\s*=\s*(\S+)! ) {
            my $dbName        = $1;
            my $rawServerName = $2;
            my $repoName      = $repoFile;

            if( $rawServerName =~ m!/$! ) {
                $rawServerName = substr( $rawServerName, 0, -1 );
            }
            my $serverName = $rawServerName;
            $serverName =~ s!\$arch!$arch!g;
            $serverName =~ s!\$channel!$channel!g;

            $repoName =~ s!.*/!!;

            $self->{repos}->{$repoName} = {
                'server'     => $serverName,
                'rawcontent' => $rawRepoFileContent
            };
        } else {
            warning( 'Repo file does not have expected syntax, skipping:', $repoFile );
        }
    }
    trace( 'Determined repos', $self->repoNames() );

    if( -e $LAST_UPDATE_JSON_FILE ) {
        my $lastUpdateJson = UBOS::Utils::readJsonFromFile( $LAST_UPDATE_JSON_FILE );
        $self->{upgradeSuccessTs}     = UBOS::Utils::rfc3339string2time( $lastUpdateJson->{upgradeSuccessTs} );
        $self->{repositoryPositionTs} = UBOS::Utils::rfc3339string2time( $lastUpdateJson->{repositoryPositionTs} );
    } elsif( -e $LAST_UPDATE_FILE ) {
        $self->{upgradeSuccessTs}     = UBOS::Utils::string2time( UBOS::Utils::slurpFile( $LAST_UPDATE_FILE ));
        $self->{repositoryPositionTs} = undef;
    }
    $self->{repoHistories} = undef; # allocated as needed

    return $self;
}

##
# Factory method to create a RatchetState that will be the initial RatchetState for a newly installed system
sub new {
    my $self             = shift;
    my $pacmanConfFile   = shift;
    my $repoDir          = shift;
    my $repoHistoriesDir = shift;
    my $repos            = shift;
    my $arch             = shift;
    my $channel          = shift;

    unless( ref $self ) {
        $self = fields::new( $self );
    }
    $self->{pacmanConfFile}       = $pacmanConfFile;
    $self->{repoDir}              = $repoDir;
    $self->{repoHistoriesDir}     = $repoHistoriesDir;
    $self->{upgradeSuccessTs}     = time();
    $self->{repositoryPositionTs} = $self->{upgradeSuccessTs};
    $self->{repoHistories}        = undef; # allocated as needed
    $self->{isModified}           = 0;

    $self->{repos} = {};
    foreach my $repoName ( keys %$repos ) {
        my $rawServerName = $repos->{$repoName};
        if( $rawServerName =~ m!/$! ) {
            $rawServerName = substr( $rawServerName, 0, -1 );
        }
        my $serverName = $rawServerName;
        $serverName =~ s!\$arch!$arch!g;
        $serverName =~ s!\$channel!$channel!g;

        $self->{repos}->{$repoName} = {
            'server' => $serverName,
            'rawcontent' => "[\$dbName]\nServer = $serverName\n\n"
        };
    }
    return $self;
}

##
# Save this state back to the standard locations in the filesystem on a device.
sub save {
    my $self = shift;

    my $json = {
        'upgradeSuccessTs'     => UBOS::Utils::rfc3339string2time( time() ),
        'repositoryPositionTs' => $self->{repositoryPositionTs} ? UBOS::Utils::rfc3339string2time( $self->{repositoryPositionTs} ) : undef
    };
    UBOS::Utils::writeJsonToFile( $LAST_UPDATE_JSON_FILE, $json );

    if( -e $LAST_UPDATE_FILE ) {
        UBOS::Utils::deleteFile( $LAST_UPDATE_FILE );
    }
}

##
##
# Returns true if this RatchetState is different from the current state on disk, and
# needs to be saved.
sub isModified {
    my $self = shift;

    return $self->{isModified};
}

##
# Determine whether the ratchet is already active on this device, or whether
# we still are pre-ratchet.
sub isRatchetActive {
    my $self = shift;

    foreach my $repoName ( keys %{$self->{repos}} ) {
        my $currentTs = $self->repoCurrentTsFor( $repoName );
        if( $currentTs ) {
            return 1;
        }
    }
    return 0; # not one of them
}

##
# Return the wall clock time when the device was last successfully upgraded
sub upgradeSuccessTs {
    my $self = shift;

    return $self->{upgradeSuccessTs};
}

##
# Return the timestamp the represents the position of the ratchet
sub repositoryPositionTs {
    my $self = shift;

    return $self->{repositoryPositionTs};
}

##
# Return the list of repo names
# return: repo names
sub repoNames {
    my $self = shift;

    return sort keys %{$self->{repos}};
}

##
# Obtain the timestamp that is active for the repo with this name.
# return: undef if not on the ratchet
sub repoCurrentTsFor {
    my $self     = shift;
    my $repoName = shift;

    my $historyJson = $self->_ensureRepoHistoryFor( $repoName );
    unless( $historyJson ) {
        return undef;
    }
    my $lastFoundTs = undef;
    foreach my $historyElement ( @{$historyJson->{history}} ) {
        my $foundTs = UBOS::Utils::rfc3339string2time( $historyElement->{tstamp} );
        if( $foundTs > $self->{repositoryPositionTs} ) {
            # too far
            last;
        }
        $lastFoundTs = $historyElement;
    }
    return $lastFoundTs;
}

## Obtain the timestamp after the active one for the repo with this name
# return: undef if not on the ratchet, or the current one is HEAD
sub repoNextTsFor {
    my $self     = shift;
    my $repoName = shift;

    my $historyJson = $self->_ensureRepoHistoryFor( $repoName );
    unless( $historyJson ) {
        return undef;
    }
    foreach my $historyElement ( @{$historyJson->{history}} ) {
        my $foundTs = UBOS::Utils::rfc3339string2time( $historyElement->{tstamp} );
        if( $foundTs > $self->{repositoryPositionTs} ) {
            return $foundTs;
        }
    }
    return undef;
}

##
# Helper to populate the repoHistories cache for the given repo, like 'os'
# $repoName: name of the repo
# return: has representing history.json
sub _ensureRepoHistoryFor {
    my $self     = shift;
    my $repoName = shift;

    unless( exists( $self->{repoHistories}->{$repoName})) {
        unless( exists( $self->{repos}->{$repoName} )) {
            error( 'Repo does not exist', $repoName );
            return undef;
        }
        my $repoHistoriesDir = $self->{repoHistoriesDir};
        my $file = "$repoHistoriesDir/$repoName/history.json";
        my $url  = $self->{repos}->{$repoName}->{server} . '/history.json';

        unless( -d "$repoHistoriesDir/$repoName" ) {
            UBOS::Utils::mkdirDashP( "$repoHistoriesDir/$repoName" );
        }

        $file = UBOS::Utils::ensureCachedFileUpToDate( $file, $url );
        if( $file ) {
            $self->{repoHistories}->{$repoName} = UBOS::Utils::readJsonFromFile( $file );
        } else {
            # Most likely, this repo does not have a history: if so, return undef
            # (Could also be it had a history and not any more, or got deleted entirely)
            return undef;
        }
    }
    return $self->{repoHistories}->{$repoName};
}

##
# Return a new RatchetState that is this RatchetState but at the provided time.
# This may return $self if we are already at HEAD.
sub skipTo {
    my $self          = shift;
    my $updateSkipTo  = shift;

    my $ret = fields::new( 'UBOS::RatchetState' );
    $ret->{repos}                = $self->{repoDreposir};
    $ret->{upgradeSuccessTs}     = $self->{upgradeSuccessTs};
    $ret->{repositoryPositionTs} = $updateSkipTo;
    $ret->{repoHistories}        = $self->{repoHistories};
    $ret->{isModified}           = 1;

    return $ret;
}

##
# Return a new RatchetState that ratchets one forward from here. To not go
# beyond the provided timestamp.
# This may return $self if we are already at HEAD, or the provided timestamp
# has been reached
sub ratchetNext {
    my $self      = shift;
    my $updateTo  = shift || 10**16; # something very large but still integer

    # We are looking for the smallest timestamp beyond the current position on which
    # any of the history.json has an entry

    my $found = undef;
    foreach my $repoName ( keys %{$self->{repos}} ) {
        my $nextTs = $self->repoNextTsFor( $repoName );
        if( $nextTs ) {
            if( !$found || $nextTs < $found ) {
                $found = $nextTs;
            }
        }
    }
    unless( $found ) {
        return $self;
    }
    if( $found > $updateTo ) {
        return $self;
    }

    my $ret = fields::new( 'UBOS::RatchetState' );
    $ret->{repos}                = $self->{repos};
    $ret->{upgradeSuccessTs}     = $self->{upgradeSuccessTs};
    $ret->{repositoryPositionTs} = $found;
    $ret->{repoHistories}        = $self->{repoHistories};
    $ret->{isModified}           = 1;

    return $ret;
}

##
# Regenerate the /etc/pacman.conf file.
# $channel: use this as the value for $channel in the repo URLs, or, if not
#    given, use value of /etc/ubos/channel
sub regeneratePacmanConf {
    my $self = shift;

    my $channel = UBOS::Utils::channel();
    my $pacmanConfFile = $self->{pacmanConfFile};
    my $oldPacmanConf = UBOS::Utils::slurpFile( $pacmanConfFile );

    my $preamble = $oldPacmanConf;
    if( $oldPacmanConf =~ m!^(.*?)$PACMAN_CONF_SEP!s ) {
        # zap the trailer
        $preamble = $1;
    }
    $preamble =~ s!\s+$!!; # zap white space at end
    $preamble .= "\n\n" . $PACMAN_CONF_SEP . "\n\n";

    my $pacmanConf = $preamble;

    foreach my $repoName( sort keys %{$self->{repos}} ) {
        my $dbName = dbNameWithTimestamp( $repoName, $self->repoCurrentTsFor( $repoName ));

        my $toAdd  = $self->{repos}->{$repoName}->{rawcontent};

        $toAdd =~ s!#.*$!!gm; # remove comments -- will confuse the user
        $toAdd =~ s!^\s+!!gm; # leading white space
        $toAdd =~ s!\s+$!!gm; # trailing white space
        $toAdd =~ s!\$dbName!$dbName!g;
        $toAdd =~ s!\$channel!$channel!g;

        $pacmanConf .= "\n" . $toAdd . "\n";
    }

    unless( $pacmanConf eq $oldPacmanConf ) {
        UBOS::Utils::saveFile( $pacmanConfFile, $pacmanConf );
    }
    return undef;
}

##
# Save the entire pacman.conf file. This is used during install.
sub savePacmanConfig {
    my $self           = shift;
    my $depotRoot      = shift;
    my $sigLevelString = shift;
    my $arch           = shift || UBOS::Utils::arch();
    my $channel        = shift || UBOS::Utils::channel();

    my $errors = 0;
    my $content = <<END;
#
# Pacman config file for UBOS
#

[options]
Architecture = $arch
CheckSpace

SigLevel           = $sigLevelString
LocalFileSigLevel  = $sigLevelString
RemoteFileSigLevel = $sigLevelString

$PACMAN_CONF_SEP


END

    foreach my $repoName ( sort keys %{$self->{repos}} ) {
        my $server = $self->{repos}->{$repoName}->{server};
        $server =~ s!\$depotRoot!$depotRoot!g;
        $server =~ s!\$channel!$channel!g;

        my $dbName = dbNameWithTimestamp( $repoName, $self->repoCurrentTsFor( $repoName ));

        $content .= "\n";
        $content .= "[$dbName]\n";
        $content .= "Server = $server\n";
    }

    unless( UBOS::Utils::saveFile( $self->{pacmanConfFile}, $content, 0644 )) {
        ++$errors;
    }
    return $errors;
}

##
# Save the pacman repositories to repositories.d.
# This is only here because it is similar code, but not actually a method of RachetState
sub savePacmanRepositories {
    my $activeRepos   = shift;
    my $disabledRepos = shift;
    my $repoDir       = shift;
    my $depotRoot     = shift;

    my $errors = 0;
    unless( -d $repoDir ) {
        unless( UBOS::Utils::mkdir( $repoDir )) {
            ++$errors;
        }
    }

    foreach my $dbKey ( sort keys %$activeRepos ) {
        my $dbValue = $activeRepos->{$dbKey};
        $dbValue =~ s!\$depotRoot!$depotRoot!g;

        my $content = "[\$dbName]\n"; # This is being replaced when pacman.conf is generated
        $content .= "Server = $dbValue\n";

        unless( UBOS::Utils::saveFile( "$repoDir/$dbKey", $content, 0644 )) {
            ++$errors;
        }
    }
    foreach my $dbKey ( sort keys %$disabledRepos ) {
        my $dbValue = $disabledRepos->{$dbKey};
        $dbValue =~ s!\$depotRoot!$depotRoot!g;

        my $content = "# [\$dbName]\n"; # This is being replaced when pacman.conf is generated
        $content .= "# Server = $dbValue\n";

        unless( UBOS::Utils::saveFile( "$repoDir/$dbKey", $content, 0644 )) {
            ++$errors;
        }
    }
    return $errors;
}

##
# Helper to construct the db name given a repo name and a timestamp.
# $repoName
# $ts: timestamp in epoch millis, or undef if no timestamp
# return dbName
sub dbNameWithTimestamp {
    my $repoName = shift;
    my $ts       = shift;

    my $ret;
    if( $ts ) {
        $ret = UBOS::Utils::time2rfc3339String( $ts );
        $ret =~ s![:-]!!g;
        $ret = "$repoName-$ret";
    } else {
        $ret = $repoName;
    }
    return $ret;
}

1;
