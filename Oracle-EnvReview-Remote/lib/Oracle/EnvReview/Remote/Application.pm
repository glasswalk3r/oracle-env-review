package Oracle::EnvReview::Remote::Application;
use warnings;
use strict;
use Scalar::Util 'blessed';
use XML::LibXML 2.0124;
use Carp;
use parent qw(Oracle::EnvReview::Application);

# VERSION

sub _get_basic {
    my ( $class, $xml_node ) = @_;
    my $check = blessed($xml_node);
    confess 'must receive as parameter a XML::LibXML::Element'
      unless ( ( defined($check) ) and ( $check eq 'XML::LibXML::Element' ) );
    my @patches;

    foreach my $patch ( $xml_node->findnodes('patches/patch') ) {
        push( @patches, $patch->textContent );
    }

    my %attribs = (
        name    => $xml_node->findvalue('name'),
        version => $xml_node->findvalue('version'),
        patches => \@patches
    );

    return \%attribs;
}

sub new {
    my ( $class, $xml_node ) = @_;
    my $attribs_ref = $class->_get_basic($xml_node);
    return $class->SUPER::new($attribs_ref);
}

sub to_mongodb {
    my $self = shift;
    my $copy = { %{$self} };
    delete( $copy->{_patches} );
    $copy->{patches} = [ $self->get_patches ];
    return $copy;
}
