#!/ood_repository/environment_review/perl -T
use warnings;
use strict;
use XML::LibXML 2.0124 qw(:libxml);
use Cwd;
use File::Spec;
use Capture::Tiny 0.36 ':all';
use Getopt::Std;
use XML::Writer 0.625;
use Hash::Util qw(lock_keys);
use Config;
use IO::File;
use Storable qw(retrieve nstore);
use Carp;
use DateTime 1.27;
use File::HomeDir 1.00;
use Oracle::EnvReview::FilesDef qw(temp_xml untaint_path);
use Readonly;
use Oracle::EnvReview::XMLConverter qw(app_2_xml);
use Oracle::EnvReview::Application 0.001;
use Oracle::EnvReview::Application::None 0.001;
use Try::Tiny 0.24;
use Data::Dumper;

#generated with find2perl
use File::Find ();

# VERSION
# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name  = *File::Find::name;
*dir   = *File::Find::dir;
*prune = *File::Find::prune;

# WORKAROUND: sub "wanted" won't accept parameters
our @list;
my %opts;
getopts( 'i:c:t:e:vdh', \%opts );

if ( $opts{v} ) {
    print <<BLOCK;
run_opatch version $VERSION
BLOCK
    exit;
}

if ( $opts{h} ) {
    print <<BLOCK;
run_opatch - executes opatch with through an application user - version $VERSION

This program will execute opatch, hopefully the user that is the owner
of the ORACLE_HOME of the application.

Options:

-i <instance name>: required
-d: forces the program to use a specific oraInst.loc file to start searching
-c <complete path to catalogue file>: optional, required if -d is specified
-t <complete path to temporary working directory>: required
-e <days>: maximum number of days before Opatch product cache expires. Required.
-v: prints the program name and version
-h: this help message

BLOCK
}

foreach my $key (qw(t i e)) {
    confess "must receive a value for the $key parameter"
      unless ( ( exists( $opts{$key} ) ) and ( defined( $opts{$key} ) ) );
}

if ( $opts{d} ) {
    confess
"must receive a value for the -c (catalogue) parameter with -d (default) is in use"
      unless ( ( exists( $opts{c} ) ) and ( defined( $opts{c} ) ) );
}

confess "Invalid cache date expiration" unless ( $opts{e} =~ /^\d+$/ );

# XML file will be shared by different processes from different users
umask(000);
Readonly my $TEMP_DIR => untaint_path( $opts{t} );

# applications already printed into the XML, to avoid repeating them between multiple opatch executions
# each hash key will have the ORACLE_HOME value for each application already printed to the XML
my $apps_control = File::Spec->catfile( $TEMP_DIR, 'apps_control' );

# hash reference
my $apps_done;

if ( -e $apps_control ) {
    $apps_done = retrieve($apps_control);
}
else {
    $apps_done = {};
}

my $xml_path;

if ( $opts{i} =~ /^(\w+)$/ ) {
    $xml_path = '>>' . temp_xml( $TEMP_DIR, $1 );
}
else {
    confess "invalid/insecure instance name";
}

# :WORKAROUND:10/17/2014 04:35:29 PM:: UNSAFE to allow including other applications in the same execution
my $xml_out =
  XML::Writer->new( OUTPUT => IO::File->new($xml_path), UNSAFE => 1 );
$SIG{INT}  = sub { $xml_out->comment('caught a SIGINT') };
$SIG{TERM} = sub { $xml_out->comment('caught a SIGTERM') };
my $opatch_errors = 0;
Readonly my $CACHE_FILE =>
  File::Spec->catfile( untaint_path( File::HomeDir->my_home() ),
    '.opatch_prods_cache' );
my $prod_cache = manage_cache( $CACHE_FILE, $opts{e} );

