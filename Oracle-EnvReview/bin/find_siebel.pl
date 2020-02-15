#!/ood_repository/environment_review/perl -T
use warnings;
use strict;
use Storable qw(nstore_fd);
use File::Spec;
use Getopt::Std;
use Carp;
use Oracle::EnvReview::Application::Siebel 0.001;
# VERSION

my %opts;
getopts( 'hvf:i:b:', \%opts );

if ( exists( $opts{h} ) ) {
    print <<BLOCK;
$0 - version $VERSION

This program will look for Siebel applications in pre-defined directory as
defined by instance name.

Parameters:

    -h: this help
    -v: prints the program name and version and exists
    -f <PATH>: complete path to a FIFO for communication
    -i <NAME>: instance name that the script should look for Siebel
    -b <PATH>: complete path to the home directory of Siebel application user

This program will print Perl serialized data with Storable to the FIFO.
Hope you will have a Perl program in the other side prepared to deal with it.

BLOCK
    exit;
}

if ( exists( $opts{v} ) ) {
    print "$0 - version $VERSION\n";
    exit;
}

foreach my $option (qw(f i b)) {
    confess "command option -$option is required"
      unless ( ( exists( $opts{$option} ) ) and ( defined( $opts{$option} ) ) );
}

my $home = $opts{b};
my %apps;

if ( -d $home ) {
    opendir( DIR, $home ) or confess "Cannot read directory $home: $!";
    my @items = readdir(DIR);
    close(DIR);
    my $regex       = qr/^8\.?\d+/;
    my $siebel_root = undef;

    foreach my $item (@items) {
        if (    ( $item =~ $regex )
            and ( -d File::Spec->catdir( $home, $item ) ) )
        {
            $siebel_root = $item;
            last;
        }
    }

    unless ( defined($siebel_root) ) {
        confess "Could not find Siebel installation in $home";
        return 0;
    }

    my %files = (
        'Siebel Server' => File::Spec->catfile(
            $home, $siebel_root, 'siebsrvr', 'upgrade', 'base.txt'
        ),
        'SWSE' =>
          File::Spec->catfile( $home, $siebel_root, 'sweapp', 'upgrade.txt' ),
        'Siebel Gateway' =>
          File::Spec->catfile( $home, $siebel_root, 'gtwysrvr', 'base.txt' )
    );

    foreach my $app ( keys(%files) ) {
        if ( -e $files{$app} ) {
            open( my $in, '<', $files{$app} )
              or confess 'Cannot read ' . $files{$app} . ": $!";
            while (<$in>) {
=pod
$ cat upgrade.txt
INSTALLED : 8.1.1.3 :  : Sun Dec 26 03:03:57 CST 2010
INSTALLED : 8.1.1.7 :  : Thu Jun 21 02:38:27 CDT 2012
INSTALLED : 8.1.1.7 : QF0795 : Sat Jul 05 10:33:57 CDT 2014
INSTALLED : 8.1.1.7 : QF07GH : Thu Jan 08 17:27:35 CST 2015
INSTALLED : 8.1.1.7 : QF07GH : Wed Jan 28 02:28:55 CST 2015
UNINSTALLED: 8.1.1.7 : QF07GH : Wed Jan 28 05:01:50 CST 2015
INSTALLED : 8.1.1.7 : QF07GH : Wed Jan 28 05:11:56 CST 2015
=cut
                chomp;

                # only the last setup version is desired
                if ( $app eq 'SWSE' ) {
                    my @parts = split( /\s\:\s/, $_ );
                    next unless ( $parts[0] eq 'INSTALLED' );
                    $apps{$app} = {} unless ( exists( $apps{$app} ) );

                    if ( $parts[2] =~ /^Q/ ) {

                        if ( exists( $apps{$app}->{hotfixes} ) ) {
                            push( @{ $apps{$app}->{hotfixes} }, $parts[2] );
                        }
                        else {
                            $apps{$app}->{hotfixes} = [ $parts[2] ];
                        }

                    }
                    else {
                        $apps{$app}->{version} = $parts[1];
                        $apps{$app}->{when}    = $parts[3];
                    }

                }
                else {
=pod
Same output for Siebel Server and Siebel Gateway
[sbtcfs22@vmsodcfst023 siebsrvr]$ cat base.txt
    8.1.1.7 SIA [21238] LANG_INDEPENDENT patch applied.
    HOTFIX QF07GH

=cut
                    $apps{$app} = {}
                      unless ( exists( $apps{$app} ) );
                    s/^\s+//g;
                    my @parts = split( /\s/, $_ );

                    if ( $parts[0] eq 'HOTFIX' ) {

                        if ( exists( $apps{$app}->{hotfixes} ) ) {
                            push( @{ $apps{$app}->{hotfixes} }, $parts[1] );
                        }
                        else {
                            $apps{$app}->{hotfixes} = [ $parts[1] ];
                        }

                    }
                    else {
                        $parts[2] =~ tr/[//d;
                        $parts[2] =~ tr/]//d;
                        $apps{$app}->{version} = $parts[0];
                        $apps{$app}->{type}    = $parts[1];
                        $apps{$app}->{release} = $parts[2];
                    }

                }

            }

            close($in);
        }

    }

}
else {
    confess "home directory is invalid or does not exists ($ENV{HOME})";
}

my $retries = 0;
my $limit   = 3;
my @apps;
foreach my $app( keys(%apps)) {
    $apps{$app}->{name} = $app;
    push( @apps, Oracle::EnvReview::Application::Siebel->new( $apps{$app} );
}

# taint mode cleanup
if ( $opts{f} =~ /^([-\@\w.\/]+)$/ ) {
    $opts{f} = $1;
}
else {
    confess "Insecure data in '$opts{f}'";
}

while ( $retries < $limit ) {

    if ( -p $opts{f} ) {
        open( my $fifo, '>', $opts{f} )
          or confess "cannot write to pipe $opts{f}: $!";
        binmode($fifo) or confess "Cannot set fifo to binary mode: $!";
        nstore_fd \@apps, $fifo;
        close($fifo);
        last;
    }
    else {
        $retries++;
        sleep 10;
    }
}

warn "could not find the fifo $opts{f} to print output after $limit retries"
  if ( $retries == $limit );
