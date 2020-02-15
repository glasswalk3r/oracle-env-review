package Oracle::EnvReview::VersionFinder;
use warnings;
use strict;
use Exporter qw(import);
use Getopt::Std;
use Storable qw(nstore_fd);
use Carp;
use Capture::Tiny 0.27 qw(:all);
use Oracle::EnvReview::Application::Exception 0.001;

# VERSION
our @EXPORT_OK = qw(check_version check_args);

=pod

=head1 NAME

Oracle::EnvReview::VersionFinder - exports versions for command lines scripts to execute external programs

=head1 SYNOPSIS

    use Oracle::EnvReview::VersionFinder;

    my $VERSION = 1;

    my ( $cmd, $home ) = check_args( $VERSION, 'program_name', 'AppName' );

    check_version(
        $cmd, undef,
        File::Spec->catfile( 'path_to', 'fifo_filename' ),
        sub {

            my $output_ref = shift;
            # do something with $output_ref as scalar reference
        }
    );

=head1 DESCRIPTION

This module is intended to be used by scripts that will execute a external program and capture it's output.

Also, it has a general command line processing to enable online documentation and version checking.

=head2 EXPORTS

The functions C<check_args> and C<check_version> are exported by default.

=head3 check_version

Expects the following parameters in that order:

=over

=item string of the external program path

=item arguments to the external program as an array reference

=item string of complete path to the fifo

=item code reference to to be used to process program output

=back

This function will execute a given program and capture it's output (both STDOUT and STDERR).
The output will then be passed as an argument to the code reference given, which should be
able to parse the content of it, returning a hash reference.

By convention, the hash reference keys are the application name and each key value will be a hash reference
itself. The keys/values stored in this inner hash reference doesn't matter.

This information will serialized and sent by a fifo. It is expected to have a
program connected to the other side of the fifo to read such information. If the fifo is not
present at the time of execution, the version will sleep and retry 3 times to find the fifo, calling
C<warn> when none is found and exiting.

=cut

sub check_version {
    my ( $cmd, $args_ref, $fifo_path, $code_ref ) = @_;
    confess "command parameter must be defined" unless ( defined($cmd) );
    confess "fifo path parameter must be defined"
      unless ( defined($fifo_path) );
    confess "code parameter must be defined and be a code reference"
      unless ( ( defined($code_ref) ) and ( ref($code_ref) eq 'CODE' ) );

    if ( defined($args_ref) ) {
        confess "additional arguments must be an array reference"
          unless ( ref($args_ref) eq 'ARRAY' );
    }

    my $retries = 0;
    my $limit   = 3;

    while ( $retries < $limit ) {

        if ( -p $fifo_path ) {
            open( my $fifo, '>', $fifo_path )
              or confess "cannot write to pipe $fifo_path: $!";
            binmode($fifo) or confess "failed to set fifo to binary mode: $!";
            my ( $stdout, $stderr, $exit );

            # taint mode clean up
            delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};

            if ( $cmd =~ /^([\/\w\.\-]+)$/ ) {
                $cmd = $1;
            }
            else {
                confess "Insecure command '$cmd' received, aborting";
            }

            my @cmd = ($cmd);
            push( @cmd, @{$args_ref} ) if ( defined($args_ref) );

            ( $stdout, $stderr, $exit ) = capture {
                system(@cmd);
            };

            # array reference
            my $data_ref;

            if ( $exit == 0 ) {

# because some apps can be dumb enough to use STDERR instead of STDOUT to print version
                if ( ( defined($stderr) ) and ( $stderr =~ /\w+/ ) ) {
                    $data_ref = $code_ref->( \$stderr );
                }
                else {
                    $data_ref = $code_ref->( \$stdout );
                }

                confess 'data returned from program is invalid'
                  unless ( ( defined($data_ref) )
                    and ( ref($data_ref) eq 'ARRAY' ) );
                nstore_fd $data_ref, $fifo;
            }
            else {
                warn $stderr;
                my $error = [
                    Oracle::EnvReview::Application::Exception->new(
                        { error_msg => $stderr }
                    )
                ];
                nstore_fd $error, $fifo;
            }

            close($fifo);
            last;
        }
        else {
            $retries++;
            sleep 10;
        }

    }    # end of while block

    warn
      "could not find the fifo $fifo_path to print output after $limit retries"
      if ( $retries == $limit );

}

=head2 check_args

This function provides basic command line processing for scripts.

The scripts are expected to the have always the same command line options: -h (for help),
-v (for version), -o (the value of ORACLE_HOME environment variable), -f (FIFO) and -c (for complete path to the program to execute).

This function will provide basic help information when request as well version checking.

Expect as parameters:

=over

=item version of the script

=item complete path to the program to execute

=item name of the Oracle application that will be checked by the script

=item complete path to the FIFO for interprocess communication

=back

Return the values of -c, -f and -o as a list.

=cut

sub check_args {
    my ( $version, $program_name, $app_name ) = @_;
    confess "must receive version number as parameter"
      unless ( defined($version) );
    confess "must receive program name as parameter"
      unless ( defined($program_name) );
    confess "must receive app name as parameter" unless ( defined($app_name) );
    my %opts;
    getopts( 'hvc:o:f:', \%opts );

    if ( exists( $opts{h} ) ) {
        print <<BLOCK;
$0 - version $version

This program will try to execute and capture the output of $program_name program to check the version of $app_name from it.

Options:

    -h: this help
    -v: prints the program name and version and exists
    -c <PATH>: complete path to the $program_name program
    -o <ORACLE_HOME>: the value to set ORACLE_HOME environment variable (if necessary) to execute $program_name execution
    -f <PATH>: path to the FIFO for interprocess communication

BLOCK
        exit;
    }

    if ( exists( $opts{v} ) ) {
        print "$0 - version $version\n";
        exit;
    }

    foreach my $arg (qw(c o f)) {
        confess "command option -$arg is required"
          unless ( ( exists( $opts{$arg} ) ) and ( defined( $opts{$arg} ) ) );
    }

    return ( $opts{c}, $opts{o}, $opts{f} );
}

=head1 SEE ALSO

=over

=item *

L<Getopt::Std>

=item *

L<Capture::Tiny>

=item *

L<Storable>

=back

=head1 AUTHOR

Alceu Rodrigues de Freitas Junior, E<lt>glasswalk3r@yahoo.com.brE<gt>

=cut

1;
