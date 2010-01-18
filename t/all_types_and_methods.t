#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;
use Test::More tests => 78;

use Config::Strict;
use Declare::Constraints::Simple -All;

my %default = (
    b1    => 1,
    s2    => 'meh',
    enum1 => undef,
    nvar  => 2.3,
    aref1 => [ 'meh' ],
    href1 => { 'k' => 'v' },
    pos1  => 2,
    pos   => 3,
);
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
            CodeRef  => 'cref1',
            Custom   => {                                  # Custom routines
#                pos1 => sub            { $_[ 0 ] > 0 },        TODO?
#pos1 => And( IsNumber, Matches( qr/^[^-]+$/ ) ),
                pos  => And( IsNumber, Matches( qr/^[^-]+$/ ) ),
                nest => IsA( 'Config::Strict' ),
            }
        },
        required => [ qw( b1 nvar ) ],                     # Required parameters
        defaults => \%default
    }
);
#print Dumper $config;

# Underlying data accessors
is_deeply( { $config->param_hash }, \%default, 'param_hash' );
is_deeply(
    [ $config->param_array ],
    [ map { [ $_ => $default{ $_ } ] } keys %default ],
    'param_array'
);
is_deeply( [ $config->all_set_params ], [ keys %default ], 'all_set_params' );

# Bad params
my_eval_ok( 'get_param', $config, 'blah' );
my_eval_ok( 'set_param', $config, 'blah' => 0 );
ok( !$config->param_exists( 'blah' ), 'blah' );
ok( !$config->param_is_set( 'blah' ), 'blah unset' );

# Set/Existent params
for my $p ( $config->all_params ) {
    # Check that all existing keys are valid
    ok( $config->param_exists( $p ), "$p exists" );
    # Check set/nonset params
    if ( exists $default{ $p } ) {
        ok( $config->param_is_set( $p ), "$p set" );
        # Validate defaults
        ok( $config->validate( $p => $config->get_param( $p ) ),
            "$p default valid" );
    }
    else {
        ok( !$config->param_is_set( $p ), "$p not set" );
    }
}

# Unset checks
ok( $config->param_is_set( 's2' ), 's2 set' );
$config->unset_param( 's2' );
ok( !$config->param_is_set( 's2' ), 's2 unset' );
ok( $config->param_exists( 's2' ),  's2 exists' );
# Required parameters
ok( $config->param_is_required( 'b1' ),  'b1 required' );
ok( !$config->param_is_required( 'b2' ), 'b2 not required' );
my_eval_ok( 'unset_param', $config, 'b1' );
ok( $config->param_is_set( 'b1' ), 'b1 still set' );

# Profile checks

# Int
ok( $config->validate( 'ivar' => 2 ), 'int validate' );
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

# Refs
my_eval_ok( 'set_param', $config, 'aref1' => {} );
my_eval_ok( 'set_param', $config, 'href1' => [] );
my_eval_ok( 'set_param', $config, 'cref1' => 'meh' );
ok( $config->set_param( 'aref1' => [] ), 'aref set' );
ok( $config->set_param( 'href1' => {} ), 'href set' );
ok( $config->set_param( 'cref1' => sub { 1 } ), 'cref set' );

# Custom
is( $config->get_param( 'pos' ), 3, 'pos' );
#my_eval_ok( 'set_param', $config, 'pos1' => -2 );
my_eval_ok( 'set_param', $config, 'pos' => -2 );
my_eval_ok( 'set_param', $config, 'ivar' => 5, 'pos' => -5 );
$config->set_param( pos => 2.22 );
is_deeply(
    [ $config->get_param( qw( ivar pos ) ) ] => [ 2, 2.22 ],
    "posints"
);
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
    if ( $subname eq 'Config::Strict::set_param' and @params % 2 == 0 ) {
        ok( !$object->validate( @params ), "setting @params invalid" );
    }
}

sub _error {
    local $_ = shift;
    s/^(.+?)\s+at.+$/$1/sg;
    'error: ' . $_;
}
