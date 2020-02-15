#!/ood_repository/environment_review/perl -t
use warnings;
use strict;
use Storable;
use Data::Dumper;
use Getopt::Std;
use Oracle::EnvReview::FilesDef qw(untaint_path);

# VERSION
my %opts;
getopts( 'f:', \%opts );
unless (( exists( $opts{f} ) )
    and ( defined( $opts{f} ) )
    and ( -p $opts{f} ) )
{
    die 'must receive the complete path to a fifo as parameter for -f option';
}
print Dumper( retrieve( untaint_path( $opts{f} ) ) );
