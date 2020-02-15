package Oracle::EnvReview::Application::Exception;
use warnings;
use strict;
use Carp;
use Hash::Util qw(lock_keys unlock_keys);
use base 'Oracle::EnvReview::Application';

# VERSION
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors('error_msg');

# an application whose details could not be checked due some fatal error
sub new {
    my ( $class, $attribs_ref ) = @_;
    confess 'error_msg attribute is required'
      unless ( ( exists( $attribs_ref->{error_msg} ) )
        and ( defined( $attribs_ref->{error_msg} ) ) );
    $attribs_ref->{name}         = 'unrecoverable error';
    $attribs_ref->{version}      = 'unknown';
    $attribs_ref->{architecture} = 'unknown';
    $attribs_ref->{patches}      = [];
    my $self = $class->SUPER::new($attribs_ref);
    unlock_keys( %{$self} );
    $self->{error_msg} = $attribs_ref->{error_msg};
    lock_keys( %{$self} );
    return $self;
}

1;
