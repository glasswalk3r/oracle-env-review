package Oracle::EnvReview::ProcFinder::Weblogic;
use warnings;
use strict;
use parent qw(Oracle::EnvReview::ProcFinder);

# VERSION

sub new {
    my ( $class, $attribs_ref ) = @_;
    $attribs_ref->{is_storable} = 0;
    return $class->SUPER::new($attribs_ref);
}

sub get_args {
    my $self = shift;
    return [ '-f', $self->get_fifo() ];
}

1;
