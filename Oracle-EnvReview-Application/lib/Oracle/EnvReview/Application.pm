package Oracle::EnvReview::Application;

=pod

=head1 NAME

Oracle::EnvReview::Application - definition of applications classes available.

=head1 DESCRIPTION

Oracle::EnvReview::Application is a spin-off of L<Oracle::EnvReview>
distribution.

The classes available under Oracle::EnvReview::Application are necessary both
in Windows and Linux, but L<Oracle::EnvReview> has specific requirements
available only in Linux.

A complete refactoring of namespace should be done by feature, separating
by namespace what require Linux, Windows and none of them.

=cut

use warnings;
use strict;
use Carp;
use Hash::Util qw(lock_keys);
use Set::Tiny 0.04;
use base 'Class::Accessor';

# VERSION

__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(qw(name version _patches home architecture));

sub new {
    my ( $class, $attribs_ref ) = @_;
    confess "must receive a hash reference as attributes"
      unless ( ( defined($attribs_ref) ) and ( ref($attribs_ref) eq 'HASH' ) );

    __PACKAGE__->_validate_attribs( [ 'name', 'version', 'patches' ],
        $attribs_ref );

    $attribs_ref->{home} = undef unless ( exists( $attribs_ref->{home} ) );
    $attribs_ref->{architecture} = undef
      unless ( exists( $attribs_ref->{architecture} ) );
    confess "attribute patches must be an array reference"
      unless ( ref( $attribs_ref->{patches} ) eq 'ARRAY' );

    # copy only what we want to avoid creating arbitrary attributes
    my $self = {
        home         => $attribs_ref->{home},
        name         => $attribs_ref->{name},
        version      => $attribs_ref->{version},
        architecture => $attribs_ref->{architecture},
        _patches     => Set::Tiny->new( @{ $attribs_ref->{patches} } ),
    };
    bless $self, $class;
    lock_keys( %{$self} );
    return $self;
}

sub _validate_attribs {
    my ( $class, $required_ref, $attribs_ref ) = @_;
    confess
      "must receive an array reference of the names of attributes to check"
      unless ( ( defined($required_ref) )
        and ( ref($required_ref) eq 'ARRAY' ) );
    confess "must receive an hash reference of the attributes to check"
      unless ( ( defined($attribs_ref) ) and ( ref($attribs_ref) eq 'HASH' ) );
    foreach my $attrib ( @{$required_ref} ) {
        confess "attribute $attrib is required"
          unless ( exists( $attribs_ref->{$attrib} ) );
        confess "attribute $attrib must be defined"
          unless ( defined( $attribs_ref->{$attrib} ) );
    }
}

sub add_patch {
    my ( $self, $patch ) = @_;
    if ( $self->get__patches->has($patch) ) {
        return 0;
    }
    else {
        $self->get__patches->insert($patch);
        return 1;
    }
}

# identifies which attributes should be treated as a list
sub get_lists {
    return (qw(patches));
}

# this is a public method, created to avoid exposing Set::Tiny instance
sub get_patches {
    my $self = shift;
    return $self->get__patches->members;
}

sub get_scalars {
    my $self    = shift;
    my %scalars = (
        name    => $self->get_name,
        version => $self->get_version
    );

    if ( defined( $self->get_home ) ) {
        $scalars{home} = $self->get_home;
    }

    if ( defined( $self->get_architecture ) ) {
        $scalars{architecture} = $self->get_architecture;
    }

    return \%scalars;
}

1;
