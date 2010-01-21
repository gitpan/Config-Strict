#!/usr/bin/perl
use strict;
use warnings;
use Test::More;

if ( not $ENV{ TEST_AUTHOR } ) {
    my $msg = 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
    plan( skip_all => $msg );
}

eval "use Test::GreaterVersion";
plan skip_all => "Test::GreaterVersion required for checking versions" if $@;
has_greater_version_than_cpan('Config::Strict');
done_testing(1);