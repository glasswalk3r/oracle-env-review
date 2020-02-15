package Oracle::EnvReview::Hints::Server;

use warnings;
use strict;
use Set::Tiny 0.04;
use Carp;
use Hash::Util 'lock_keys';
use base 'Class::Accessor';

# VERSION

__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(qw(inventories skip_users));

sub new {
    my ( $class, $attribs_ref ) = @_;
    my $self = {};

    if ( exists( $attribs_ref->{inventories} ) ) {
        confess 'inventories must be an array reference'
          unless ( ref( $attribs_ref->{inventories} ) eq 'ARRAY' );
        $self->{inventories} = $attribs_ref->{inventories};
    }
    else {
        $self->{inventories} = [];
    }

    if ( exists( $attribs_ref->{skip_users} ) ) {
        confess 'skip_users must be an array reference'
          unless ( ref( $attribs_ref->{skip_users} ) eq 'ARRAY' );
        $self->{skip_users} =
          Set::Tiny->new( ( @{ $attribs_ref->{skip_users} } ) );
    }
    else {
        $self->{skip_users} = Set::Tiny->new();
    }

    bless $self, $class;
    lock_keys( %{$self} );
    return $self;
}

sub skip_user {
    my ( $self, $user ) = @_;
    return $self->{skip_users}->has($user);
}

1;
