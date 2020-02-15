package Oracle::EnvReview::Remote::Application::OHS;
use warnings;
use strict;
use parent
  qw(Oracle::EnvReview::Application::OHS Oracle::EnvReview::Remote::Application);

# VERSION

sub new {
    my ( $class, $xml_node ) = @_;
    my $attribs_ref = $class->_get_basic($xml_node);

    foreach my $attrib (qw(alias apache_version)) {
        $attribs_ref->{$attrib} = $xml_node->findvalue($attrib);
    }

    return $class->SUPER::new($attribs_ref);
}

1;
