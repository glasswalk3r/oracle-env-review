use warnings;
use strict;
use Oracle::EnvReview::Remote::Putty;
use Term::ReadKey 2.33;
use DateTime 1.27;
use Config;
use threads;
use File::Spec;
use Cwd;
use XML::LibXML 2.0124;
use Set::Tiny 0.04;
use Data::Dumper;
use Getopt::Std;
use Try::Tiny 0.24;
use Carp;
use Scalar::Util qw(blessed);
use YAML::XS 0.62 qw(LoadFile);

# VERSION
$Config{useithreads} or die('Recompile Perl with threads to run this program.');
my %opts;
$SIG{INT} = sub { warn Dumper( threads->list() ); exit 1; };

getopts( 'c:o', \%opts );
my $log = 'rcview.log';
open( my $out, '>>', $log ) or die "could not create/update $log: $!";
my $main_start : shared = DateTime->now;
tee( $out, 'Started at ' . $main_start->iso8601() . "\n" );
my $config_file;

if ( ( exists( $opts{c} ) ) and ( defined( $opts{c} ) ) and ( -e $opts{c} ) ) {
    $config_file = $opts{c};
}
else {
    $config_file = 'config.yml';
}

tee( $out, "Reading configuration from $config_file\n" );
my ( $user, $customer, $threads_limit, $entries_ref ) = read_cfg($config_file);
print "Welcome to Remote Customer View - version $VERSION\n";
print "Enter password for $user: ";
ReadMode('noecho');
my $password = <STDIN>;
chomp($password);
ReadMode('restore');
print "\n",
  'Please enter with SR number for production servers (defaults to "1-1"): ';
my $sr_num = <STDIN>;
chomp($sr_num);
$sr_num = '1-1' unless ( ( defined($sr_num) ) and ( $sr_num ne '' ) );
print 'Do you want to clean product cache? (y/n): ';
my $response = <STDIN>;
chomp($response);
my $clean_cache     = ( $response eq 'y' ) ? 1 : 0;
my $total_time      = 0;
my $total_conn      = 0;
my $total_errors    = 0;
my $threads_counter = 0;
my $max_retries     = 10;
my $retry_sleep     = 30;
my $os_only         = ( exists( $opts{o} ) ) ? 1 : 0;
my $wait_counter    = 0;

foreach my $dir (qw(tmp logs)) {

    unless ( -d $dir ) {
        mkdir $dir or die "Cannot create $dir: $!";
    }

}

my @jobs;

# sort servers by instance
# add them by instance so they probably will not mix the same server for different instances
foreach my $instance ( keys( %{$entries_ref} ) ) {
    my @curr_servers = sort( @{ $entries_ref->{$instance} } );
    foreach my $server (@curr_servers) {
        push( @jobs, { server => $server, instance => $instance } );
    }
}

# ban the server if the number of attempts reached max
my $banned = Set::Tiny->new();
my %server_attempts;
my $running = Set::Tiny->new();

JOBS: while ( scalar(@jobs) or $running->size ) {

    $| = 1;
    my $job_ref;
    if ( $running->size < $threads_limit ) {
        $job_ref = shift(@jobs);
    }

    if ( defined($job_ref) ) {

        if ( check_cache($job_ref) ) {
            tee( $out,
                    'server '
                  . $job_ref->{server}
                  . ' of instance '
                  . $job_ref->{instance}
                  . " skipped due cache file found\n" );
            next JOBS;
        }

        if ( $banned->has( $job_ref->{server} ) ) {
            tee( $out,
                    'server '
                  . $job_ref->{server}
                  . " was banned after $max_retries retries" );
        }
        else {
       # must not allow two instances running on the same server to avoid errors
            if ( $running->has( $job_ref->{server} ) ) {

                if ( exists( $server_attempts{ $job_ref->{server} } ) ) {
                    $server_attempts{ $job_ref->{server} } += 1;

                    if ( $server_attempts{ $job_ref->{server} } > $max_retries )
                    {
                        $banned->insert( $job_ref->{server} );
                        delete( $server_attempts{ $job_ref->{server} } );
                    }

                }
                else {
                    # put back the job to the end of line
                    push( @jobs, $job_ref );
                    $server_attempts{ $job_ref->{server} } = 1;
                }

            }
            else {
                tee( $out,
                    'Creating thread for ' . $job_ref->{server} . '... ' );
                my $thread = threads->create(
                    { context => 'list' },
                    \&ssh_2_server,
                    {
                        server      => $job_ref->{server},
                        instance    => $job_ref->{instance},
                        clean_cache => $clean_cache,
                        sr_num      => $sr_num,
                        os_only     => $os_only
                    }
                );
                tee( $out, 'created thread ' . $thread->tid() . "\n" );
                $running->insert( $job_ref->{server} );
            }

        }
    }

    if ( $running->size == $threads_limit ) {
        tee( $out, "reached threads limit, sleeping\n" );
        sleep 10;
        join_threads( $running, $out );
    }
    elsif ( $running->size and ( scalar(@jobs) == 0 ) ) {
        sleep 10;
        tee( $out, "jobs are done, threads still running\n" );
        $wait_counter++;
        if ( $wait_counter > $max_retries ) {
            tee( $out,
"wait for threads when jobs are done exceeded maximum retries of $max_retries.\n"
            );
            last JOBS;
        }
        join_threads( $running, $out );
    }

}

