package Oracle::EnvReview::XMLConverter;
use warnings;
use strict;
use Exporter qw(import);
use Carp;
use Scalar::Util qw(blessed);
use Data::Dumper;
use Oracle::EnvReview::Application 0.001;
use Oracle::EnvReview::Application::Exception;
use Oracle::EnvReview::Application::Weblogic 0.001;
use Oracle::EnvReview::Application::BRM 0.001;
use Oracle::EnvReview::Application::EBSO 0.001;
use Oracle::EnvReview::Application::None;
use Oracle::EnvReview::Application::Siebel 0.001;
use Oracle::EnvReview::Application::OHS 0.001;

# VERSION
our @EXPORT_OK = qw(app_2_xml);

sub app_2_xml {
    my ( $xml, $apps_ref ) = @_;
    confess "first parameter must be a valid XML::Writer object"
      unless ( ( defined($xml) ) and ( $xml->isa('XML::Writer') ) );
    confess "application parameter must be an array reference"
      unless ( ( defined($apps_ref) ) and ( ref($apps_ref) eq 'ARRAY' ) );
    my $name_with_spaces = qr/\s+/;

    # validation
    foreach my $app ( @{$apps_ref} ) {
        confess( 'application ' . Dumper($app) . ' is an invalid input' )
          unless ( ( defined( blessed($app) ) )
            and ( $app->isa('Oracle::EnvReview::Application') ) );
    }

    foreach my $app ( @{$apps_ref} ) {
        if ( $app->isa('Oracle::EnvReview::Application::Exception') ) {
            $xml->comment( $app->get_error_msg );
            next;
        }
        if ( $app->isa('Oracle::EnvReview::Application::None') ) {
            next;    # no need to put anything
        }
        else {
            my $app_ref = $app->get_scalars;
            $xml->startTag('application');

            foreach my $attrib_name ( keys( %{$app_ref} ) ) {
                $xml->dataElement( $attrib_name, $app_ref->{$attrib_name} );
            }

            foreach my $attrib ( $app->get_lists ) {
                my $method = "get_$attrib";

               # remove "plural" of XML entity to create individual child entity
                my $item_name = $attrib;
                $item_name =~ s/e?s$//;
                $xml->startTag( $attrib, 'type' => 'list' );

# :TODO:07/08/2015 09:07:56 PM:: this kind of "protocol" should be better documented
                foreach my $item_value ( $app->$method ) {
                    $xml->dataElement( $item_name, $item_value );
                }

                $xml->endTag($attrib);
            }

            $xml->endTag('application');
        }
    }
}

1;
