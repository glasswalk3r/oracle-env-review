package Oracle::EnvReview::FilesDef;
use warnings;
use strict;
use Exporter qw(import);
use File::Spec;
use Sys::Hostname 1.20;
use Carp;

# VERSION
our @EXPORT_OK = qw(temp_xml untaint_path);

=pod

=head1 NAME

Oracle::EnvReview::FilesDef - common files paths definition

=head1 SYNOPSIS

    use Oracle::EnvReview::FilesDef qw(temp_xml);
    my $xml_path = temp_xml($dir, $instance); # $dir and $instance are defined elsewhere

=head1 DESCRIPTION

This module is intended to be used by scripts that will execute a external program and capture it's output.

=head2 EXPORTS

The function C<temp_xml> is exportable.

=head3 temp_xml

Returns the complete path to the XML file that will be used for temporary storing of applications found.

Expects the following parameters in that order:

=over

=item string of the complete path where the file is expected to be available

=item string of the instance name that a script is running into

=back

=cut

sub temp_xml {

    my $dir      = shift;
    my $instance = shift;

    confess "invalid dir parameter" unless ( defined($dir) );
    confess "$dir is not accessible for reading/writing"
      unless ( ( -d $dir ) and ( -r $dir ) and ( -w $dir ) );
    confess "invalid instance parameter" unless ( defined($instance) );

    return File::Spec->catfile( $dir,
        ( $instance . '_' . hostname() . '.xml' ) );

}

=head3 untaint_path

Expects a path as parameters and returns this value untainted.

Most scripts of this distribution are forced to be executed in taint mode to avoid issues with C<PERL5LIB> variable.

Due that, parameters read from commmand line must be untained. This function validates those parameters with
values considered valid for a UNIX path.

If the path is invalid, an error is created with Carp C<confess> function.

=cut

sub untaint_path {
    my $path = shift;
    if ( $path =~ /^([\w\/\.\-\_]+)$/ ) {
        return $1;
    }
    else {
        confess "Insecure place received: '$path'";
    }
}

=head1 SEE ALSO

=over

=item *

L<Oracle::EnvReview>

=back

=head1 AUTHOR

Alceu Rodrigues de Freitas Junior, E<lt>glasswalk3r@yahoo.com.brE<gt>

=cut

1;
