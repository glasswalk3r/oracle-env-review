#!/ood_repository/environment_review/perl -T
use warnings;
use strict;
use Linux::Info::SysInfo 0.9;
use POSIX qw(uname);
use File::Spec;
use Capture::Tiny 0.27 ':all';
use Getopt::Std;
use XML::Writer 0.625;
use Config;
use IO::File;
use File::Copy;
use Oracle::EnvReview::ExecPbrun;
use Oracle::EnvReview::FilesDef qw(temp_xml untaint_path);
use Oracle::EnvReview::ProcFinder;
use Oracle::EnvReview::ProcFinder::BRM;
use Oracle::EnvReview::ProcFinder::DBMS;
use Oracle::EnvReview::ProcFinder::OHS;
use Oracle::EnvReview::ProcFinder::Siebel;
use Oracle::EnvReview::ProcFinder::Weblogic;
use Oracle::EnvReview::Application 0.001;
use Oracle::EnvReview::Application::Weblogic 0.001;
use File::Temp qw(tempdir);
use Try::Tiny 0.24;
use Carp;
use Readonly;
use Config;
use Set::Tiny 0.04;
use YAML::XS 0.62 'LoadFile';
use Hash::Util qw(lock_hash);
use Oracle::EnvReview::Hints 'check_hints';

# VERSION
use constant ENV_REVIEW_HOME => '/ood_repository/environment_review';

# a hack to cases where oraInst.loc and ORACLE_HOME are not available, this is optional per server
use constant HINTS => '/ood_repository/environment_review/exceptions.yml';
Readonly my $TEMP_DIR => tempdir( CLEANUP => 1 );
chmod 0777, $TEMP_DIR;

# insecure, should review it, but needs to be accessible by processes of different users
umask(000);
Readonly my $MY_FIFO => File::Spec->catfile( $TEMP_DIR, 'cview.fifo' );
die "This program will only work with Linux"
  unless ( $Config{osname} eq 'linux' );

my %opts;
getopts( 'i:s:e:vho', \%opts );

# validates and locks %opts
my %options;
my $instance = check_params();

my $filename = temp_xml( $TEMP_DIR, $opts{i} );

os_only($filename) if ( ( exists( $opts{o} ) ) and ( $opts{o} ) );

start_xml($filename);
my $locations_ref;
my $opatch_errors = 0;
my ( $users_ref, $logins ) = find_app_users($instance);
add_comment( $filename, 'Starting generic process with opatch' );

# searching for apps in the default oraInst.loc
try {

    my $default_orainst = File::Spec->catfile( '', 'etc', 'oraInst.loc' );
    my $inventory_file  = File::Spec->catfile( get_inventory($default_orainst),
        'ContentsXML', 'inventory.xml' );

    # the inventory file corresponds to the instance we are checking
    if ( $inventory_file =~ /^\/$instance/ ) {

# assuming some standard here, that the directory following the instance name is where an application is installed
        my @dirs = File::Spec->splitdir($inventory_file);

        # first index is "/"
        my $root  = File::Spec->catdir( $dirs[0], $dirs[1], $dirs[2] );
        my $owner = validate_owner($root);
        if ( $logins->has($owner) ) {
            add_comment( $filename,
                "inventory file is available for user $owner" );
            my %args = (
                instance   => $instance,
                catalog    => $inventory_file,
                is_default => 1,
                sr_num     => $opts{s},
                expires    => $opts{e},
                temp_dir   => $TEMP_DIR,
                user       => $owner
            );
            $opatch_errors += run_opatch( \%args );
        }

    }
    else {
        add_comment( $filename, "$inventory_file is part of other instance" );
    }

}
catch {
    add_comment( $filename, $_ );
};

