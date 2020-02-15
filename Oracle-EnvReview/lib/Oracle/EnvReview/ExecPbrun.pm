package Oracle::EnvReview::ExecPbrun;
use warnings;
use strict;
use Expect 1.32;
use Exporter 'import';
use Carp;
use Config;
use Oracle::EnvReview::FilesDef qw(untaint_path);

# VERSION
our @EXPORT = qw(exec_pbrun);

=pod

=head1 NAME

Oracle::EnvReview::ExecPbrun - Perl module to execute a program through pbrun

=head1 SYNOPSIS

    use Oracle::EnvReview::ExecPbrun;

    my $exit = exec_pbrun(
        $user,   $instance, $program,
        $sr_num, \@args
    );

=head1 DESCRIPTION

This module executes a program through pbrun by using L<Expect>.

=head1 EXPORTS

Only exec_pbrun function is automatically exported.

=head2 exec_pbrun.

This functions executes a program through pbrun by using L<Expect> module.

This is necessary because on production instances the pbrun will expect a SR number which can be givin only through a
tty, which is provided by L<Expect>.

The function will not capture output but will try to match a error message, in this case return 1. In all other cases
it will return 0.

Expects as parameters the following values:

=over

=item a string with the user to use with pbrun

=item instance name

=item the string of the complete pathname to the program to execute

=item the string of a Service Request number to be used with pbrun on production instances

=item the command line options to the program as an array reference

=back

=cut

sub exec_pbrun {
    my ( $user, $instance, $cmd, $sr_num, $opts_ref ) = @_;
    confess "user parameter is required"         unless ( defined($user) );
    confess "instance parameter is required"     unless ( defined($instance) );
    confess "cmd parameter is required"          unless ( defined($cmd) );
    confess "Service Request number is required" unless ( defined($sr_num) );
    confess "options parameter is required and must be an array reference"
      unless ( ( defined($opts_ref) ) and ( ref($opts_ref) eq 'ARRAY' ) );
    my @args = ( 'pbrun', 'ohsdba', '-u', $user, $cmd, @{$opts_ref} );
    print 'Will execute \'', join( ' ', @args ), "'\n";
    my $exit;
    local $ENV{PATH} =
      join( ':', '/usr/bin', '/usr/local/bin', untaint_path( $Config{bin} ) );

    if ( $instance =~ /^p/i ) {
        print "Running in production, will call pbrun with $sr_num\n";
        my $exp = Expect->new;
        $exp->raw_pty(1);
        $exp->spawn( @args, ';echo "__EOF__"' );
        $exp->expect(
            300,
            [
                qr/request\snumber/,
                sub {
                    my $self = shift;
                    $self->send("$sr_num\n");
                    exp_continue;
                }
            ],
            [
                qr/error/i,
                sub {
                    my $self = shift;
                    print 'ERROR: ', $self->match, "\n";
                    exp_continue;
                }
            ],
            [ qr/__EOF__/, sub { print shift->pid(), " finished\n"; } ]
        );
        $exp->soft_close();
        $exit = $exp->exitstatus();
    }
    else {
        system(@args);
        $exit = $? >> 8;
    }

    return $exit;
}

=head1 SEE ALSO

L<Expect>.

=head1 AUTHOR

Alceu Rodrigues de Freitas Junior, E<lt>glasswalk3r@yahoo.com.brE<gt>

=cut
