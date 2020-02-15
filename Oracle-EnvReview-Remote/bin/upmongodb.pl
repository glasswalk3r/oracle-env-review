use warnings;
use strict;
use XML::LibXML 2.0124;
use File::Spec;
use Getopt::Std;
use Cwd;
use feature 'say';
use JSON::Syck 1.29;
use MongoDB 1.4.2;
use MongoDB::OID 1.4.2;
use Encode;
use YAML::XS 0.62 qw(LoadFile);
use Oracle::EnvReview::Remote::Application;
use Oracle::EnvReview::Remote::Application::OHS;
use Oracle::EnvReview::Remote::Application::Weblogic;

# VERSION
my %opts;
getopts( 'c:', \%opts );
my $config_file;

if ( ( exists( $opts{c} ) ) and ( defined( $opts{c} ) ) and ( -e $opts{c} ) ) {
    $config_file = $opts{c};
}
else {
    $config_file = 'config.yml';
}

my ( $collection_name, $map_ref ) = read_config($config_file);

my $client     = MongoDB::MongoClient->new();
my $mongodb    = $client->get_database('customer');
my $collection = $mongodb->get_collection($collection_name);
my $xml_dir    = File::Spec->catdir( getcwd(), 'tmp' );
my $parser     = XML::LibXML->new();
opendir( DIR, $xml_dir ) or die "Cannot read dir $xml_dir: $!";
my $file_regex = qr/\.xml$/;

while ( my $file = readdir(DIR) ) {
    next unless $file =~ $file_regex;
    my ( $instance, $hostname ) = split( '_', $file );
    my %data;
    my $doc =
      $parser->load_xml( location => File::Spec->catfile( $xml_dir, $file ) );
    $data{server} = {};

    # a document key is $name and $instance
    $data{server}->{name}     = $doc->findvalue('/server/name');
    $data{server}->{instance} = $instance;
    $data{server}->{virtualCPUCount} =
      $doc->findvalue('/server/virtualCPUCount') +
      0;    # force numeric conversion to JSON
    $data{server}->{osBitVersion} = $doc->findvalue('/server/osBitVersion');
    $data{server}->{osSummary}    = $doc->findvalue('/server/osSummary');
    $data{server}->{osVersion}    = $doc->findvalue('/server/osVersion');
    $data{server}->{osLevel}      = $doc->findvalue('/server/osLevel');
    $data{server}->{applications} = [];

    foreach
      my $app_element ( $doc->findnodes('/server/applications/application') )
    {
        my $app;
        if ( exists( $map_ref->{ $app_element->findvalue('name') } ) ) {
            my $class = $map_ref->{ $app_element->findvalue('name') };
            $app = $class->new($app_element);
        }
        else {
            $app = Oracle::EnvReview::Remote::Application->new($app_element);
        }

        push( @{ $data{server}->{applications} }, $app->to_mongodb );
    }

# TODO: must merge info
# first from the source (XML), applications may have name variations (build a dictionary for that)
# second compare with the adata available on MongoDB: if they app is on MongoDB and not in the source, preserve MongoDB
# otherwise, update on MongoDB directly
    $collection->update(
        {
            "server.name"     => $data{server}->{name},
            "server.instance" => $data{server}->{instance}
        },
        \%data,
        { upsert => 1 }
    );
    say "upsert of "
      . $data{server}->{name} . " in "
      . $data{server}->{instance};

    #say JSON::Syck::Dump(\%data);

}

close(DIR);

sub read_config {
    my $yaml       = LoadFile(shift);
    my $collection = $yaml->{customer};
    $collection =~ tr/ /_/;
    return $collection, $yaml->{mapping};
}
