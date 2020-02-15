package Oracle::EnvReview::Remote::Application::Weblogic;
use warnings;
use strict;
use parent
  qw(Oracle::EnvReview::Application::Weblogic Oracle::EnvReview::Remote::Application);

# VERSION

sub new {
    my ( $class, $xml_node ) = @_;
    my $attribs_ref = $class->_get_basic($xml_node);
    $attribs_ref->{psu} = $xml_node->findvalue('psu');
    return $class->SUPER::new($attribs_ref);
}

1;
