package Oracle::EnvReview::Application::EBSO;
use warnings;
use strict;
use Set::Tiny;
use Carp;
use Hash::Util qw(lock_keys unlock_keys);
use base 'Oracle::EnvReview::Application';

# VERSION
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(qw(_languages));

sub new {
    my ( $class, $attribs_ref ) = @_;
    confess 'the array ref languages attribute is required'
      unless ( ( exists( $attribs_ref->{languages} ) )
        and ( defined( $attribs_ref->{languages} ) )
        and ( ref( $attribs_ref->{languages} ) eq 'ARRAY' ) );
    my $self = $class->SUPER::new($attribs_ref);
    unlock_keys( %{$self} );
    $self->{languages} = Set::Tiny->new( @{ $attribs_ref->{languages} } );
    lock_keys( %{$self} );
    return $self;
}

# an alias to list the EBSO registered bugs
sub get_bugs {
    my $self = shift;
    return $self->get_patches;
}

sub get_languages {
    my $self = shift;
    return $self->get__languages->members;
}

sub as_list {
    my $self = shift;
    my @list = $self->SUPER::as_list;
    push( @list, 'languages' );
    return @list;
}

# EBSO keeps the fixed bugs numbers instead of the patches applied
sub get_lists {
    return (qw(bugs));
}

1;
