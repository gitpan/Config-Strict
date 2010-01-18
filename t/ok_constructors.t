#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 4;

use Config::Strict;
use Moose::Util::TypeConstraints qw(find_type_constraint);

ok(
    Config::Strict->new( {
            name   => 'Test1',
            params => { Bool => 'b' }
        }
    ),
    'basic'
  );

ok(
    Config::Strict->new( {
            name     => 'Test2',
            params   => { Bool => 'b' },
            defaults => { 'b' => 0 }
        }
    ),
    'defaults'
  );

ok(
    Config::Strict->new( {
            name     => 'Test3',
            params   => { Bool => 'b' },
            required => [ 'b' ],
            defaults => { 'b' => 0 }
        }
    ),
    'required'
  );

ok(
    Config::Strict->new( {
            name     => 'Test4',
            params   => { Bool => 'b', Int => 'i', Num => 'n' },
            required => [ qw( i n ) ],
            defaults => { 'i' => 10, 'n' => 2.2 }
        }
    ),
    'some required'
  );

#ok(
# TODO
#    my $cs_sub = Config::Strict->new( {
#            name   => 'Test5',
#            params => {
#                Custom => {
#                    c => sub { $_[ 0 ] == 1 }
#                }
#            },
#            defaults => { c => 1 }
#        }
#    )
#  );
