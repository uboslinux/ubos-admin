#!/usr/bin/perl
#
# A do-nothing BackupOperation.
#
# Copyright (C) 2014 and later, Indie Computing Corp. All rights reserved. License: see package.
#

use strict;
use warnings;

package UBOS::BackupOperations::NoOp;

use base qw( UBOS::BackupOperation );
use fields;

##
# Constructor
# Ignore all arguments
sub new {
    my $self = shift;

    unless( ref( $self )) {
        $self = fields::new( $self );
    }
    # no need to invoke superclass constructor

    return $self;
}

##
# Is this a No op?
sub isNoOp {

    return 1;
}

##
# Override and do nothing
sub analyze {

    return 1;
}

##
# Override and do nothing
sub setSitesToBackUp {

    return 1;
}

##
# Override and do nothing
sub getSitesToSuspendResume {

    return 1;
}

##
# Override and do nothing
sub constructCheckPipeline {

    return 1;
}

##
# Override and do nothing
sub doBackup {

    return 1;
}

##
# Override and do nothing
sub doUpload {

    return 1;
}

##
# Override and do nothing
sub finish {

    return 1;
}

1;
