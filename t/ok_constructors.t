#!/usr/bin/perl
use strict;
use warnings;
use Test::More tests => 4;

use Config::Strict;

ok(
    Config::Strict->new( {
            params => { Bool => 'b' }
        }
    ),
    'basic'
  );

ok(
    Config::Strict->new( {
            params   => { Bool => 'b' },
            defaults => { 'b' => 0 }
        }
    ),
    'defaults'
  );

ok(
    Config::Strict->new( {
            params   => { Bool => 'b' },
            required => [ 'b' ],
            defaults => { 'b' => 0 }
        }
    ),
    'required'
  );

ok(
    Config::Strict->new( {
            params   => { Bool => 'b', Int => 'i', Num => 'n' },
            required => [ qw( i n ) ],
            defaults => { 'i' => 10, 'n' => 2.2 }
        }
    ),
    'some required'
  );
  