if ( $opts{d} ) {

    my $locations_ref;
    try {
        $locations_ref = find_locations( untaint_path( $opts{c} ) );
    }
    catch {
        $xml_out->comment($_);
        $opatch_errors++;
    };

    foreach my $loc ( @{$locations_ref} ) {
        print "Checking $loc as ORACLE_HOME\n";

        unless ( exists( $prod_cache->{$loc} ) ) {
            my ( $apps_ref, $errors ) = exec_opatch( $loc, $xml_out );
            $opatch_errors += $errors;

            if (    ( ref($apps_ref) eq 'ARRAY' )
                and ( scalar( @{$apps_ref} ) > 0 ) )
            {
                $prod_cache->{$loc} = undef;
                add_apps( $prod_cache, $loc, $apps_ref );
                $apps_done->{$loc} = undef;
            }
            else {
                warn
                  "exec_opatch returned an invalid value as execution result";
            }

        }
        else {

            unless ( is_none($prod_cache) ) {
                unless ( exists( $apps_done->{$loc} ) ) {
                    app_2_xml( $xml_out, $prod_cache->{$loc} );
                    $apps_done->{$loc} = undef;
                }
                else {
                    $xml_out->comment("$loc already processed, skipping it");
                }
            }
        }
    }
}
else {

    # avoiding expensive find on the directory if cache is available
    if ( ( ref($prod_cache) eq 'HASH' ) and ( keys( %{$prod_cache} ) ) ) {

        unless ( is_none($prod_cache) ) {

            foreach my $loc ( keys( %{$prod_cache} ) ) {
                unless ( exists( $apps_done->{$loc} ) ) {
                    app_2_xml( $xml_out, $prod_cache->{$loc} );
                    $apps_done->{$loc} = undef;
                }
                else {
                    $xml_out->comment("$loc already processed, skipping it");
                }
            }

        }

    }
    else {

        if (    ( exists( $ENV{ORACLE_HOME} ) )
            and ( defined( $ENV{ORACLE_HOME} ) )
            and ( not( exists( $apps_done->{ $ENV{ORACLE_HOME} } ) ) ) )
        {
            $xml_out->comment(
                "Checking with default ORACLE_HOME '$ENV{ORACLE_HOME}'");
            my ( $apps_ref, $errors ) =
              exec_opatch( $ENV{ORACLE_HOME}, $xml_out );
            $opatch_errors += $errors;

            if (    ( ref($apps_ref) eq 'ARRAY' )
                and ( scalar( @{$apps_ref} ) > 0 ) )
            {
                $prod_cache->{ $ENV{ORACLE_HOME} } = undef;
                add_apps( $prod_cache, $ENV{ORACLE_HOME}, $apps_ref );
                $apps_done->{ $ENV{ORACLE_HOME} } = undef;
            }
            else {
                warn
"exec_opatch returned an invalid value as execution result, the number of errors registered are: $errors";
            }

        }

        my $oracle_home = untaint_path( $ENV{HOME} );

        try {
            File::Find::find(
                {
                    wanted          => \&wanted,
                    follow          => 0,
                    untaint         => 1,
                    untaint_pattern => qr|^([-+@\w./]+)$|
                },
                $oracle_home
            );
        }
        catch {
            $xml_out->comment(
"'find like' search in $oracle_home failed with error: $_\nLast try with default oraInst.loc under $oracle_home."
            );
            my $default = File::Spec->catfile( $oracle_home, 'oraInst.loc' );

            if ( -e $default ) {
                @list = ($default);
            }
            else {
                $xml_out->comment(
                    "$default does not exists, won't try to run opatch again");
            }
        };

        foreach my $file (@list) {

            my $locations_ref;
            my $inventory_file =
              File::Spec->catfile( get_inventory($file), 'ContentsXML',
                'inventory.xml' );

            $xml_out->comment("Checking inventory file $inventory_file");

            try {
                $locations_ref = find_locations($inventory_file);
            }
            catch {
                $xml_out->comment(
"An error ocurred when trying to parse '$inventory_file': $_"
                );
                $opatch_errors++;
            };

            my $regex = qr/^$ENV{HOME}/;

            foreach my $loc ( @{$locations_ref} ) {

                unless ( exists( $apps_done->{$loc} ) ) {
                    $xml_out->comment("Checking location '$loc'");

                    if ( $loc =~ /$regex/ ) {
                        my ( $apps_ref, $errors ) =
                          exec_opatch( $loc, $xml_out );
                        $opatch_errors += $errors;

                        if (    ( ref($apps_ref) eq 'ARRAY' )
                            and ( scalar( @{$apps_ref} ) > 0 ) )
                        {
                            $prod_cache->{$loc} = undef;
                            add_apps( $prod_cache, $loc, $apps_ref );
                            $apps_done->{$loc} = undef;
                        }
                        else {
                            warn "exec_opatch returned an invalid result";
                        }

                    }
                    else {
                        $xml_out->comment("'$loc' is not part of '$ENV{HOME}'");
                    }

                }
                else {
                    $xml_out->comment("$loc already processed, skipping it");
                }

            }

        }

    }

}