foreach my $home ( keys( %{$users_ref} ) ) {

    my $owner;
    add_comment( $filename, "Checking opatch at $home" );

    try {
        $owner = validate_owner($home)
    }
    catch {
        add_comment( $filename, $_ );
    };

    # using next inside the catch blocks causes warnings
    unless ( defined($owner) ) {
        add_comment( $filename, "could not define a owner for $home" );
        next;
    }
    else {
        add_comment( $filename, "$owner is the owner of $home" );
    }

    my %args = (
        instance   => $instance,
        sr_num     => $opts{s},
        user       => $users_ref->{$home}->{login},
        xml_file   => $filename,
        is_default => 0,
        temp_dir   => $TEMP_DIR,
        expires    => $opts{e}
    );

    if ( $users_ref->{$home}->{login} eq $owner ) {

        if ( -r HINTS ) {
            add_comment( $filename, 'using HINTS file' );
            my $hints = check_hints( HINTS, $instance );

            if ( defined($hints) ) {
                my $invent_ref = $hints->get_inventories;

                foreach my $inventory ( @{$invent_ref} ) {
                    $inventory = untaint_path($inventory);
                    add_comment("opatch exception available at $inventory");
                    $args{catalog}    = $inventory;
                    $args{is_default} = 1;
                    $opatch_errors += run_opatch( \%args );
                }

            }
            else {
                add_comment( $filename,
                    "no hints available for this instance" );
                $opatch_errors += run_opatch( \%args );
            }

        }
        else {
            add_comment( $filename, 'no HINTS file available' );
            $opatch_errors += run_opatch( \%args );
        }

    }
    else {
        add_comment( $filename,
            "$home is property of $owner instead "
              . $users_ref->{$home}->{login} );
        $args{user} = $owner;
        $opatch_errors += run_opatch( \%args );
    }

}

my $instance_type = instance_type($instance);
add_comment( $filename, 'Starting specific instance process' );

CASE: {

    if ( $instance_type eq 'SIEBEL' ) {
        find_ohs( $filename, \%options );
        find_oracle_db( $filename, \%options );
        find_oid( $filename, \%options );
        find_siebel( $filename, \%options );
        last CASE;
    }

    if ( $instance_type eq 'OTO' ) {
        find_ohs( $filename, \%options );
        find_oracle_db( $filename, \%options );
        find_oid( $filename, \%options );
        find_brm( $filename, \%options );
        find_weblogic( $filename, \%options );
        last CASE;
    }

# TODO: EBSO application users have a banner being printed to STDOUT and this
# is causing an issue with find_ohs.pl script (needs ENTER after the banner to continue processing)
    if ( $instance_type eq 'EBSO' ) {
        find_oracle_db( $filename, \%options, 1 );
        find_weblogic( $filename, \%options );
        find_ohs( $filename, \%options );
    }
    else {
        find_java($filename);
        find_oracle_db( $filename, \%options );
        find_weblogic( $filename, \%options );
        find_ohs( $filename, \%options );
    }
}

end_xml( $filename, $opatch_errors );

copy( $filename, File::Spec->catfile( ENV_REVIEW_HOME, 'results' ) )
  or warn "Cannot copy $filename: $!";

###########################################
# subs

sub os_only {
    start_xml($filename);
    end_xml( $filename, $opatch_errors );
    my $dest = File::Spec->catfile( ENV_REVIEW_HOME, 'results' );
    warn "$dest is not available" unless ( -d $dest );
    copy( $filename, $dest ) or warn "Cannot copy $filename: $!";
    exit 0;
}

sub run_opatch {
    my $opts_ref = shift;
    my $instance = $opts_ref->{instance};
    my $user     = untaint_string( $opts_ref->{user} );
    my $sr_num   = $opts_ref->{sr_num};
    $opts_ref->{is_default} = 0 unless ( defined( $opts_ref->{is_default} ) );
    my $is_default = untaint_string( $opts_ref->{is_default} );
    my $expires    = untaint_string( $opts_ref->{expires} );
    my $temp_dir   = untaint_path( $opts_ref->{temp_dir} );
    my $opatch =
      File::Spec->catfile( untaint_path( $Config{bin} ), 'run_opatch.pl' );
    my @args = ( '-i', $instance, '-t', $temp_dir, '-e', $expires );

    if ($is_default) {
        if (    ( exists( $opts_ref->{catalog} ) )
            and ( defined( $opts_ref->{catalog} ) ) )
        {
            my $catalog = untaint_path( $opts_ref->{catalog} );
            push( @args, '-d', '-c', $catalog );
            my $exit = exec_pbrun( $user, $instance, $opatch, $sr_num, \@args );
            return $exit;
        }
        else {
            confess
'cannot run opatch without a catalog defined in the default location';
        }
    }
    else {
        # try to use application user ORACLE_HOME instead
        my $oracle_home = $ENV{ORACLE_HOME};
        delete $ENV{ORACLE_HOME};
        my $exit = exec_pbrun( $user, $instance, $opatch, $sr_num, \@args );
        $ENV{ORACLE_HOME} = $oracle_home;
        return $exit;
    }
}

