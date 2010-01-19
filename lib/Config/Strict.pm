package Config::Strict;
use warnings;
use strict;
use Data::Dumper;
use Scalar::Util qw(blessed weaken);
$Data::Dumper::Indent = 0;
use Carp qw(confess croak);

our $VERSION = '0.04';

use Declare::Constraints::Simple -All;

# TODO: Allow user type registration
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

sub _validate_defaults {
    my ( $default, $required ) = @_;
    for ( @$required ) {
        confess "$_ is a required parameter but isn't in the defaults"
            unless exists $default->{ $_ };
    }
}

# Constructor
sub new {
    my $class = shift;
    my $opts  = shift;
    confess "Invalid construction arguments: @_" if @_;

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

    # Validate defaults
    _validate_defaults( $default, $required );

    # Construct
    my $self = bless( {
            _required => { map { $_ => 1 } @$required }
            ,    # Convert to hash lookup
            _profile => $profile,
        },
        $class
    );
    $self->set_param( %$default );
    $self;
} ## end sub new

sub get_param {
    my $self = shift;
    $self->_get_check( @_ );
    my $params = $self->{ _params };
#    print Dumper \@_;
    return (
        wantarray ? ( map { $params->{ $_ } } @_ ) : $params->{ $_[ 0 ] } );
}

sub set_param {
    my $self = shift;
    $self->_set_check( @_ );
    my %pv = @_;
    while ( my ( $p, $v ) = each %pv ) {
        $self->{ _params }{ $p } = $v;
    }
    1;
}

sub unset_param {
    my $self = shift;
    $self->_unset_check( @_ );
    delete $self->{ _params }{ $_ } for @_;
}

sub param_is_set {
    my $self = shift;
    croak "No parameter passed" unless @_;
    return exists $self->{ _params }{ $_[ 0 ] };
}

sub all_set_params {
    keys %{ shift->{ _params } };
}

sub param_hash {
    %{ shift->{ _params } };
}

sub param_array {
    my $self = shift;
#    my @array;
#    while ( my ( $p, $v ) = each %{ $self->{ _params } } ) {
#        push @array, [ $p => $v ];
#    }
#    @array;
    my $params = $self->{ _params };
    map { [ $_ => $params->{ $_ } ] } keys %$params;
}

sub param_exists {
    my $self = shift;
    croak "No parameter passed" unless @_;
    return exists $self->{ _profile }{ $_[ 0 ] };
}

sub all_params {
    keys %{ shift->{ _profile } };
}

sub get_profile {
    my $self = shift;
    croak "No parameter passed" unless @_;
    $self->{ _profile }{ $_[ 0 ] };
}

sub _get_check {
    my ( $self, @params ) = @_;
    my $profile = $self->{ _profile };
    _profile_check( $profile, $_ ) for @params;
}

sub _set_check {
    my ( $self, %value ) = @_;
    my $profile = $self->{ _profile };
    while ( my ( $k, $v ) = each %value ) {
        _profile_check( $profile, $k => $v );
    }
}

sub _unset_check {
    my ( $self, @params ) = @_;
    # Check against required parameters
    for ( @params ) {
        confess "$_ is a required parameter" if $self->param_is_required( $_ );
    }
    # Check against profile
    my $profile = $self->{ _profile };
    _profile_check( $profile, $_ ) for @params;
}

sub validate {
    my $self = shift;
    confess "No parameter-values pairs passed" unless @_ >= 2;
    confess "Uneven number of parameter-values pairs passed" if @_ % 2;
    my %pair = @_;
    while ( my ( $param, $value ) = each %pair ) {
        return 0
            unless $self->param_exists( $param )
                and $self->get_profile( $param )->( $value );
    }
    1;
}

sub param_is_required {
    my ( $self, $param ) = @_;
    return unless $param;
    return 1 if $self->{ _required }{ $param };
    0;
}

# Static validator from profile
sub _profile_check {
    my ( $profile, $param ) = ( shift, shift );
    confess "No parameter passed" unless defined $param;
    confess "Invalid parameter: $param doesn't exist"
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
                $_ => $sub
                }
                keys %{ $param->{ Custom } }
        ),
    );
    \%profile;
} ## end sub _create_profile

1;
