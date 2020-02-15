package Oracle::EnvReview::Hints;

use warnings;
use strict;
use Linux::Info::SysInfo 0.9;
use YAML::XS 0.62 'LoadFile';
use Oracle::EnvReview::Hints::Server;
use Exporter 'import';

# VERSION

our @EXPORT_OK = qw(check_hints);

=pod

=head1 NAME

Oracle::EnvReview::Hints - functions to read hints to locate and describe application installed with Universal Installer

=head1 DESCRIPTION

This module provides a function to read a hints file and return a object to handle the details if one exists for that combination of instance/host.

See HINTS for a description of the YAML file expected.

=head1 EXPORTS

The function C<check_hint> will be exported if requested.

=head1 FUNCTIONS

=head2 check_hints

Expects as parameter:

=over

=item 1.

A string with the full path to the hints file.

=item 2.

A string with the instance name (all lowercase).

=back

The function will check if there is an entry for the combination of the instance and the current hostname where this function
is being executed.

If there is such entry, it will create an instance of L<Oracle::EnvReview::Hints::Server> and return it. Otherwise, returns C<undef>.

=cut

sub check_hints {
    my ( $hint_file, $instance ) = @_;
    my $cfg = LoadFile($hint_file);
    my $sys = Linux::Info::SysInfo->new;

    if ( exists( $cfg->{$instance} ) ) {

        if ( exists( $cfg->{$instance}->{ $sys->get_hostname } ) ) {
            return Oracle::EnvReview::Hints::Server->new(
                $cfg->{$instance}->{ $sys->get_hostname } );
        }
        else {
            return;
        }

    }
    else {
        return;
    }

}

=head1 HINTS

The hints file is an optional YAML file that contains declarations used to described how applications should be located and processed.

This file is required only if the particular server configuration does not allow the Universal Installer inventory to be located by standard procedures of
any other issue on the server makes that impossible.

The file should contain one or more entries organized as:

    ---
    instance:
      hostname:
       inventories:
         - full path to inventory file
         - full path to another inventory file
         - full path to another inventory file
       skip_user:
         - userA
         - userB

Where:

=over

=item *

instance is the lowercase string representing the instance name.

=item *

hostname is the server host name, domain not included.

=item *

inventories is a list of inventory files to use. You can include as many different locations as you want. Beware that the string C<inventories> is
an expected reserved word, if you want to specify inventories at all.

=item *

skip_users is an option reserved keyword that you can use to provide a list of users that you don't want to try to locate related applications. For example, you might find
that a particular user is presenting issues when trying to pbrun to it.

You can add as many users as you need to.

Beware that is implicit that you include C<inventories> if you add C<skip_users>, otherwise no application will be searched.

=back

Example:

    ---
    foobar123:
      vmfoobar1:
        inventories:
          - /foobar123/hyperion/oraInventory/ContentsXML/inventory.xml
      vmfoobar2:
        inventories:
          - /foobar123/essbase/oraInventory/ContentsXML/inventory.xml
    foobar321:
      vmfoobar3:
        inventories:
          - /foobar321/fmw/oraInventory/ContentsXML/inventory.xml
    foobar456:
      vmfoobar4:
        inventories:
          - /foobar456/oracle/product/ora11GR2Inventory/ContentsXML/inventory.xml
    foobar890:
      vmfoobar5:
        inventories:
          - /foobar890/hyperion/oraInventory/ContentsXML/inventory.xml
        skip_users:
          -johndoe

=cut

1;