$xml_out->end;

save_cache( $CACHE_FILE, $prod_cache );

# saving what as found, the cache will be removed together with the temporary directory later
nstore( $apps_done, $apps_control );
exit($opatch_errors);

########################################
# subs

sub capture_opatch {

    my $opatch        = shift;
    my $args_ref      = shift;
    my $opatch_errors = 0;
    delete @ENV{qw(PATH IFS CDPATH ENV BASH_ENV)};
    my ( $stdout, $stderr, $exit ) = capture {
        system( $opatch, @{$args_ref} );
    };

    unless ( $exit == 0 ) {
        $opatch_errors++;
        my $ret_code = $exit >> 8;
        my $self     = getpwuid($<);
        warn(
"Execution of opatch with $self failed with return code $ret_code. Trying to retrieve STDERR and STDOUT from it..."
              . "STDERR = $stderr"
              . "STDOUT = $stdout" );
    }

    return ( \$stdout, \$stderr, $opatch_errors );
}

# expects a hash reference as parameter
# with the following keys:
# - before: XML tag to include before the application data, optional
# - after: XML tag to include after the application data, optional
# - output: the application output, required
# - xml: the XML::Writer instance, required
# - location: the location where the applications were found
sub output_2_xml {
    my $opts_ref = shift;
    foreach my $param (qw(output xml location)) {
        confess "parameter $param is required with a defined value"
          unless ( ( exists( $opts_ref->{$param} ) )
            and ( defined( $opts_ref->{$param} ) ) );
    }
    $opts_ref->{xml}->comment( $opts_ref->{before} )
      if ( exists( $opts_ref->{before} ) );

    # array ref
    my $products_ref = find_product( $opts_ref->{output}, $opts_ref->{xml},
        $opts_ref->{location} );

    # won't hurt to check it again
    if (    ( ref($products_ref) eq 'ARRAY' )
        and ( scalar( @{$products_ref} ) > 0 ) )
    {
        app_2_xml( $opts_ref->{xml}, $products_ref );
    }
    else {
        $opts_ref->{xml}
          ->comment( 'No products found in ' . $opts_ref->{location} );
    }
    $opts_ref->{xml}->comment( $opts_ref->{after} )
      if ( exists( $opts_ref->{after} ) );
    return $products_ref;
}

sub opatch_version {
    my ( $opatch, $xml ) = @_;
    my ( $output_ref, $error_ref, $opatch_errors ) =
      capture_opatch( $opatch, ['version'], $xml );

    if ( ( defined($opatch_errors) ) and ( $opatch_errors > 0 ) ) {
        return undef;
    }
    else {

        my @lines = split( /\n/, $$output_ref );
        my $regex = qr/OPatch\sVersion\:/;
        my $version;

        foreach my $line (@lines) {

            if ( $line =~ $regex ) {

                #OPatch Version: 1.0.0.0.56
                #OPatch Version: 11.2.0.1.7
                #OPatch Version: 11.1.0.9.0
                $version = ( split( ' ', $line ) )[2];
                last;
            }

        }

        return ( split( /\./, $version ) )[0];
    }
}