$retry_sleep = 60;
tee( $out,
"Will try again to wait for the rest of threads with $retry_sleep seconds sleep time\n"
);
my $join_retries = 0;

while ( threads->list() ) {
    join_threads( $running, $out );
    $join_retries++;
    sleep $retry_sleep;

    if ( $join_retries == $max_retries ) {
        tee( $out,
            "Will ignore the following threads after exhausted the retries\n" );

        foreach my $ignored ( threads->list(threads::running) ) {
            tee( $out, $ignored->tid() . "\n" );
            $total_errors++;
        }

        tee( $out,
                'Known connections to servers: '
              . Dumper( $running->members )
              . "\n" );
        last;
    }

}

# avoiding making threads to load those modules
require XML::Writer;
require IO::File;

my $output = IO::File->new('>results.xml');
my $xml    = XML::Writer->new( OUTPUT => $output );
$xml->xmlDecl("UTF-8");
$xml->startTag('customer');
$xml->dataElement( 'name', $customer );
$xml->startTag('instances');

my $local_dir = File::Spec->catdir( getcwd(), 'tmp' );
opendir( my $dh, $local_dir ) or confess "Cannot read $local_dir: $!";
my @list = sort( readdir($dh) );
close($dh);

my $previous = 'none';
my $regex    = qr/\.xml$/;

foreach my $server_file (@list) {

    next unless $server_file =~ $regex;
    my $instance = ( split( '_', $server_file ) )[0];

    if ( $previous ne $instance ) {

        unless ( $previous eq 'none' ) {
            $xml->endTag('servers');
            $xml->endTag('instance');
        }

        $xml->startTag('instance');
        $xml->dataElement( 'name', $instance );
        $xml->startTag('servers');
        $previous = $instance;
    }

    my $path = File::Spec->catfile( $local_dir, $server_file );

    # validate XML before trying to include it
    my $is_xml_ok = 0;

    try {
        my $parser = XML::LibXML->new();
        my $xml    = $parser->load_xml( location => $path );
        $is_xml_ok = 1;
    }
    catch {
        tee( $out, "An error ocurrered: $_\n" );
    };

    if ($is_xml_ok) {
        open( my $in, '<', $path ) or confess "Cannot read $path: $!";
        while (<$in>) { print $output $_ }
        close($in);

        #unlink( $path ) or warn "remove of $path failed: $!";
    }
}

$xml->endTag('servers');
$xml->endTag('instance');
$xml->endTag('instances');
$xml->endTag('customer');
$xml->end;

my $main_end = DateTime->now;
my $main_dur = $main_end->subtract_datetime($main_start);
tee( $out, 'Finished checking all servers at ' . $main_end->iso8601() . "\n" );
tee( $out,
    "Tried $total_conn SSH connections with a total of $total_errors errors\n"
);
my ( $hours, $min, $sec ) =
  $main_dur->in_units( 'hours', 'minutes', 'seconds' );
my $main_total = ( $hours * 3600 ) + ( $min * 60 ) + $sec;

tee( $out,
        'Main thread spent '
      . $main_total
      . " seconds while SSH threads used $total_time seconds\n" );

tee( $out,
    "Checking other instances/servers that might have not finished yet\n" );
close($out) or confess "Could not close $log: $!";

sub tee {
    my ( $fh, $msg ) = @_;
    print $fh $msg;
    print $msg;
}

