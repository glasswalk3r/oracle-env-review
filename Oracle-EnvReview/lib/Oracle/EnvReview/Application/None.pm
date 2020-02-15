package Oracle::EnvReview::Application::None;
use warnings;
use strict;
use parent 'Oracle::EnvReview::Application';

# VERSION
# to be used in cache, explicit tells that there is no application over there
sub new {
    my $class   = shift;
    my %attribs = (
        name    => 'none',
        version => 'N/A',
        home    => 'N/A',
        patches => []
    );
    return $class->SUPER::new( \%attribs );
}

1;
