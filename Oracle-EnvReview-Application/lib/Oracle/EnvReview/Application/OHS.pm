package Oracle::EnvReview::Application::OHS;
use warnings;
use strict;
use Hash::Util qw(lock_keys unlock_keys);
use parent 'Oracle::EnvReview::Application';

# VERSION
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(qw(apache_version alias));

sub new {
    my ( $class, $attribs_ref ) = @_;
    __PACKAGE__->_validate_attribs( [qw(apache_version alias)], $attribs_ref );
    my $self = $class->SUPER::new($attribs_ref);
    unlock_keys( %{$self} );
    $self->{apache_version} = $attribs_ref->{apache_version};
    $self->{alias}          = $attribs_ref->{alias};
    lock_keys( %{$self} );
    return $self;
}

sub get_scalars {
    my $self        = shift;
    my $scalars_ref = $self->SUPER::get_scalars;
    $scalars_ref->{apache_version} = $self->get_apache_version;
    $scalars_ref->{alias}          = $self->get_alias;
    return $scalars_ref;
}

1;
