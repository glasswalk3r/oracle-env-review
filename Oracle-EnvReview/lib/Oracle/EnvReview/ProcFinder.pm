package Oracle::EnvReview::ProcFinder;
use warnings;
use strict;
use XML::Writer 0.625;
use Proc::ProcessTable 0.53;
use Hash::Util qw(lock_keys);
use Oracle::EnvReview::ExecPbrun;
use File::Spec;
use Storable qw(fd_retrieve);
use Carp;
use Try::Tiny 0.24;
use Oracle::EnvReview::FilesDef qw(untaint_path);
use Oracle::EnvReview::XMLConverter qw(app_2_xml);
use base 'Class::Accessor';

=head1 NAME

Oracle::EnvReview::ProcFinder - class to find and execute Oracle applications to get their version

=cut

# VERSION
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(qw(home user app_prog));
__PACKAGE__->mk_ro_accessors(
    qw(xml_file fname_regex pbrun_prog cmdline_regex fifo sr_num home_regex instance parser child_pid pid)
);

=head1 DESCRIPTION

This class is to be used to search for a running process from a giving Oracle application.

Once the process, home directory and user from it is determined, the object will execute an external program
to retrieve it's name and version.

The external program will be executed through C<pbrun> by a child process previously forked.

The result of the process is an XML file with the application name and version.

=head1 ATTRIBUTES

=head2 pid

The PID of the application that was being searched and was found. Set automatically, this is a read-only attribute.

=head2 child_pid

The PID of the child process after the C<fork>.

The child process will execute the program defined in C<app_prog>.

=head2 multiple

This attribute is a boolean (in the Perl concepts, 0 or 1).

If true, when checking the running processes the object will try to find the same process running from different locations
(for example, there are multiple instances of OHS installed in the same server) and try to check their versions.

Otherwise, after finding the first process that matches the C<cmdline_regex> the object will stop searching, which in fact will speed up
the results.

This attribute is optional and the default value is 0 (false).

=head2 cmdline_regex

A string of a regular expression to match the application program running in /proc.

Read-only and required.

=head2 home_regex

