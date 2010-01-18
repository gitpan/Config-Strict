#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use Test::More tests => 6;

use Config::Strict;

# 1.
eval { Config::Strict->new( {} ) };
ok( $@ =~ /name needed/i, _error( $@ ) );
# 2.
eval { Config::Strict->new( { name => 'meh' } ) };
ok( $@ =~ /no parameters/i, _error( $@ ) );
# 3.
eval {
    Config::Strict->new( { 
        name => 'meh', 
        params => { Bool => { 'b1' => 'b2' } } 
    } );
};
ok( $@ =~ /HASH/, _error( $@ ) );
# 4.
eval {
    Config::Strict->new( {
            name     => 'meh',
            params   => { Bool => 'b1' },
            required => [ 'b1' ],
        }
    );
};
ok( $@ =~ /defaults/i, _error( $@ ) );
# 5.
eval {
    Config::Strict->new( {
            name     => 'meh',
            params   => { Bool => 'b1' },
            required => [ 'b1' ],
            defaults => { b1 => undef },
        }
    );
};
ok( $@ =~ /invalid value/i, _error( $@ ) );
# 6.
eval {
    Config::Strict->new( {
            name     => 'meh',
            params   => { Bool => [ qw( b1 b2 ) ] },
            required => [ '_all' ],
            defaults => { b1 => 1 },
        }
    );
};
ok( $@ =~ /required parameters/i, _error( $@ ) );

sub _error {
    local $_ = shift;
    s/\s+at.+$//sg;
    s/\$VAR.+$//sg;
    'error: ' . $_;
}
