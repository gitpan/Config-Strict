package Config::Strict;
use warnings;
use strict;
use Data::Dumper;
use Carp;

our $VERSION = '0.02';

use Moose;
use Moose::Util::TypeConstraints;
use Declare::Constraints::Simple -All;

# Constructor
around BUILDARGS => sub {
    my ( $new, $class ) = ( shift, shift );
    my $opts = shift;
    confess "Invalid construction arguments: @_" if @_;
    my ( @require, %default, $profile );
    {    # Localize these
        my ( $st_name, %param );
        croak "Subtype name needed"
            unless ( $st_name = delete $opts->{ name } );
        croak "No parameters!"
            unless exists $opts->{ params }
                and ( %param = %{ delete $opts->{ params } } );
        # Check parameter hash structure
        _validate_param_hash( \%param );

        @require = @{ delete $opts->{ required } }
            if exists $opts->{ required };
        %default = %{ delete $opts->{ defaults } }
            if exists $opts->{ defaults };
        confess sprintf( "Invalid option(s): %s", Dumper( $opts ) ) if %$opts;

        # Register namespace, profile
        $profile = _create_profile( \%param );
        # Check defaults against require, profile
        @require = keys %$profile
            if @require and $require[ 0 ] eq '_all';
        my @bad = grep { not exists $default{ $_ } } @require;
        confess "Not all required parameters set in defaults (missing @bad)"
            if @bad;
        while ( my ( $k, $v ) = each %default ) {
            _profile_check( $profile, $k => $v );
        }
        # Create our custom subtype
        _register_subtype( $st_name, \@require, $profile );
    }

    # Construct
    $class->$new(
        params  => \%default,
        profile => $profile,
    );
};

# Create parent subtype (just inherits HashRef)
subtype 'Config::Strict::Params' => as 'HashRef';
has 'params'                     => (
    is       => 'ro',
    isa      => 'Config::Strict::Params',
    required => 1,
#    default => sub { {} },
    traits  => [ 'Hash' ],
    handles => {
        get_param => 'get',
        set_param => 'set',
#        all_set_params => 'keys',
        param_set => 'exists'
    },
);
before 'get_param' => \&_get_check;
before 'set_param' => \&_set_check;

has 'profile' => (
    is       => 'ro',
    isa      => 'HashRef[CodeRef]',
    required => 1,
    traits   => [ 'Hash' ],
    handles  => {
        get_profile     => 'get',
        param_exists    => 'exists',
        all_params      => 'keys',
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

sub _register_subtype {
    my ( $name, $require, $profile ) = @_;
    $require ||= [];
    $profile ||= {};
    subtype(
        "Config::Strict::Params::$name" => as( 'Config::Strict::Params' ) =>
            where {
            IsHashRef( HasAllKeys( @$require ), OnHashKeys( %$profile ) );
        }
    );
#    print Dumper $st;
}

no Moose;

# Static validator from profile
sub _profile_check {
    my ( $profile, $param ) = ( shift, shift );
    confess "No parameter passed" unless defined $param;
    confess "Config parameter $param doesn't exist"
        unless exists $profile->{ $param };
    if ( @_ ) {
        my $value = shift;
        no warnings 'uninitialized';
#        print "Checking $param setting to $value with " , $profile{$param} , "\n";
        confess sprintf( "Invalid value (%s) for config parameter $param",
            defined $value ? $value : 'undef' )
            unless $profile->{ $param }->( $value );
    }
}

sub _validate_param_hash {
    my $param         = shift;
    my $param_profile = OnHashKeys( (
            map { $_ => Or( HasLength, IsArrayRef ) }
                qw( Bool Int Num Str Regexp ArrayRef HashRef )
        ),
        Enum   => IsHashRef( -keys => HasLength, -values => IsArrayRef ),
        Custom => IsHashRef( -keys => HasLength, -values => IsCodeRef ),
    );
    my $result = $param_profile->( $param );
    confess $result->message unless $result->is_valid;
    1;
}

sub _flatten {
    my $val = shift;
    return unless defined $val;
    return ( $val ) unless ref $val;
    return @{ $val } if ref $val eq 'ARRAY';
    confess "Not a valid parameter ref: " . ref $val;
}

sub _create_profile {
    my $param   = shift;
    my %profile = (
        ( map { $_ => IsOneOf( 0, 1 ) } _flatten( $param->{ Bool } ) ),
        ( map { $_ => IsNumber } _flatten( $param->{ Num } ) ),
        ( map { $_ => IsInt } _flatten( $param->{ Int } ) ),
        ( map { $_ => HasLength } _flatten( $param->{ Str } ) ),
        (
            map { $_ => IsOneOf( @{ $param->{ Enum }{ $_ } } ) }
                keys %{ $param->{ Enum } }
        ),
        ( map { $_ => IsArrayRef } _flatten( $param->{ ArrayRef } ) ),
        ( map { $_ => IsHashRef } _flatten( $param->{ HashRef } ) ),
        ( map { $_ => IsCodeRef } _flatten( $param->{ CodeRef } ) ),
        ( map { $_ => IsRegex } _flatten( $param->{ RegexpRef } ) ),
        (
            map {
                my $sub = $param->{ Custom }{ $_ };
                confess "Not a coderef" unless ref $sub eq 'CODE';
                $_ => $sub
                }
                keys %{ $param->{ Custom } }
        ),
    );
#    print Dumper \%profile;
    \%profile;
}

1;