A string of a regular expression used for substitution of string in the string previously
matched by C<cmdline_regex>. Part of this string will be used to identify where the Oracle application
was installed (it's home directory).

Read-only and optional. If no value is given during object creation it will be set to cmdline_regex value by default.

An example of how this is suppose to work, considering that this command line was recovered from the OS:

    # /talq5i/applmgr/fs1/FMW_Home/jrockit64/jre/bin/java -Dweblogic.Name=AdminServer -Djava.security.policy=null
    # |                          |                   |                              |
    # |                          |                   |<-       cmdline_regex      ->|
    # |<-  application home    ->|

In this example you would want to setup C<home_regex> with the string C</j.*/jre/bin/java>.

=head2 sr_num

A string of a Service Request (SR) number to be used.

Only useful for executing in production hosts where C<pbrun> will required a SR number.

This parameter is optional. If not set, it defaults to "1-1".

=head2 fifo

The name of a fifo that will be created to allow communication between granparent process with grandchild process.

The fifo will be created automatically in C</tmp> directory when necessary with permission mode set to 0777.

Read-only and required.

=head2 xml_file

String describing the complete pathname to a XML file that will keep results of the execution.

Read-only and required.

=head2 fname_regex

A string of a regular expression used to match the program file name to search for (not the complete pathname, see L<Proc::ProcessTable::Process> C<fname> method).

Read-only and required.

=head2 pbrun_prog

The complete pathname to the program to execute when fname is found through C<pbrun>.

Read-only and required.

=head2 instance

A string representing the instance name.

Read-only and required.

=head2 home

String of the home directory where the application is installed. In most cases, required
to set the ORACLE_HOME environment variable before running a program to retrieve the
application version.

This attribute will be determined during execution by invocation of C<get_oracle_home> method.

=head2 user

String of the user that is executing a process that this class will search for.

This attribute will be determined during execution.

=head2 app_prog

String of the complete path to the program of the Oracle application that prints application name and version.

This attribute will be determined during execution.

=head2 parser

An code reference that will receive a string as output from C<app_prog>, parse it and return a L<Oracle::EnvReview::Application> (or subclass) instance.

Read-only and optional. This is intented to be use with programs that cannot provide output serialized with L<Storable>, in other words, programs that were not
written in Perl or you don't have access to the source code for modification (although you could write a wrapper).

Of course, you will need to known previously how the program to be executed output will be to be able to parse it correctly.

This code reference will receive a single row as parameter to it. It has to return a hash reference as result, containing key values (hopefully, at least
the application name and version). Below follows an example:

    my $finder = Oracle::EnvReview::ProcFinder->new(
        {
            xml_file    => $filename,
            instance    => $instance,
            fname_regex => 'oidldapd',
            fifo        => $MY_FIFO,
            pbrun_prog  => File::Spec->catfile($Config{bin},'find_oid.pl'),
            cmdline_regex => '\/idm\/product\/.*\/bin\/oidldapd',
            sr_num        => $sr_num,
            home_regex    => '\/bin\/oidldapd',
            parser => sub {
                my $row = shift;
                chomp($row);
                my ( $app, $version ) = split( '#', $row );
                return [
                    Oracle::EnvReview::Application->new( { name => $app, version => $version, patches => [] } );
                ];
            },
        }
    );

 Maybe it is not intuitive, but since you receive a single line as parameter (and return an application from it), you also will be able to invoke it as long as
 rows you have, returning multiple instances as required.

=head2 is_storable

This attribute is set automatically with true by default. If C<new> receives such attribute as parameter, then the passed value will be used.

You can check its value with C<is_storable> method, but shouldn't mess around with it.

It defines if the object is expecting program output read from a FIFO as a serialized data by L<Storable> or just a string.

=cut

=head1 METHODS

In the case where not mentioned, all read-only attribute will have their "get_" method.

The same for read and write attributes, they will have their "get_" and "set_" methods.

=head2 new

Creates a new instance of this class.

Expects a hash reference with all required attributes as keys.

Return a instance of this class.

=cut

sub new {
    my ( $class, $attribs_ref ) = @_;
    confess "Must receive an hash reference with attributes"
      unless ( ref($attribs_ref) eq 'HASH' );

    foreach my $attrib (
        qw(xml_file fname_regex pbrun_prog fifo cmdline_regex instance))
    {
        confess "attribute $attrib must be defined as an scalar"
          unless ( ( exists( $attribs_ref->{$attrib} ) )
            and ( defined( $attribs_ref->{$attrib} ) ) );
    }

    $attribs_ref->{home_regex} = $attribs_ref->{cmdline_regex}
      unless ( ( exists( $attribs_ref->{home_regex} ) )
        and ( defined( $attribs_ref->{home_regex} ) ) );

    $attribs_ref->{sr_num} = '1-1'
      unless ( ( exists( $attribs_ref->{sr_num} ) )
        and ( defined( $attribs_ref->{sr_num} ) ) );

    $attribs_ref->{multiple} = 0
      unless ( ( exists( $attribs_ref->{multiple} ) )
        and ( defined( $attribs_ref->{multiple} ) ) );

    # missing attributes
    foreach my $attrib (qw(user home app_prog child_pid app_found)) {
        $attribs_ref->{$attrib} = undef;
    }

    if ( exists( $attribs_ref->{parser} ) ) {
        confess "parser attribute must be a defined code reference"
          unless ( ( defined( $attribs_ref->{parser} ) )
            and ( ref( $attribs_ref->{parser} ) eq 'CODE' ) );
    }

    my $self = $attribs_ref;
    $self->{pid} = undef;
    if ( exists( $attribs_ref->{is_storable} ) ) {
        $self->{is_storable} = $attribs_ref->{is_storable};
    }
    else {
        $self->{is_storable} = 1;
    }
    bless( $self, $class );
    lock_keys( %{$self} );
    return $self;
}

=head2 get_args

Returns an array reference with arguments to the C<pbrun_prog> attribute.

This method can be overrided to give different parameters.

Since version 0.03, the C<-f> command line option is required to give the location
of the FIFO for the programs to execute, so keep that in mind when subclassing or
your subclass won't work as expected.

Current this method also returns the following options:

=over

=item *

-o C<get_home> method return value

=item *

-c C<get_app_prog> method return value

=item *

-f C<get_fifo> method return value.

=back

=cut

sub get_args {
    my $self = shift;
    return [
        '-o',                  $self->get_home(), '-c',
        $self->get_app_prog(), '-f',              $self->get_fifo()
    ];
}

=head2 get_cmdline_cregex

Returns a compiled, case insensitive regular expression based on C<cmdline_regex>.

=cut

sub get_cmdline_cregex {
    my $self = shift;
    my $temp = $self->get_cmdline_regex;
    return qr/$temp/i;
}

=head2 get_fname_cregex

Returns a compiled, case insensitive regular expression based on C<fname_regex>.

=cut

sub get_fname_cregex {
    my $self = shift;
    my $temp = $self->get_fname_regex();
    return qr/$temp/i;
}

=head1 is_multiple

Returns true or false depending on the value of the attribute C<multiple>.

=cut

sub is_multiple {
    my $self = shift;
    return $self->{multiple};
}

=head2 search_procs

Search and execute programs as found by object attribute C<cmdline_regex>. It is expected that the
command line can be matched to the C<instance> attribute (case insensite comparison). This is necessary to find the correct process
corresponding to the instance that is being search for as some servers are used by multiple instances.

All results will be written to the XML file defined by C<xml_file> attribute.

=cut

sub search_procs {
    my $self           = shift;
    my $proc           = Proc::ProcessTable->new();
    my $cmdline_regex  = $self->get_cmdline_cregex;
    my $instance       = $self->get_instance;
    my $instance_regex = qr/$instance/i;
    my $fname_regex    = $self->get_fname_cregex();
    my %saw_apps;

    foreach my $process ( @{ $proc->table } ) {

        if (    ( $process->fname =~ $fname_regex )
            and ( $process->cmndline =~ $cmdline_regex ) )
        {
            next unless ( $process->cmndline =~ $instance_regex );

            # getting only the program path
            my $cmd  = $self->get_cmd($process);
            my $home = $self->get_oracle_home($process);

            if (    ( exists( $saw_apps{$cmd} ) )
                and ( $saw_apps{$cmd} eq $home ) )
            {
                next;
            }
            else {
                $self->set_user(
                    $self->_untaint(
                        scalar( getpwuid( $process->uid ) ), qr/^(\w+)$/
                    )
                );
                $self->set_home($home);
                $self->set_app_prog($cmd);
                $self->_set_pid(
                    $self->_untaint( $process->pid, qr/^(\d+)$/ ) );
                $self->exec_app;

                if ( $self->is_multiple ) {
                    $saw_apps{$cmd} = $home;
                }
                else {
                    last;
                }

            }

        }
    }

    if ( $self->get_child_pid ) {
        confess("Could not match any application with current configurations")
          unless ( $self->_got_app );
    }
    else {
        warn "child process shouldn't be here";
    }
    return 1;
}

sub _app_found {
    my $self = shift;
    $self->{app_found} = 1;
}

sub _got_app {
    return shift->{app_found};
}

sub _set_pid {
    my ( $self, $value ) = @_;
    $self->{pid} = $value;
}

sub _set_child_pid {
    my ( $self, $value ) = @_;
    $self->{pid} = $value;
}

sub _untaint {
    my ( $self, $value, $regex ) = @_;
    if ( $value =~ $regex ) {
        return $1;
    }
    else {
        confess "insecure value '$value'";
    }
}

=head2 get_cmd

Returns the program complete path read from C</proc> without arguments.

Expects as parameter a L<Proc::ProcessTable> object.

=cut

sub get_cmd {
    my ( $self, $process ) = @_;
    confess 'must receive a Proc::ProcessTable::Process object as parameter'
      unless (
        ( defined($process) )
        and (  ( ref($process) eq 'Proc::ProcessTable::Process' )
            or ( $process->isa('Proc::ProcessTable::Process') ) )
      );
    return untaint_path( ( split( /\s/, $process->cmndline ) )[0] );
}

=head2 get_oracle_home

This method returns the complete pathname expected to be used as value for the C<ORACLE_HOME>
environment variable.

This implementation is based on the process path (returned by method C<get_cmd>) and the regular
expression returned by C<get_home_regex> method to remove the undesired parts.

=cut

sub get_oracle_home {
    my $self       = shift;
    my $process    = shift;
    my $home       = $self->get_cmd($process);
    my $home_regex = $self->get_home_regex;
    $home =~ s#$home_regex##i;
    return $home;
}

sub _create_fifo {
    my $self = shift;
    my $fifo = $self->get_fifo;
    require POSIX;    #avoiding loading it by child process

    unless ( ( -e $fifo ) and ( -p $fifo ) ) {

 # to allow remove of the fifo by any user (current or anyone caught with pbrun)
        umask(0000);
        POSIX::mkfifo( $fifo, 0777 ) or warn "Cannot create $fifo: $!";
    }

    return $fifo;
}

=head2 exec_app

Forks a child process to execute an external program. Returns true if everything goes as expected.

The child process will execute a program through pbrun and will expect to find the named pipe to be write to
before executing the program and will wait and retry for it a couple of seconds. Otherwise it will abort execution
with C<confess>.

The program executed through pbrun will have its output collected and written to the named piped defined by C<fifo>.

If the method C<is_storable> returns false, the grandparent process will parse the output read from the named pipe
through C<get_parser> method and print to the XML file defined by C<xml_file> attribute. B<Beware> that you can read
multiple lines when using C<parser> attribute, but those rows will all be stored in memory at once. Don't use
this option if the program potentially prints a lot of data!

If the method C<is_storable> returns true, it is expected that the child process will write an array reference with
one or more instances of L<Oracle::EnvReview::Application>.

To avoid deadlock, there is a hardcoded timeout for reading the named pipe of 30 seconds. After this time, the
object will C<confess> with an error message.

This method is automatically invoked by the C<search_procs> method when a process matches the regular expressions.

=cut

sub exec_app {
    my $self      = shift;
    my $child_pid = fork();
    my $timeout   = 60;

    # parent
    if ($child_pid) {
        warn "forked $child_pid";
        $self->_set_child_pid($child_pid);
        my $fifo = $self->_create_fifo();
        my $apps_ref;

        try {
            local $SIG{ALRM} =
              sub { confess "Read from $fifo timeout (set to $timeout)\n" };
            alarm $timeout;
            open( my $in, '<', $fifo ) or confess "Cannot read from $fifo: $!";

            if ( $self->is_storable ) {
                binmode($in) or confess "Cannot set $fifo to binary mode: $!";

                # should receive an array reference
                $apps_ref = fd_retrieve($in);
            }
            else {
                # text mode input
                $apps_ref = [];

                # should work better with pipe
                while (<$in>) {
                    chomp();
                    push( @{$apps_ref}, $self->get_parser->($_) );
                }
            }
            close($in);
            alarm 0;
            $self->_app_found;
            sleep 1;
        }
        catch {
            warn $_;
            if ( kill 0, $child_pid ) {
                kill 'KILL', $child_pid;
                waitpid( $child_pid, 0 );
            }
            confess "an error ocurred while trying to read from fifo $fifo: $_";
        };

        my $xml =
          XML::Writer->new( OUTPUT =>
              ( IO::File->new( ( '>>' . $self->get_xml_file ) ), UNSAFE => 1 )
          );
        app_2_xml( $xml, $apps_ref, $self->get_home );
        $xml->end();
        print 'Waiting for the child process to complete... ';
        waitpid( $child_pid, 0 );
        print "done\n";
        unlink($fifo) or warn "could not remove $fifo: $!";
    }
    elsif ( $child_pid == 0 ) {
        sleep(1);
        my $fifo = $self->get_fifo;
        print "Child process trying to use fifo $fifo\n";
        my $retries   = 3;
        my $ok_to_run = 0;

        while ($retries) {
            unless ( -p $fifo ) {
                sleep 10;
                $retries--;
            }
            else {
                $ok_to_run = 1;
                last;
            }
        }

        confess 'Cannot execute '
          . $self->get_pbrun_prog
          . ' because named pipe '
          . $fifo
          . ' is not available'
          unless ($ok_to_run);
        my $exit = exec_pbrun(
            $self->get_user,   $self->get_instance, $self->get_pbrun_prog,
            $self->get_sr_num, $self->get_args
        );
        print 'Script ', $self->get_pbrun_prog, ' returned ', '(', $exit, ")\n";
        exit;
    }
    else {
        confess "fork failed: $!";
    }

}

=head2 get_parser

Getter for the C<parser> attribute.

It can be invoke multiple times, always returning a L<Oracle::EnvReview::Application> instance at each invocation.

This method is to be used internally, unless you're subclassing this class.

=head2 get_pid

Getter for the C<pid> attribute.

=head2 is_storable

Getter for the attribute C<is_storable>.

=cut

sub is_storable {
    return shift->{is_storable};
}

=head1 SEE ALSO

=over

=item *

L<Oracle::EnvReview::ExecPbrun>

=item *

L<Oracle::EnvReview::Application>

=back

=head1 AUTHOR

Alceu Rodrigues de Freitas Junior, E<lt>glasswalk3r@yahoo.com.brE<gt>

=cut

1;
