package Oracle::EnvReview::Application::BRM;
use warnings;
use strict;
use Set::Tiny;
use Hash::Util qw(lock_keys unlock_keys);
use Carp;
use parent 'Oracle::EnvReview::Application';

# VERSION
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(qw(_components build_time installed_time));

sub new {
    my ( $class, $attribs_ref ) = @_;
    confess 'the array ref components attribute is required'
      unless ( ( exists( $attribs_ref->{components} ) )
        and ( defined( $attribs_ref->{components} ) )
        and ( ref( $attribs_ref->{components} ) eq 'ARRAY' ) );
    my $self = $class->SUPER::new($attribs_ref);
    unlock_keys( %{$self} );
    $self->{components}     = Set::Tiny->new( @{ $attribs_ref->{components} } );
    $self->{build_time}     = $attribs_ref->{build_time} || undef;
    $self->{installed_time} = $attribs_ref->{installed_time} || undef;
    lock_keys( %{$self} );
    return $self;
}

sub get_components {
    my $self = shift;
    return $self->get__components->members;
}

sub as_list {
    my $self = shift;
    my @list = $self->SUPER::as_list;
    push( @list, 'components' );
    return @list;
}

1;
