#!/usr/bin/perl

# lib.pl is the file where database specific things should live,
# whereever possible. For example, you define certain constants
# here and the like.

use strict;

use File::Basename;
use File::Path;
use File::Spec;

my $test_dir;
END { defined( $test_dir ) and rmtree $test_dir }

sub test_dir
{
    unless( defined( $test_dir ) )
    {
	$test_dir = File::Spec->rel2abs( File::Spec->curdir () );
	$test_dir = File::Spec->catdir ( $test_dir, "test_output_" . $$ );
	$test_dir .= "_" . basename($0, qr/\.[^.]*/);
	$test_dir = VMS::Filespec::unixify($test_dir) if $^O eq 'VMS';
	rmtree $test_dir;
	mkpath $test_dir;
    }

    return $test_dir;
}

1;
