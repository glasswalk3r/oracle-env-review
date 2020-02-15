package Oracle::EnvReview::ProcFinder::OHS;
use warnings;
use strict;
use File::Spec;
use parent qw(Oracle::EnvReview::ProcFinder);

# VERSION

=head1 NAME

	Oracle::EnvReview::ProcFinder::OHS - subclass of Oracle::EnvReview::ProcFinder for specifics of OHS

=cut

=head1 SYNOPSIS

See L<Oracle::EnvReview::ProcFinder>.

=head1 DESCRIPTION

This subclass will have details to find version of OHS.

=head1 METHODS

=head2 get_args

Overrided from parent class, this method will return arguments specific to the script execute to fetch
version from OHS.

=cut

sub get_args {

    my $self = shift;
    return [
        '-p',                  $self->get_pid(), '-c',
        $self->get_app_prog(), '-f',             $self->get_fifo()
    ];

}

=head1 SEE ALSO

=over

=item *

L<Oracle::EnvReview::ProcFinder>

=back

=head1 AUTHOR

Alceu Rodrigues de Freitas Junior, E<lt>glasswalk3r@yahoo.com.brE<gt>

=cut

1;