# executes opatch
# expects as parameters:
# - the application Oracle Home
# - the reference to the XML IO::File object
# returns a reference of applications found and a integer as number of errors
sub exec_opatch {
    my $oracle_home = untaint_path(shift);
    my $xml         = shift;

    # there are several other applications depending on this env variable
    $ENV{ORACLE_HOME} = $oracle_home;
    $xml->comment("Using '$oracle_home' as ORACLE_HOME environment variable");
    my $opatch = File::Spec->catfile( $oracle_home, 'OPatch', 'opatch' );

    unless ( -e $opatch ) {
        $xml->comment("'$opatch' program does not exist");
    }

    unless ( -x $opatch ) {
        $xml->comment("'$opatch' program is not executable");
    }

    my $version = opatch_version( $opatch, $xml );
    my $products_ref;

    unless ( ( defined($version) ) and ( $version =~ /^\d+$/ ) ) {

  # for some reason the version of opatch could not be checked, so it's an error
        if ( defined($version) ) {
            $xml->comment("opatch version '$version' is invalid");
        }
        else {
            $xml->comment('opatch version is unknown');
        }
        return [], 1;
    }
    else {
        my @args;
        if ( $version >= 11 ) {
            @args = (
                'lsinventory', '-local',
                '-invPtrLoc', File::Spec->catfile( $oracle_home, 'oraInst.loc' )
            );
        }
        else {
            @args = (
                'lsinventory', '-invPtrLoc',
                File::Spec->catfile( $oracle_home, 'oraInst.loc' )
            );
        }

        my ( $output_ref, $err_ref, $opatch_errors ) =
          capture_opatch( $opatch, \@args );

        if ( $opatch_errors == 0 ) {

            if ( $version == 1 ) {
                $xml->comment(
'opatch version 1 does not return the application name and version, only patches applied'
                );
            }

            $products_ref = output_2_xml(
                {
                    output => $output_ref,
                    xml    => $xml,
                    before => (
                        "opatch version is $version, executing $opatch "
                          . join( ' ', @args )
                    ),
                    location => $oracle_home
                }
            );
        }
        else {
            $products_ref = output_2_xml(
                {
                    output => $output_ref,
                    xml    => $xml,
                    before => (
                        "opatch version is $version, executing $opatch "
                          . join( ' ', @args )
                    ),
                    after => ( 'opatch failed with error "' . $$err_ref . '"' ),
                    location => $oracle_home
                }
            );
        }
    }

    return $products_ref, $opatch_errors;
}

sub find_product {
    my ( $output_ref, $xml, $location ) = @_;
    my @lines = split( /\n/, $$output_ref );
    my ( @products, %products );

    unless ( scalar(@lines) > 0 ) {
        $xml->comment('Invalid opatch output received');
        return \@products;
    }

    my $bullshit       = 1;
    my $total_products = 0;
    my $no_apps        = 0;
    my $last_app;

    foreach my $line (@lines) {

        next if ( $line eq '' );
        next if ( $line =~ /^\-/ );

        #Installed Top-level Products (1):
        if ( $line =~ /^Installed\sTop-level\sProducts\s\((\d+)\)/ ) {
            $total_products = $1;
            $bullshit       = 0;
            next;
        }

        next if ($bullshit);

        #There are 2 product(s) installed in this Oracle Home.
        if ( $line =~
            /There\sare\s\d+\sproduct.*installed\sin\sthis\sOracle\sHome\./ )
        {
            $no_apps = 1;
        }

        unless ($no_apps) {
            my ( $product, $version ) = split( /\s{2,}/, $line );
            $products{$product} = Oracle::EnvReview::Application->new(
                {
                    name    => $product,
                    version => $version,
                    patches => [],
                    home    => $location
                }
            );
            $last_app = $product;
        }
        else {

            if ( $line =~ /^Patch/ ) {

                # Patch  13324848     : applied on Fri May 01 07:39:14 CDT 2015
                my $number = ( split( ':', $line ) )[0];
                $number =~ s/Patch\s+//;
                $number =~ s/\s+$//;

                # to avoid the word "description" as a patch number
                next unless ( $number =~ /^\d+$/ );
                $products{$last_app}->add_patch($number);
            }

        }

    }
    my $found_prods = scalar( keys(%products) );
    $xml->comment(
        "Could not find all products (found $found_prods of $total_products)")
      unless ( $found_prods == $total_products );
    @products = values(%products);
    return \@products;
}

