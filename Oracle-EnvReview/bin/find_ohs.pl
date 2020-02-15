#!/ood_repository/environment_review/perl -T
use warnings;
use strict;
use Oracle::EnvReview::VersionFinder qw(check_version);
use Oracle::EnvReview::FilesDef qw(untaint_path);
use Getopt::Std;
use Proc::Info::Environment 0.01;
use Oracle::EnvReview::Application::OHS 0.001;
use Carp;

# VERSION

my %opts;
getopts( 'hvc:p:f:', \%opts );

if ( exists( $opts{h} ) ) {

    print <<BLOCK;
$0 - version $VERSION

This program will try to execute and capture the output of httpd program to
check the version of OHS from it.
To do that, a running process of httpd must be available because this script
will copy environment variables from the respective /proc/<PID>/environ file.

Options:

    -h: this help
    -v: prints the program name and version and exists
    -c <PATH>: complete path to the httpd program
    -p <PID>: the PID of the program given by -c parameter.
    -f <PATH>: complete path to a FIFO for communication

This program will print Perl serialized data with Storable to the FIFO.
Hope you will have a Perl program in the other side prepared to deal with it.

BLOCK

    exit;

}

if ( exists( $opts{v} ) ) {
    print "$0 - version $VERSION\n";
    exit;
}

foreach my $arg (qw(c p f)) {
    confess "command option -$arg is required"
      unless ( ( exists( $opts{$arg} ) ) and ( defined( $opts{$arg} ) ) );
}

if ( $opts{p} =~ /^(\d+)$/ ) {
    $opts{p} = $1;
}
else {
    confess "pid parameter must be a number";
}

my $proc_info = Proc::Info::Environment->new();
my $env       = $proc_info->env( $opts{p} );

confess "could not recover environment variables from $opts{p}"
  unless ( ( defined($env) ) and ( ref($env) eq 'HASH' ) );

foreach my $var ( keys( %{$env} ) ) {
    $ENV{$var} = $env->{$var};
}

check_version(
    untaint_path( $opts{c} ),
    ['-v'],
    untaint_path( $opts{f} ),
    sub {
        my $output_ref = shift;
        my @rows       = split( /\n/, $$output_ref );
        my %data;

=pod
Output samples:

Server version: Oracle-HTTP-Server/2.2.21 (Unix)
Server built:   Nov  9 2011 22:28:35
Server label:   APACHE_11.1.1.6.0_LINUX_111109.2001

Server version: Oracle-Application-Server-10g/10.1.3.1.0 Oracle-HTTP-Server
Server built:   Sep 18 2006 16:09:37

Server version: Oracle-HTTP-Server/2.2.22 (Unix)
Server built:   Aug 20 2015 15:10:59
Server label:   APACHE_11.1.1.7.0_LINUX.X64_RELEASE

=cut

        foreach my $row (@rows) {

            if ( $row =~ /^Server\sversion/ ) {
                $row =~ s/Server\sversion\:\s//;
                my ( $name,    $tmp )   = split( '/',  $row );
                my ( $version, $alias ) = split( /\s/, $tmp );
                $data{name}    = $name;
                $data{version} = $version;
                $alias =~ tr/(//d;
                $alias =~ tr/)//d;
                $data{alias} = $alias;

                # to have something if OHS is an older version
                $data{apache_version} = $version;
                next;
            }

            if ( $row =~ /^Server\sbuilt/ ) {
                $row =~ s/Server\sbuilt\:\s+//;
                $data{build} = $row;
                next;
            }

            if ( $row =~ /^Server\slabel/ ) {
                $row =~ s/Server\slabel\:\s+//;
                my $name    = ( keys(%data) )[0];
                my $version = ( split( '_', $row ) )[1];
                $data{version} = $version;
            }

        }

        return [
            Oracle::EnvReview::Application::OHS->new(
                {
                    name           => $data{name},
                    version        => $data{version},
                    apache_version => $data{apache_version},
                    alias          => $data{alias},
                    patches        => []
                }
            )
        ];
    }
);
