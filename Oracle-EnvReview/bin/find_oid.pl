#!/ood_repository/environment_review/perl -T
use warnings;
use strict;
use Oracle::EnvReview::VersionFinder qw(check_version check_args);
use File::Spec;
use Oracle::EnvReview::Application 0.001;

# VERSION

my ( $cmd, $home, $fifo ) = check_args( $VERSION, 'oidldapd', 'OID' );

$ENV{ORACLE_HOME} = $home;

check_version(
    $cmd,
    ['-v'],
    $fifo,
    sub {
        my $output_ref = shift;
        my @lines      = split( /\n/, $$output_ref );
        my $regex      = qr/^oidldapd\:\sRelease/;
        my %data;

        foreach my $line (@lines) {

          #oidldapd: Release 10.1.4.0.1 - Production on thu nov  6 10:36:59 2014
            if ( $line =~ $regex ) {
                my $version = ( split( ' ', $line ) )[2];

                $data{} = { version => $version };
                return [
                    Oracle::EnvReview::Application->new(
                        {
                            name    => 'Oracle Internet Directory',
                            version => $version,
                            patches => []
                        }
                    )
                ];
            }

        }
    }
);
