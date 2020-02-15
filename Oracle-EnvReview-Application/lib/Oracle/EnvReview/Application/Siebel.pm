package Oracle::EnvReview::Application::Siebel;
use warnings;
use strict;
use Set::Tiny;
use Hash::Util qw(lock_keys unlock_keys);
use parent 'Oracle::EnvReview::Application';

# VERSION
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(qw(when type release));

sub new {
    my ( $class, $attribs_ref ) = @_;
    $attribs_ref->{patches} = $attribs_ref->{hotfixes};
    delete( $attribs_ref->{hotfixes} );
    my $self = $class->SUPER::new($attribs_ref);
    unlock_keys( %{$self} );
    $self->{when} = $attribs_ref->{when} if ( exists( $attribs_ref->{when} ) );
    $self->{type} = $attribs_ref->{type} if ( exists( $attribs_ref->{type} ) );
    $self->{release} = $attribs_ref->{release}
      if ( exists( $attribs_ref->{release} ) );
    lock_keys( %{$self} );
    return $self;
}

# an alias to list the Siebel hotfixes installed
sub get_hotfixes {
    my $self = shift;
    return $self->get_patches;
}

1;
