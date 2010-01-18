#!/usr/bin/perl
use strict;
use warnings;
use diagnostics;
use Test::More tests => 10;

use Config::Strict;

# No name
eval { Config::Strict->new( {} ) };
like( $@ => qr/'name' key needed/, _error( $@ ) );

# No params
eval { Config::Strict->new( { name => 'meh' } ) };
like( $@ => qr/'params' key/, _error( $@ ) );

# Bad param hash
eval {
    Config::Strict->new( {
            name   => 'meh',
            params => { Bool => { 'b1' => 'b2' } }
        }
    );
};
like( $@ => qr/Not a valid parameter ref/, _error( $@ ) );
eval {
    Config::Strict->new( {
            name   => 'meh',
            params => { Enum => [ 'e' ] }
        }
    );
};
like( $@ => qr/Not a HashRef/, _error( $@ ) );

# Missing required params
eval {
    Config::Strict->new( {
            name     => 'meh',
            params   => { Bool => 'b1' },
            required => [ 'b1' ],
        }
    );
};
like( $@ => qr/no 'b1' key present/i, _error( $@ ) );
eval {
    Config::Strict->new( {
            name   => 'meh',
            params => { Bool => [ qw( b1 b2 ) ] },
        }
    );
};
like( $@ => qr/::meh already exists/, _error( $@ ) );
eval {
    Config::Strict->new( {
            name     => 'mehh',
            params   => { Bool => [ qw( b1 b2 ) ] },
            required => [ '_all' ],
            defaults => { b1 => 1 },
        }
    );
};
like( $@ => qr/no 'b2' key present/i, _error( $@ ) );

# Invalid default value
eval {
    Config::Strict->new( {
            name     => 'mehhh',
            params   => { Bool => 'b1' },
            required => [ 'b1' ],
            defaults => { b1 => 2 },
        }
    );
};
like( $@ => qr/no value matches/i, _error( $@ ) );

# Duplicate params-type constraint name
my $ok = Config::Strict->new( { name => 'Test', params => { Int => 'i' } } );
eval { Config::Strict->new( { name => 'Test', params => { Int => 'i' } } ) };
like( $@ => qr/already exists/, _error( $@ ) );

# No literal subs (TODO)
eval {
    Config::Strict->new( {
            name   => 'mehhhh',
            params => {
                Custom => {
                    s => sub { $_[ 0 ] == 1 }
                },
            }
        }
    );
};
like( $@ => qr/custom validation must be done with Declare/i, _error( $@ ) );

sub _error {
    local $_ = shift;
    s/\s+at.+$//sg;
    s/\W+\$VAR.+$//sg;
    'error: ' . $_;
}
