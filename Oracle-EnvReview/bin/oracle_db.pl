# this script doesn't have a shebang, and that's expected since it should rely on perl available to the user executing it (unknown path)
use warnings;
use strict;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use Storable qw(nstore_fd);
use Getopt::Std;
use Carp;

# TODO: maybe a symbolic link will work instead using a hardcoded path?
use lib '/ood_repository/alceu/perl5/perls/perl-5.24.0/lib/site_perl/5.24.0';
use Oracle::EnvReview::Application 0.002;
use Oracle::EnvReview::Application::EBSO 0.002;
use Oracle::EnvReview::Application::Exception 0.002;

# VERSION

my %opts;
getopts( 'hvf:e', \%opts );

if ( exists( $opts{h} ) ) {
    print <<BLOCK;
$0 - version $VERSION

This program will connect to a Oracle database as SYSDBA and execute SQL queries
to find out Oracle and EBS version details, patches included.

Parameters:

    -h: this help
    -v: prints the program name and version and exists
    -e: optional. Tells the script to search for EBSO information as well in the Oracle DB.
    -f <PATH>: complete path to a FIFO for communication

This program will print Perl serialized data with Storable to the FIFO.
Hope you will have a Perl program in the other side prepared to deal with it.

It is required that the user that will run this script have the proper permissions to connect to the Oracle
database without providing user and password. All required environment variables must be set for that.

This script expects that all environment variables required to connect to the database are in place.

BLOCK

    exit;

}

if ( exists( $opts{v} ) ) {
    print "$0 - version $VERSION\n";
    exit;
}

confess "command option -f is required"
  unless ( ( exists( $opts{f} ) ) and ( defined( $opts{f} ) ) );

my $dbh;
my @apps;

if ( exists( $ENV{ORACLE_SID} ) ) {

    # untaint
    $ENV{ORACLE_SID} =~ /^(\w+)$/;
    my $SID = $1;
    confess 'Invalid ORACLE_SID' unless ( defined($SID) );
    print "Connecting to Oracle DB of $SID... ";

# see http://search.cpan.org/~pythian/DBD-Oracle-1.30/Oracle.pm#ora_session_mode for details on the parameters below
    my $dbh;
    eval {
        $dbh = DBI->connect( 'dbi:Oracle:', undef, undef,
            { RaiseError => 1, ora_session_mode => ORA_SYSDBA } );
        push( @apps, get_oracle($dbh) );
        if ( ( exists( $opts{e} ) ) and ( $opts{e} ) ) {
            push( @apps, get_ebs($dbh) );
        }
    };

    if ($@) {
        print
"failed due unrecoverable error. Exception will be included as output.\n";
        push(
            @apps,
            Oracle::EnvReview::Application::Exception->new(
                { error_msg => "$0 failed: $@", name => 'Oracle Database' }
            )
        );
    }

    my $retries = 0;
    my $limit   = 6;

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
              or die "cannot write to pipe $opts{f}: $!";
            binmode($fifo) or die "Cannot set fifo to binary mode: $!";
            nstore_fd \@apps, $fifo;
            close($fifo);
            last;
        }
        else {
            $retries++;
            sleep 10;
        }
    }

    warn
      "could not find the fifo $opts{f} to print output after $limit retries"
      if ( $retries == $limit );
}
else {
    confess
      "the environment variable ORACLE_SID is not defined, cannot continue";
}

sub get_oracle {
    my $dbh = shift;
    print "Querying Oracle DB version\n";
    my $sth = $dbh->prepare('select * from v$version');
    $sth->execute();
    my $row = $sth->fetchrow_arrayref();

  # Oracle Database 11g Enterprise Edition Release 11.2.0.1.0 - 64bit Production
    my @parts = split( /\s/, $row->[0] );
    my $name  = join( ' ', @parts[ 0 .. 4 ] );

    # :TODO:07/03/2015 06:09:36 PM:: check Oracle 11G patches as well
    return Oracle::EnvReview::Application->new(
        {
            name         => $name,
            version      => $parts[6],
            architecture => $parts[8],
            patches      => []
        }
    );
}

sub get_ebs {
    my $dbh = shift;
    print "Querying EBSO details\n";
    my $sth =
      $dbh->prepare(q{select RELEASE_NAME from apps.fnd_product_groups});
    $sth->execute();
    my $row     = $sth->fetchrow_arrayref();
    my $version = $row->[0];
    $sth = $dbh->prepare(
q{select language_code || ':' || installed_flag as language from apps.fnd_languages where installed_flag in ('I','B')}
    );
    $sth->execute();
    $row = $sth->fetchrow_arrayref();
    my @languages = @{$row};

# listing only the last year bugs registered, no correlation with patches sets or CPUs
    $sth = $dbh->prepare(
q{SELECT DISTINCT bug_number FROM apps.ad_bugs WHERE creation_date >= to_date( (SELECT to_char(MAX(creation_date),'YYYY-MM-DD') FROM apps.ad_bugs), 'YYYY-MM-DD')}
    );
    $sth->execute();
    my @patches;
    while ( $row = $sth->fetchrow_arrayref() ) {
        push( @patches, $row->[0] );
    }
    return Oracle::EnvReview::Application::EBSO->new(
        {
            name      => 'Oracle E-Business Suite',
            version   => $version,
            languages => \@languages,
            patches   => \@patches
        }
    );
}

END {
    $dbh->disconnect() if ( defined($dbh) );
}