sub untaint_string {
    my $string = shift;
    if ( $string =~ /^(\w+)$/ ) {
        return $1;
    }
    else {
        confess "invalid/insecure string '$string'";
    }
}

sub get_inventory {
    my $file = shift;
    open( my $in, '<', $file ) or die "Cannot read $file $!";
    my ( $key, $value );

    while (<$in>) {
        chomp;

        # inventory_loc
        if (/^inventory_loc/) {
            ( $key, $value ) = split( /\=/, $_ );
            last;
        }
    }

    close($in);
    return $value;
}

sub find_app_users {
    my $instance = shift;
    my %users;
    my @logins;
    my $file  = '/etc/passwd';
    my $regex = qr/$instance/;
    open( my $in, '<', $file ) or die "Cannot read $file: $!";
    my $hints;

    if ( -r HINTS ) {
        $hints = check_hints( HINTS, $instance );
    }

    while (<$in>) {

        if (/$regex/) {
            chomp;
            my @fields = split( ':', $_ );
            next
              if (  ( defined($hints) )
                and ( $hints->skip_user( $fields[0] ) ) );
            $users{ $fields[5] } = { login => $fields[0] };
            push( @logins, $fields[0] );
        }

    }

    close($in);
    my $logins = Set::Tiny->new(@logins);
    return \%users, $logins;
}

sub get_linux_dist {
    my $file = '/etc/oracle-release';
    open( my $in, '<', $file ) or die "Cannot read $file: $!";
    my $line;

    while (<$in>) {
        chomp;
        $line = $_;
        last;
    }

    close($in);
    return $line;
}

sub get_sys_info {
    my $sys = Linux::Info::SysInfo->new;
    return {
        vcpu     => $sys->get_tcpucount,
        arch     => $sys->get_proc_arch,
        memory   => $sys->get_mem,
        pcpu     => $sys->get_pcpucount,
        hostname => $sys->get_hostname
    };
}

