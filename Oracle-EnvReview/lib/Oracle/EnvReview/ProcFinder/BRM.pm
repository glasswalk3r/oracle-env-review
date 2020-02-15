package Oracle::EnvReview::ProcFinder::BRM;
use warnings;
use strict;
use File::Spec;
use parent qw(Oracle::EnvReview::ProcFinder);

# VERSION

=head1 NAME

Oracle::EnvReview::ProcFinder::BRM - subclass of Oracle::EnvReview::ProcFinder for specifics of BRM

=head1 SYNOSIS

See parent class L<Oracle::EnvReview::ProcFinder>.

=head1 DESCRIPTION

This subclass overrrides some methos from parent class to be able to correctly search for BRM programs
and version.

=cut

=head1 METHODS

=head2 get_app_prog

This method is based on parent class C<get_app_prog> but instead of returning the found process from /proc, it
will replace the program found with the hardcoded value of 'pinrev', which is the application of BRM that will return
version details.

=cut

sub get_app_prog {

    my $self = shift;

    my ( $volume, $directories, $file ) =
      File::Spec->splitpath( $self->SUPER::get_app_prog );

    return File::Spec->catfile( $volume, $directories, 'pinrev' );

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
