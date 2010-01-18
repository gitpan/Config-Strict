#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 40;

use Config::Strict;
use Declare::Constraints::Simple -All;

my $tests = 0;

my $config = Config::Strict->new( {
        name   => "Example",    # Subtype name
        params => {             # Parameter names
            Bool   => [ qw( b1 b2 ) ],                     # Multiple parameters
            Int    => 'ivar',                              # One parameter
            Num    => 'nvar',
            Str    => [ qw( s1 s2 ) ],
            Enum   => { enum1 => [ qw( e1 e2 ), undef ] },
            Regexp => 're1',
            ArrayRef => 'aref1',
            HashRef  => 'href1',
            Custom   => {                                  # Custom routines
                pos1 => sub            { $_[ 0 ] > 0 },
                pos2 => And( IsNumber, Matches( qr/^[^-]+$/ ) ),
                nest => IsA( 'Config::Strict' ),
            }
        },
        required => [ qw( b1 nvar ) ],                     # Required parameters
        defaults => {                                      # Default values
            b1    => 1,
            s2    => 'meh',
            enum1 => undef,
            nvar  => 2.3,
            aref1 => [ 'meh' ],
            href1 => { 'k' => 'v' },
            pos1  => 2,
            pos2  => 3,
        },
    }
);
#print Dumper $config;

# Bad params
my_eval_ok( 'get_param', $config, 'blah' );

# Set/Existent params
my @set = qw( b1 s2 enum1 nvar aref1 href1 pos1 pos2 );
for my $p ( $config->all_params ) {
    # Check that all existing keys are valid
    ok( $config->param_exists( $p ), "$p exists" );
    # Check set/nonset params
    if ( grep { $p eq $_ } @set ) {
        ok( $config->param_set( $p ), "$p set" );
    }
    else {
        ok( !$config->param_set( $p ), "$p not set" );
    }
}

# Profile checks

# Int
ok( $config->set_param( 'ivar' => 2 ), 'int set_param' );
my_eval_ok( 'set_param', $config, 'ivar' => 1.1 );
my_eval_ok( 'set_param', $config, 'ivar' => 'meh' );
is( $config->get_param( 'ivar' ) => 2, 'int get_param' );

# Enum
is( $config->get_param( 'enum1' ) => undef, 'enum' );
$config->set_param( 'enum1' => 'e1' );
is( $config->get_param( 'enum1' ) => 'e1', 'enum' );
$config->set_param( 'enum1' => undef );
is( $config->get_param( 'enum1' ) => undef, 'enum undef' );
my_eval_ok( 'set_param', $config, 'enum1' => 'blah' );
#print Dumper $config;
my_eval_ok( 'set_param', $config, 'enum1' => 1 );
#print Dumper $config;

# Custom
is( $config->get_param( 'pos2' ), 3, 'pos2' );
my_eval_ok( 'set_param', $config, 'pos1' => -2 );
my_eval_ok( 'set_param', $config, 'pos2' => -2 );
my_eval_ok( 'set_param', $config, 'pos1' => 5, 'pos2' => -5 );
$config->set_param( pos1 => 100_000, pos2 => 2.22 );
is_deeply(
    [ $config->get_param( qw( pos1 pos2 ) ) ] => [ 100_000, 2.22 ],
    "posints"
);
$tests++;
$config->set_param(
    'nest' => Config::Strict->new( {
            name     => "Example::Nested",
            params   => { Bool => [ 'b1' ] },
            defaults => { b1 => 0 }
        }
    )
);
is( $config->get_param( 'nest' )->get_param( 'b1' ), 0, 'nested' );

# Subroutines

sub my_eval_ok {
    # Check for error
    my ( $subname, $object, @params ) = @_;
    $subname = "Config::Strict::$subname";
    no strict 'refs';
#    eval { $sub->( @params ) };
    eval { &{ $subname }( $object, @params ) };
    ok( $@, _error( $@ ) );
}

sub _error {
    local $_ = shift;
    s/^(.+?)\s+at.+$/$1/sg;
    'error: ' . $_;
}
