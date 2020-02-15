package Oracle::EnvReview::ProcFinder::Siebel;
use warnings;
use strict;
use parent qw(Oracle::EnvReview::ProcFinder);

# VERSION

=head1 NAME

Oracle::EnvReview::ProcFinder::Siebel - subclass of Oracle::EnvReview::ProcFinder for specifics of Siebel

=cut

=head1 SYNOPSIS

See L<Oracle::EnvReview::ProcFinder>.

=head1 DESCRIPTION

This subclass will have details to find version of Oracle Siebel by reading upgrade.txt and base.txt files.

=head1 METHODS

=head2 get_args

Overrided from parent class, this method will return arguments specific to the script execute to fetch
version from Oracle Siebel.

=cut

sub get_args {

    my $self = shift;

    return [
        '-f',                  $self->get_fifo(), '-i',
        $self->get_instance(), '-b',              $self->get_home()
    ];
}

=head2 get_oracle_home

This method returns the complete pathname expected to be used as value for the C<ORACLE_HOME>
environment variable.

This method is overrided from parent class.

=cut

sub get_oracle_home {

    my $self = shift;
    return File::Spec->catdir( '', $self->get_instance, 'siebel' );

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
