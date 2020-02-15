package Oracle::EnvReview::ProcFinder::DBMS;
use warnings;
use strict;
use Hash::Util qw(lock_keys unlock_keys);
use Carp;
use Config;
use File::Spec;
use parent qw(Oracle::EnvReview::ProcFinder);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(qw(ebs_check));

# VERSION

=head1 NAME

Oracle::EnvReview::ProcFinder::DBMS - subclass of Oracle::EnvReview::ProcFinder for specifics of Oracle DBMS

=cut

=head1 SYNOPSIS

See L<Oracle::EnvReview::ProcFinder>.

=head1 DESCRIPTION

This subclass will have details to find version of Oracle DBMS and Oracle EBS as well.

It does that by assuming that each Oracle DB will have a "private" perl interpreter installed together with the database, and that this perl will
also have L<DBI> and L<DBD::Oracle> installed and configured. It won't work otherwise (see oracle_db.pl script for more detais).

This class also assumes that all instances names that ends with an "i" will have EBS installed in the
Oracle DBMS, and in those cases the version of EBS will be queried too.

=head1 ATTRIBUTES

Extends superclass by adding C<check_ebs> attribute. This attribute is boolean (as defined by Perl), optional (false by default) and read-only.

=head1 METHODS

=head2 new

Overloaded from parent to include C<ebs_check> attribute.

=cut

sub new {
    my ( $class, $attribs_ref ) = @_;
    my $self = $class->SUPER::new($attribs_ref);
    unlock_keys( %{$self} );

    if ( exists( $attribs_ref->{ebs_check} ) ) {
        confess "ebs_check attribute must be boolean"
          unless ( ( $attribs_ref->{ebs_check} == 0 )
            or ( $attribs_ref->{ebs_check} == 1 ) );
        $self->{ebs_check} = $attribs_ref->{ebs_check};
    }
    else {
        $self->{ebs_check} = 0;
    }

    lock_keys( %{$self} );
    return $self;
}

=head2 get_ebs_check

Getter for C<ebs_check> attribute.

=cut

=head2 get_args

Overrided from parent class, this method will return arguments specific to the script execute to fetch
version from Oracle DBMS and EBS.

If the instance name finishes with an "i", it is expected to have EBS running on the server, so EBS will
be checked as well.

=cut

sub get_args {
    my $self = shift;
    my @args = (
        File::Spec->catfile( $Config{bin}, 'oracle_db.pl' ),
        '-f', $self->get_fifo()
    );

    if ( $self->get_ebs_check ) {
        push( @args, '-e' );
    }

    return \@args;
}

=head2 get_oracle_home

This method overrides the one from parent class to implement a search of the ORACLE_HOME
based on the /etc/passwd instead of program path.

=cut

sub get_oracle_home {
    my ( $self, $process ) = @_;
    my @list = getpwuid( $process->uid );
    confess 'cannot find a user with ' . $process->uid . ' in /etc/passwd'
      unless (@list);
    return $list[7];
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