sub find_locations {
    my $inventory_file = untaint_path(shift);

    # to avoid repeating values
    my %locations;
    my $xml = XML::LibXML->new->load_xml( location => $inventory_file );
    my $xc  = XML::LibXML::XPathContext->new($xml);
    my @nodes =
      $xc->findnodes('/INVENTORY/HOME_LIST/HOME/REFHOMELIST/REFHOME/@LOC');
    push( @nodes, $xc->findnodes('/INVENTORY/HOME_LIST/HOME/@LOC') );

    foreach my $node (@nodes) {
        if ( $node->nodeType eq XML_ATTRIBUTE_NODE ) {
            my $location = untaint_path( $node->getValue() );

            # might contain spaces
            $locations{qq{$location}} = undef;
        }
        else {
            confess "Don't know what to do with node type " . $node->nodeType;
        }
    }
    my @locations = ( keys(%locations) );
    return \@locations;
}

sub get_inventory {
    my $file = shift;
    open( my $in, '<', $file ) or confess "Cannot read $file $!";
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

# generated with find2perl
sub wanted {
    my ( $dev, $ino, $mode, $nlink, $uid, $gid );

    try {
        $name = untaint_path($name);
    }
    catch {
        warn $_;
        return 0;
    };

    ( ( $dev, $ino, $mode, $nlink, $uid, $gid ) = lstat($_) )
      && $File::Find::name =~ /^.*\/\.zfs\z/s
      && ( $File::Find::prune = 1 )
      || /^oraInst\.loc\z/s && push( @list, $name );
}

sub save_cache {
    my $cache_file = shift;
    my $prev_prods = shift;

    if (    ( ref($prev_prods) eq 'HASH' )
        and ( scalar( keys( %{$prev_prods} ) ) > 0 ) )
    {
        print 'Saving cache: ', Dumper($prev_prods), "\n";
    }
    else {
# explicit indicates that there is nothing in for the current in terms of applications installed
        print "Nothing found, explicit indicating that on the cache\n";
        $prev_prods->{NONE} = [ Oracle::EnvReview::Application::None->new() ];
    }

    umask(000);
    nstore( $prev_prods, $cache_file );
}

sub add_apps {
    my ( $prod_cache, $loc, $apps_ref ) = @_;

    if ( exists( $prod_cache->{$loc} ) ) {
        $prod_cache->{$loc} = $apps_ref;
    }
    else {
        warn "'$loc' does not exists in the product cache";
    }
}

# manages Opatch product cache
sub manage_cache {
    my ( $cache_file, $limit ) = @_;

    # convert the days to seconds
    my $limit_secs = $limit * 3600 * 24;
    my $now        = DateTime->now();

    if ( -e $cache_file ) {
        my $last_mod =
          DateTime->from_epoch( epoch => ( stat($cache_file) )[9] );
        my $delta = $now->subtract_datetime_absolute($last_mod);

        if ( $delta->seconds() > $limit_secs ) {
            print "Product cache $cache_file is stale, removing it\n";
            unlink $cache_file or confess "Could not remove $cache_file: $!\n";
            return {};
        }
        else {
            print "Cache is still valid, using it\n";
            return retrieve($cache_file);
        }

    }
    else {
        print
"File $cache_file is not available, will create one at the end of processing\n";
        return {};
    }
}

sub is_none {

    # hash ref
    my $prod_cache = shift;

    if (    ( exists( $prod_cache->{NONE} ) )
        and ( scalar( keys( %{$prod_cache} ) ) == 1 ) )
    {
        print
"Explicit found cache telling there is no application here, skipping this user entirely\n";
        return 1;
    }
    else {
        return 0;
    }
}