sub ssh_2_server {
    my $opts_ref = shift;
    my $log =
      File::Spec->catfile( getcwd(), 'logs', ( $opts_ref->{server} . '.log' ) );
    my $is_log_ok = open( my $out, '>>', $log );
    my $cmd;

    if ( exists( $opts_ref->{os_only} ) and $opts_ref->{os_only} ) {
        $cmd = 'cview.pl -i ' . $opts_ref->{instance} . ' -o';
    }
    elsif ( exists( $opts_ref->{clean_cache} ) and $opts_ref->{clean_cache} ) {
        $cmd =
            'cview.pl -i '
          . $opts_ref->{instance} . ' -s '
          . $opts_ref->{sr_num} . ' -e 0';
    }
    else {
        $cmd =
          'cview.pl -i ' . $opts_ref->{instance} . ' -s ' . $opts_ref->{sr_num};
    }

    if ($is_log_ok) {

        my $start  = DateTime->now();
        my $errors = 0;
        print $out join( ' ',
            'Connecting to',
            $opts_ref->{server}, 'under', $opts_ref->{instance}, '...' );
        my $ssh;
        my $fqdn = $opts_ref->{server} . '.oracleoutsourcing.com';

        try {
            $ssh = Oracle::EnvReview::Remote::Putty->new(
                { host => $fqdn, user => $user, password => $password } );
        }
        catch {
            $errors++;
            warn $_;
            return ssh_exception( $out, $_, $errors, $start,
                $opts_ref->{server}, $opts_ref->{instance} );
        };

        unless (( defined( blessed($ssh) ) )
            and ( blessed($ssh) eq 'Oracle::EnvReview::Remote::Putty' ) )
        {
            $errors++;
            return ssh_exception(
                $out,
'Could not create an instance of Oracle::EnvReview::Remote::Putty',
                $errors,
                $start,
                $opts_ref->{server},
                $opts_ref->{instance}
            );
        }
        else {
            print $out "done\n";
            print $out "Executing commands '$cmd'...\n";

            unless ( $ssh->exec( [ '. .bash_profile', $cmd ] ) ) {
                $errors++;
                return ssh_exception( $out, "failed to execute $cmd",
                    $errors, $start, $opts_ref->{server},
                    $opts_ref->{instance} );
            }

            foreach my $line ( @{ $ssh->get_last_cmd } ) {
                print $out $line, "\n";
            }
            print $out "Done executing commands\n";
            print $out 'Trying to copy response file... ';

            try {
                get_response( $ssh, $opts_ref->{server},
                    $opts_ref->{instance} );
            }
            catch {
                print $out $_;
                $errors++;
            };

            print $out "Done copying files\n";

        }

        my $elapsed = calc_elapsed($start);
        print $out
          join( ' ', 'Operation took', $elapsed, "seconds to finish\n" );
        close($out);
        return ( $errors, $elapsed, $opts_ref->{server},
            $opts_ref->{instance} );
    }
    else {
        warn "Failed to create log: $!";
        return ( 1, 0, $opts_ref->{server}, $opts_ref->{instance} );
    }

}

sub ssh_exception {
    my ( $fh, $error_msg, $errors, $start, $server, $instance ) = @_;
    my $elapsed = calc_elapsed($start);
    print $fh $error_msg, "\n";
    print $fh 'Operation took ', $elapsed, ' seconds ', " seconds to finish\n";
    return ( $errors, $elapsed, $server, $instance );
}

sub calc_elapsed {
    my $start = shift;
    my $end   = DateTime->now;
    my $dur   = $end->subtract_datetime($start);
    my ( $hours, $min, $sec ) = $dur->in_units( 'hours', 'minutes', 'seconds' );
    my $elapsed = ( $hours * 3600 ) + ( $min * 60 ) + $sec;
    return $elapsed;
}

sub get_response {
    my ( $ssh, $server, $instance ) = @_;
    my $location  = '/ood_repository/environment_review/results';
    my $file      = $instance . '_' . ( split( /\./, $server ) )[0] . '.xml';
    my $local_dir = File::Spec->catdir( getcwd(), 'tmp' );

    unless ( $ssh->download( $location, $file, $local_dir ) ) {
        confess "get $location/$file failed. Details: "
          . join( "\n\n", @{ $ssh->get_last_cmd } );
    }

}

sub read_cfg {
    my $yaml = LoadFile(shift);
    my %entries;
    my $user          = $yaml->{ssh_login};
    my $customer      = $yaml->{customer};
    my $threads_limit = $yaml->{threads};

    foreach my $instance ( keys( %{ $yaml->{instances} } ) ) {

# validating the configuration file to avoid repeating servers in the same instance
        unless ( exists( $entries{$instance} ) ) {
            $entries{$instance} = Set::Tiny->new();

            foreach my $host ( @{ $yaml->{instances}->{$instance} } ) {
                $entries{$instance}->insert($host);
            }

        }
        else {
            confess
"Something really bad happens because I cannot find $instance in the YAML!";
        }
    }

    # maintain same interface for the rest of the program
    foreach my $instance ( keys(%entries) ) {
        my $set = $entries{$instance};
        $entries{$instance} = [ $set->members() ];
    }

    return $user, $customer, $threads_limit, \%entries;
}

sub join_threads {
    my ( $running, $fh ) = @_;
    my $joined = 0;

    foreach my $thread ( threads->list(threads::joinable) ) {
        my @ret_data = $thread->join();
        tee( $fh,
                'thread '
              . $thread->tid()
              . ' for server '
              . $ret_data[2]
              . ' of instance '
              . $ret_data[3]
              . ' returned '
              . $ret_data[0]
              . " errors\n" );

        $total_errors += $ret_data[0];
        $total_time   += $ret_data[1];
        $total_conn++;
        $threads_counter--;
        $joined++;
        $running->remove( $ret_data[2] );
    }

    tee( $fh, "joined $joined threads\n" );
    return 1;
}

sub check_cache {
    my $job_ref = shift;
    my $host    = ( split( /\./, $job_ref->{server} ) )[0];
    my $file    = File::Spec->catfile( getcwd(), 'tmp',
        ( $job_ref->{instance} . '_' . $host . '.xml' ) );
    return ( -s $file );
}
