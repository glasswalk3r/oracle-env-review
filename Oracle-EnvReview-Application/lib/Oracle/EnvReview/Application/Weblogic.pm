package Oracle::EnvReview::Application::Weblogic;
use warnings;
use strict;
use Set::Tiny;
use Hash::Util qw(lock_keys unlock_keys);
use parent 'Oracle::EnvReview::Application';

# VERSION
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_ro_accessors(
    qw(psu java_version java_arch java_vendor java_vm managed_server));

=pod
WebLogic Server#10.3.6.0#10.3.6.0.161018#13729611:13845626:13964737:17319481:17495356:19259028:19687084:20474010:24608998:${CRS}#oacore_server13#1.7.0_121#64#Oracle Corporation#Java HotSpot(TM) 64-Bit Server VM
WebLogic Server#10.3.6.0#10.3.6.0.161018#13729611:13845626:13964737:17319481:17495356:19259028:19687084:20474010:24608998:${CRS}#forms-c4ws_server4#1.6.0_29#64#Oracle Corporation#Oracle JRockit(R)
WebLogic Server#10.3.6.0#10.3.6.0.161018#13729611:13845626:13964737:17319481:17495356:19259028:19687084:20474010:24608998:${CRS}#oafm_server4#1.6.0_29#64#Oracle Corporation#Oracle JRockit(R)
WebLogic Server#10.3.6.0#10.3.6.0.161018#13729611:13845626:13964737:17319481:17495356:19259028:19687084:20474010:24608998:${CRS}#forms_server10#1.6.0_29#32#Oracle Corporation#Oracle JRockit(R)
=cut

sub new {
    my ( $class, $attribs_ref ) = @_;
    my $self = $class->SUPER::new($attribs_ref);
    unlock_keys( %{$self} );

    foreach my $attrib_name (
        qw(java_version java_arch java_vendor java_vm managed_server))
    {
        $self->{$attrib_name} = $attribs_ref->{$attrib_name};
    }

    if ( exists( $attribs_ref->{psu} ) ) {
        $self->{psu} = $attribs_ref->{psu};
    }

    lock_keys( %{$self} );
    return $self;
}

sub get_bugs {
    my $self = shift;
    return $self->get_patches;
}

sub get_scalars {
    my $self        = shift;
    my $scalars_ref = $self->SUPER::get_scalars;
    foreach my $attrib_name (
        qw(psu java_version java_arch java_vendor java_vm managed_server))
    {
        my $method = "get_$attrib_name";
        $scalars_ref->{$attrib_name} = $self->$method;
    }
    return $scalars_ref;
}

1;
