package Config::Strict;
use warnings;
use strict;
use Data::Dumper;
use Scalar::Util qw(blessed weaken);
$Data::Dumper::Indent = 0;
use Carp;

our $VERSION = '0.03';

use Moose;
use Moose::Util::TypeConstraints qw(find_type_constraint);
use Declare::Constraints::Simple -All;

# Constructor
around BUILDARGS => sub {
    my ( $new, $class ) = ( shift, shift );
    my $opts = shift;
    confess "Invalid construction arguments: @_" if @_;

    # Get a type name
    croak "Subtype 'name' key needed"
        unless ( my $constraint_name = delete $opts->{ name } );
    # Prefix our type namespace
    $constraint_name = 'Config::Strict::Params::' . $constraint_name;

    # Get the parameter hash
    croak "No 'params' key in constructor"
        unless exists $opts->{ params }
            and ( my $param = delete $opts->{ params } );

    # Get required, default values
    my $required = delete $opts->{ required } || [];
    my $default  = delete $opts->{ defaults } || {};

    # Check that options hash now empty
    confess sprintf( "Invalid option(s): %s", Dumper( $opts ) )
        if %$opts;

    # Create the configuration profile
    my $profile = _create_profile( $param );
    # Set required to all parameters if == [ _all ]
    @$required = keys %$profile
        if @$required == 1 and $required->[ 0 ] eq '_all';

    # Register the Moose type constraint
#    my $constraint =
    _register_type( $constraint_name, $required, $profile );

    # Set the param attribute
    _set_params_attribute( $constraint_name );

    # Construct
    $class->$new(
        params              => $default,
        required_parameters => $required,
        profile             => $profile,
#        constraint => $constraint,
    );
};

# Create parent subtype (just inherits HashRef)
#subtype 'Config::Strict::Params' => as 'HashRef';
sub _set_params_attribute {
    my ( $isa ) = @_;
    my $constraint = has 'params' => (
        is       => 'ro',
        isa      => $isa,
        required => 1,
        traits   => [ 'Hash' ],
        handles  => {
            get_param      => 'get',
            set_param      => 'set',
            unset_param    => 'delete',
            param_is_set   => 'exists',
            all_set_params => 'keys',
            param_hash     => 'elements',
            param_array    => 'kv',
        },
    );
    before 'get_param'   => \&_get_check;
    before 'set_param'   => \&_set_check;
    before 'unset_param' => \&_unset_check;
}

has 'required_parameters' => (
    is      => 'ro',
    isa     => 'ArrayRef[Str]',
    default => sub { [] },
);

has 'profile' => (
    is       => 'ro',
    isa      => 'HashRef[CodeRef]',
    required => 1,
    traits   => [ 'Hash' ],
    handles  => {
        get_profile  => 'get',
        param_exists => 'exists',
        all_params   => 'keys',
    },
);

sub _get_check {
    my ( $self, @params ) = @_;
    my $profile = $self->profile;
    _profile_check( $profile, $_ ) for @params;
    inner();
}

sub _set_check {
    my ( $self, %value ) = @_;
    my $profile = $self->profile;
    while ( my ( $k, $v ) = each %value ) {
        _profile_check( $profile, $k => $v );
    }
    inner();
}

sub _unset_check {
    my ( $self, @params ) = @_;
    # Check against required parameters
    for ( @params ) {
        confess "$_ is a required parameter" if $self->param_is_required( $_ );
    }
    # Check against profile
    my $profile = $self->profile;
    _profile_check( $profile, $_ ) for @params;
    inner();
}

sub _register_type {
    my ( $name, $required, $profile ) = @_;

    # Check that $name doesn't exist
    confess "Type constraint $name already exists"
        if find_type_constraint( $name );

    $required ||= [];
    confess "No profile" unless %$profile;

    my $config_profile =
        And( HasAllKeys( @$required ), OnHashKeys( %$profile ) );
    Moose::Util::TypeConstraints::_create_type_constraint(
        $name,                                # name
        find_type_constraint( 'HashRef' ),    # parent
        $config_profile,                      # constraint
        sub {
            sprintf( "%s (%s)",
                $config_profile->( $_ )->message,
                ( defined $_ ? Dumper( $_ ) : 'undef' ) );
            }                                 # message
    );
}

