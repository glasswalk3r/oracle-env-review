package Oracle::EnvReview::Remote::Putty;

use warnings;
use strict;
use Moo 2.000001;
use Types::Standard 1.000005 qw(Str ArrayRef);
use namespace::clean 0.25;
use File::Spec;
use Carp;
use File::Temp qw/:POSIX/;
use feature 'say';

# VERSION

has user => ( is => 'ro', isa => Str, required => 1, reader => 'get_user' );
has password =>
  ( is => 'ro', isa => Str, required => 1, reader => 'get_password' );
has host => ( is => 'ro', isa => Str, required => 1, reader => 'get_host' );
has putty_path => (
    is       => 'ro',
    isa      => Str,
    required => 0,
    reader   => 'get_putty_path',
    default =>
      sub { File::Spec->catdir( ( 'C:', 'Program Files (x86)', 'PuTTY' ) ) }
);
has last_cmd => (
    is       => 'ro',
    isa      => ArrayRef [Str],
    required => 0,
    reader   => 'get_last_cmd',
    writer   => '_set_last_cmd'
);

sub exec {
    my ( $self, $cmds_ref ) = @_;
    confess('command parameter must be an array reference')
      unless ( ref($cmds_ref) eq 'ARRAY' );
    my $log  = tmpnam();
    my $cmds = File::Temp->new();

    foreach my $cmd ( @{$cmds_ref} ) {
        print $cmds "$cmd\n";
    }

    $cmds->close();
    my @params = (
        '-ssh', '-batch', '-l', $self->get_user, '-pw', $self->get_password,
        '-m', $cmds->filename, $self->get_host, '>', $log, '2>&1'
    );
    my $prog    = File::Spec->catfile( $self->get_putty_path, 'plink.exe' );
    my $cmd     = '"' . $prog . '" ' . join( ' ', @params );
    my $exec_ok = 0;
    my $ret     = system($cmd);

    unless ( $ret == 0 ) {

        if ( $? == -1 ) {
            print "failed to execute: $!\n";
        }
        elsif ( $? & 127 ) {
            printf "child died with signal %d, %s coredump\n",
              ( $? & 127 ), ( $? & 128 ) ? 'with' : 'without';
        }
        else {
            printf "child exited with value %d\n", $? >> 8;
        }

    }
    else {
        $exec_ok = 1;
    }

    $self->_set_last_cmd( $self->_read_out($log) );
    return $exec_ok;
}

sub _read_out {
    my ( $self, $log ) = @_;
    open( my $in, '<', $log ) or die "Cannot read $log: $!";
    my @log = <$in>;
    close($log);
    chomp(@log);
    warn "output file read is empty" unless ( scalar(@log) > 0 );
    return \@log;
}

sub download {
    my ( $self, $remote_dir, $remote_file, $local_dir ) = @_;
    my @cmds = (
        "cd $remote_dir",
        "lcd \"$local_dir\"",
        "get $remote_file",
        "del $remote_file"
    );
    my $cmds = File::Temp->new();

    foreach my $cmd (@cmds) {
        print $cmds "$cmd\n";
    }

    $cmds->close();
    my $log = tmpnam();

    my @params = (
        '-batch', '-l', $self->get_user, '-pw', $self->get_password, '-b',
        $cmds->filename, $self->get_host, '>', $log, '2>&1'
    );
    my $prog    = File::Spec->catfile( $self->get_putty_path, 'psftp.exe' );
    my $cmd     = '"' . $prog . '" ' . join( ' ', @params );
    my $exec_ok = 0;
    my $ret     = system($cmd);

    unless ( $ret == 0 ) {

        if ( $? == -1 ) {
            print "failed to execute: $!\n";
        }
        elsif ( $? & 127 ) {
            printf "child died with signal %d, %s coredump\n",
              ( $? & 127 ), ( $? & 128 ) ? 'with' : 'without';
        }
        else {
            printf "child exited with value %d\n", $? >> 8;
        }

    }
    else {
        $exec_ok = 1;
    }

    $self->_set_last_cmd( $self->_read_out($log) );
    sleep 1;
    unlink $log or warn "Could not remove $log: $!";
    return $exec_ok;
}

sub _read_log {
    my ( $self, $log ) = @_;
    my @log;

    #Incoming packet #0xd, type 94 / 0x5e (SSH2_MSG_CHANNEL_DATA)
    my $data_regex  = qr/^Incoming\spacket.*\(SSH2_MSG_CHANNEL_DATA\)$/;
    my $other_regex = qr/^\w+/;
    open( my $in, '<', $log ) or die "Cannot read log on $log: $!";
    my $is_data = 0;
    my $line;

    while (<$in>) {
        chomp();

        if ( $_ =~ $data_regex ) {
            $is_data = 1;
            next;
        }

        if ( ($is_data) and ( $_ !~ $other_regex ) ) {
            my @columns = split( /\s{2}/, $_ );

  #  00000000  00 00 01 00 00 00 00 48 20 31 36 3a 34 34 3a 35  .......H 16:44:5
  #00 00 01 00 00 00 00 48 20 31 36 3a 34 34 3a 35
            if ( substr( $columns[2], 0, 8 ) eq '00 00 01' )
            {    # "control" characters, or whatever they really mean
                my @tmp = split( /\s/, substr( $columns[2], 24 ) );

                foreach my $chr (@tmp) {

                    if ( $chr eq '0a' ) {
                        push( @log, $line ) if ( defined($line) );
                        $line = undef;
                    }
                    else {
                        $line .= chr( hex($chr) );
                    }

                }

            }
            else {
                my @tmp = split( /\s/, $columns[2] );

                # TODO: duplicated code from above
                foreach my $chr (@tmp) {

                    if ( $chr eq '0a' ) {
                        push( @log, $line ) if ( defined($line) );
                        $line = undef;
                    }
                    else {
                        $line .= chr( hex($chr) );
                    }

                }
            }
            next;
        }

        if ( $_ =~ $other_regex ) {
            $is_data = 0;
        }

    }

    close($in);
    return \@log;
}

1;