sub validate_owner {
    my $object = shift;
    confess "home parameter is required" unless ( defined($object) );
    confess "home parameter must be directory" unless ( -e $object );
    my @values = stat($object);
    confess "directory $object does not exists" if ( $#values == -1 );
    confess "directory $object does not have an owner"
      unless ( defined( $values[4] ) );
    my $owner = getpwuid( $values[4] );
    confess "could not find the login associated with owner Id $values[4]"
      unless ( defined($owner) );

    if ( $owner eq 'root' ) {
        confess "cannot pbrun to root user (owner of $object)";
    }
    return $owner;
}

sub start_xml {
    my $filename = shift;
    my $file     = IO::File->new(">>$filename");
    my $output   = XML::Writer->new( OUTPUT => $file, UNSAFE => 1 );
    $output->startTag('server');
    my $kernel = ( uname() )[2];
    my ( $os_version, $os_level ) = split( '-', $kernel );
    my $info_ref = get_sys_info();
    $output->dataElement( 'name',             $info_ref->{hostname} );
    $output->dataElement( 'virtualCPUCount',  $info_ref->{vcpu} );
    $output->dataElement( 'osBitVersion',     $info_ref->{arch} );
    $output->dataElement( 'physicalCPUCount', $info_ref->{pcpu} );
    $output->dataElement( 'memory',           $info_ref->{memory} );
    $output->dataElement( 'osSummary',        get_linux_dist() );
    $output->dataElement( 'osVersion',        $os_version );
    $output->dataElement( 'osLevel',          $os_level );
    $output->startTag('applications');
}

sub add_comment {
    my ( $filename, $comment ) = @_;
    my $file   = IO::File->new(">>$filename");
    my $output = XML::Writer->new( OUTPUT => $file, UNSAFE => 1 );
    $output->comment($comment);
    $output->end;
}

sub end_xml {
    my ( $filename, $opatch_errors ) = @_;
    my $file   = IO::File->new(">>$filename");
    my $output = XML::Writer->new( OUTPUT => $file, UNSAFE => 1 );
    $output->dataElement( 'opatchErrors', $opatch_errors );
    $output->endTag('applications');
    $output->endTag('server');
    $output->end;
}

sub find_brm {
    my ( $filename, $opts_ref ) = @_;
    my $instance = $opts_ref->{i};
    my $sr_num;

    ( exists( $opts_ref->{s} ) )
      ? ( $sr_num = $opts_ref->{s} )
      : ( $sr_num = undef );

    add_comment( $filename, 'Searching for BRM' );

    try {
        my $finder = Oracle::EnvReview::ProcFinder::BRM->new(
            {
                xml_file    => $filename,
                instance    => $instance,
                fname_regex => 'dm_oracle',
                fifo        => $MY_FIFO,
                pbrun_prog  => File::Spec->catfile(
                    $Config{bin}, 'find_brm.pl
                '
                ),
                cmdline_regex => 'appsvr\/product\/.*\/bin\/dm_oracle',
                sr_num        => $sr_num,
                home_regex    => '\/bin\/dm_oracle',
                parser        => sub {

                    my $row = shift;
                    chomp($row);
                    my ( $app, $version ) = split( '#', $row );
                    return ( $app, $version );

                },

            }
        );
        $finder->search_procs;
    }
    catch {
        add_comment( $filename, $_ );
    };

}

sub find_weblogic {
    my ( $filename, $opts_ref ) = @_;
    my $instance = $opts_ref->{i};
    my $sr_num;

    ( exists( $opts_ref->{s} ) )
      ? ( $sr_num = $opts_ref->{s} )
      : ( $sr_num = undef );

    add_comment( $filename, 'Searching for Weblogic' );

    try {
        my $finder = Oracle::EnvReview::ProcFinder::Weblogic->new(
            {
                xml_file    => $filename,
                instance    => $instance,
                fname_regex => 'java',
                fifo        => $MY_FIFO,
                pbrun_prog =>
                  File::Spec->catfile( $Config{bin}, 'weblogic_version.sh' ),

# /server/applmgr/fs1/FMW_Home/jrockit64/jre/bin/java -Dweblogic.Name=AdminServer -Djava.security.policy=null
# |                           |                   |                              |
# |                           |                   |<-       cmdline_regex      ->|
# |<- home                  ->|
                cmdline_regex => 'Dweblogic\.Name\=AdminServer',
                sr_num        => $sr_num,
                home_regex    => '/j.*/jre/bin/java',

#WebLogic Server#10.3.6.0#10.3.6.0.161018#13729611:13845626:13964737:17319481:17495356:19259028:19687084:20474010:24608998:${CRS}#oacore_server13#1.7.0_121#64#Oracle Corporation#Java HotSpot(TM) 64-Bit Server VM
                parser => sub {
                    my $row = shift;
                    chomp($row);
                    my (
                        $name,      $version,        $psu,
                        $bugs,      $managed_server, $java_version,
                        $java_arch, $java_vendor,    $java_vm
                    ) = split( '#', $row );
                    my %attribs = (
                        name           => $name,
                        version        => $version,
                        managed_server => $managed_server,
                        java_version   => $java_version,
                        java_arch      => $java_arch,
                        java_vendor    => $java_vendor,
                        java_vm        => $java_vm
                    );
                    $attribs{psu} = $psu if ( defined($psu) );
                    my @patches = split( ':', $bugs );
                    $attribs{patches} = \@patches;
                    return Oracle::EnvReview::Application::Weblogic->new(
                        \%attribs );
                },
            }
        );
        $finder->search_procs;
    }
    catch {
        add_comment( $filename, $_ );
        warn $_;
    };
}

sub find_oid {
    my ( $filename, $opts_ref ) = @_;
    my $instance = $opts_ref->{i};
    my $sr_num;

    ( exists( $opts_ref->{s} ) )
      ? ( $sr_num = $opts_ref->{s} )
      : ( $sr_num = undef );

    add_comment( $filename, 'Searching for OID' );

    try {
        my $finder = Oracle::EnvReview::ProcFinder->new(
            {
                xml_file    => $filename,
                instance    => $instance,
                fname_regex => 'oidldapd',
                fifo        => $MY_FIFO,
                pbrun_prog =>
                  File::Spec->catfile( $Config{bin}, 'find_oid.pl' ),
                cmdline_regex => '\/idm\/product\/.*\/bin\/oidldapd',
                sr_num        => $sr_num,
                home_regex    => '\/bin\/oidldapd',
                parser        => sub {
                    my $row = shift;
                    chomp($row);
                    my ( $app, $version ) = split( '#', $row );
                    return [
                        Oracle::EnvReview::Application->new(
                            {
                                name    => $app,
                                version => $version,
                                patches => []
                            }
                        )
                    ];
                },
            }
        );
        $finder->search_procs;
    }
    catch {
        add_comment( $filename, $_ );
    };
}

sub find_ohs {
    my ( $filename, $opts_ref ) = @_;
    my $instance = $opts_ref->{i};
    my $sr_num;

    ( exists( $opts_ref->{s} ) )
      ? ( $sr_num = $opts_ref->{s} )
      : ( $sr_num = undef );

    add_comment( $filename, 'Searching for OHS' );

    try {
        my $finder = Oracle::EnvReview::ProcFinder::OHS->new(
            {
                xml_file    => $filename,
                instance    => $instance,
                home_regex  => '/(Apache|OHS)/bin/httpd(\.worker)?',
                fname_regex => 'httpd(\.worker)?',
                fifo        => $MY_FIFO,
                multiple    => 1,
                pbrun_prog =>
                  File::Spec->catfile( $Config{bin}, 'find_ohs.pl' ),
                cmdline_regex => '\/(Apache|OHS)\/bin\/httpd',
                sr_num        => $sr_num,
                parser        => sub {
                    my $row = shift;
                    chomp($row);
                    my ( $app, $version ) = split( '#', $row );
                    return ( $app, $version );
                },
            }
        );
        $finder->search_procs;
    }
    catch {
        add_comment( $filename, $_ );
    };
}

sub find_oracle_db {
    my ( $filename, $opts_ref, $check_ebs ) = @_;
    $check_ebs = 0 unless ( defined($check_ebs) );
    my $instance = $opts_ref->{i};
    my $sr_num;

    add_comment( $filename, 'Searching for Oracle Database' );

    ( exists( $opts_ref->{s} ) )
      ? ( $sr_num = $opts_ref->{s} )
      : ( $sr_num = undef );

    try {
        my $finder = Oracle::EnvReview::ProcFinder::DBMS->new(
            {
                xml_file    => $filename,
                instance    => $instance,
                ebs_check   => $check_ebs,
                fname_regex => 'oracle',
                fifo        => $MY_FIFO,
                multiple    => 1,

# an special case, must rely on a different perl, provided to the Oracle DB OS user
                pbrun_prog    => 'perl',
                cmdline_regex => '^ora_pmon',
                sr_num        => $sr_num,
                parser        => sub { return 1 }
                ,    # this class doesn't parse output from the program
            }
        );
        $finder->search_procs;
    }
    catch {
        add_comment( $filename, $_ );
        warn $_;
    }
}

sub instance_type {
    my $instance = shift;
    confess "instance name is a required parameter"
      unless ( defined($instance) );
    my $type        = substr( uc($instance), ( length($instance) - 1 ) );
    my %known_types = (
        I => 'EBSO',
        O => 'OTO',
        K => 'PEOPLESOFT',
        V => 'PEOPLESOFT',
        J => 'PEOPLESOFT',
        2 => 'SIEBEL',
        3 => 'OBIEE',
        7 => 'HYPERION',
        8 => 'JDE'
    );
    if ( exists( $known_types{$type} ) ) {
        return $known_types{$type};
    }
    else {
        return 'Unknown';
    }
}

# this program should be available to all users, so no pbrun is required
# TODO: should leave the convertion to XML to XMLConverter module
sub find_java {
    my $xml_file = shift;
    confess "the xml full pathname is a required parameter"
      unless ( defined($xml_file) );
    add_comment( $xml_file, 'Searching for system wide JVM' );

    # search for system wide Java available
    try {
        my $file = IO::File->new(">>$xml_file");
        local $ENV{PATH} = '/bin:/usr/bin:/usr/local/bin';
        my ( $stdout, $stderr, $exit ) = capture {
            system( '/usr/bin/which', 'java' );
        };
        chomp($stdout);
        confess $stderr unless ( $exit == 0 );
        my $java_bin = untaint_path($stdout);
        ( $stdout, $stderr, $exit ) = capture {
            system( $java_bin, '-classpath', ENV_REVIEW_HOME, 'JavaArch' );
        };
        if ( $exit == 0 ) {
            chomp($stdout);
            my ( $version, $arch, $vendor ) = split( '#', $stdout );
            my $xml = XML::Writer->new( OUTPUT => $file, UNSAFE => 1 );
            $xml->startTag('application');
            $xml->dataElement( 'name',         'Java' );
            $xml->dataElement( 'version',      $version );
            $xml->dataElement( 'architecture', $arch );
            $xml->dataElement( 'vm_vendor',    $vendor );
            $xml->endTag('application');
        }
        else {
            confess "Failed to execute JavaArch with $java_bin -classpath '"
              . ENV_REVIEW_HOME
              . "' $stderr";
        }
    }
    catch {
        add_comment( $xml_file, $_ );
    };
}

# find_siebel will ignore home_regex because it will not execute
# a external program to find Siebel version
sub find_siebel {
    my ( $filename, $opts_ref ) = @_;
    my $instance = $opts_ref->{i};
    my $sr_num;

    ( exists( $opts_ref->{s} ) )
      ? ( $sr_num = $opts_ref->{s} )
      : ( $sr_num = undef );

    add_comment( $filename, 'Searching for Siebel' );
    try {
        my $finder = Oracle::EnvReview::ProcFinder::Siebel->new(
            {
                xml_file    => $filename,
                instance    => $instance,
                fname_regex => 'siebsvc',
                fifo        => $MY_FIFO,
                pbrun_prog =>
                  File::Spec->catfile( $Config{bin}, 'find_siebel.pl' ),
                cmdline_regex => 'sieb',
                sr_num        => $sr_num,
                home_regex    => 'siebel',
            }
        );
        $finder->search_procs;
    }
    catch {
        add_comment( $filename, $_ );
    };
}

# validates all command lines parameters and lock the hash
# beware that %opts and %options are globals
sub check_params {

    if ( $opts{v} ) {
        print <<BLOCK;
cview - customer environment view version $VERSION
BLOCK
        exit;
    }

    if ( $opts{h} ) {
        print <<BLOCK;
cview - customer environment view version $VERSION

This program will try to recover information about the server and Oracle applications installed on it.

Options:

-i <instance name>: required
-e: <days>: optional number of days to consider a Opatch product cache still valid. By default is 15 days. Non-numeric values will be ignored.
-s: <SR number>: optional, default Service Request number to use to pbrun on production systems
-o: OS basic information (CPU, memory, VCPU and processor architecture) only
-v: prints this program name and version and exit
-h: this help message
BLOCK
        exit;
    }

    unless ( ( exists( $opts{i} ) ) and ( defined( $opts{i} ) ) ) {
        die "must receive a value for the -i parameter";
    }
    else {
        if ( $opts{i} =~ /^(\w+\-?\w+)$/ ) {
            $opts{i} = $1;
        }
        else {
            die "Insecure value '$opts{i}' for instance name";
        }
    }

    if ( exists( $opts{s} ) ) {
        if ( $opts{s} =~ /^(\d\-\d+)$/ ) {
            $opts{s} = $1;
        }
        else {
            die '-s parameter only accept valid SRs numbers';
        }
    }
    else {
        $opts{s} = '1-1';
    }

    if ( exists( $opts{e} ) ) {
        if ( $opts{e} =~ /^(\d+)$/ ) {
            $opts{e} = $1;
        }
        else {
            die '-e parameter only accept integers as values';
        }
    }
    else {
        $opts{e} = 15;
    }

# copy comand line options to avoid messing around with the original values passed
    %options = %opts;
    lock_hash(%opts);
    my $instance;

    if ( $opts{i} =~ /\-dr$/ ) {

# instances that have a suffix "-dr" (which stands for "disaster recover") are essentially
# a copy of a running instance
# removing the suffix is necessary so this program can locate the related app users and processes
# on the other cases, the instance with the suffix is required to allow verification of apps installed
# without mixing results with the "source" instances
        $instance = ( split( '-', $opts{i} ) )[0];
        $options{i} = $instance;
    }
    else {
        $instance = $opts{i};
    }

    lock_hash(%options);
    return $instance;
}