no Moose;

sub validate {
    my $self = shift;
    confess "No parameter-values pairs passed" unless @_ >= 2;
    confess "Uneven number of parameter-values pairs passed" if @_ % 2;
    my %pair = @_;
    while ( my ( $param, $value ) = each %pair ) {
        return 0 unless defined $param;
        return 0
            unless $self->param_exists( $param )
                and $self->get_profile( $param )->( $value );
    }
    1;
}

sub param_is_required {
    my ( $self, $param ) = @_;
    return unless $param;
    return scalar grep { $param eq $_ } @{ $self->required_parameters };
}

# Static validator from profile
sub _profile_check {
    my ( $profile, $param ) = ( shift, shift );
    confess "No parameter passed" unless defined $param;
    confess "Invalid parameter name: $param doesn't exist"
        unless exists $profile->{ $param };
    if ( @_ ) {
        my $value  = shift;
        my $result = $profile->{ $param }->( $value );
        unless ( $result ) {
            # Failed validation
            confess $result->message
                if ref $result
                    and $result->isa( 'Declare::Constraints::Simple::Result' );
            confess sprintf( "Invalid value (%s) for config parameter $param",
                defined $value ? $value : 'undef' );
        }
    }
}

sub _validate_param_hash {
    my $param = shift;
    confess "No parameters passed"
        unless defined $param
            and ref $param
            and ref $param eq 'HASH'
            and %$param;
    my $param_profile = OnHashKeys( (
            map { $_ => Or( HasLength, IsArrayRef ) }
                qw( Bool Int Num Str Regexp ArrayRef HashRef )
        ),
        Enum => IsHashRef(
            -keys   => HasLength,
            -values => IsArrayRef
        ),
        Custom => IsHashRef(
            -keys   => HasLength,
            -values => IsCodeRef
        ),
    );
    my $result = $param_profile->( $param );
    confess $result->message unless $result;
    $result;
}

sub _flatten {
    my $val = shift;
    return unless defined $val;
    return ( $val ) unless ref $val;
    return @{ $val } if ref $val eq 'ARRAY';
    confess "Not a valid parameter ref: " . ref $val;
}

sub _create_profile {
    my $param = shift;
    # Check parameter hash structure
    _validate_param_hash( $param );

    # TODO: Make this class data and alterable
    my %type_registry = (
        Bool => IsOneOf( 0, 1 ),
        Num  => IsNumber,
        Int  => IsInt,
        Str  => HasLength,
#        Enum     => IsOneOf,   # Points to a hash
        ArrayRef => IsArrayRef,
        HashRef  => IsHashRef,
        CodeRef  => IsCodeRef,
        Regexp   => IsRegex
    );
    my %profile = (
        # Built-in types
        (
            map {
                my $type = $_;
                map { $_ => $type_registry{ $type } }
                    _flatten( $param->{ $_ } )
                } keys %type_registry
        ),
        (
            map { $_ => IsOneOf( @{ $param->{ Enum }{ $_ } } ) }
                keys %{ $param->{ Enum } }
        ),

        # Custom types
        (
            map {
                my $sub = $param->{ Custom }{ $_ };
                confess "Not a coderef"
                    unless ref $sub eq 'CODE';
                # TODO: wrap literal subs into a DCS profile
                # For now throw an error
                my $class = blessed( $sub->( 1 ) );
#                print $class;
                confess
"Custom validation must be done with Declare::Constraints::Simple profiles in $VERSION"
                    unless ( $class
                    and $class eq 'Declare::Constraints::Simple::Result' );
#                {
#                    $sub = sub {
#                        my $got = $sub->( $_[ 0 ] );
#                        Declare::Constraints::Simple::Result->new(
#                            valid => ( $got ? 1 : 0 ),
#                            message => $_[ 0 ] . " invalid"
#                        );
#                    };
#                    weaken( $sub );
#                }
                $_ => $sub
                }
                keys %{ $param->{ Custom } }
        ),
    );
    \%profile;
} ## end sub _create_profile

1;
