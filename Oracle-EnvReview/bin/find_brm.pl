#!/ood_repository/environment_review/perl -T
use warnings;
use strict;
use Oracle::EnvReview::VersionFinder qw(check_version check_args);
use Oracle::EnvReview::Application::BRM 0.001;
use File::Spec;

# VERSION
my ( $cmd, $home, $fifo ) = check_args( $VERSION, 'pinrev', 'BRM' );

#no need to set ORACLE_HOME for pinrev

check_version(
    $cmd, undef, $fifo,

    # :WARNING:07/08/2015 08:23:07 PM:: this parser will not work properly if
    # PRODUCT_NAME is not followed by other keys until the next product
    sub {
        my $output_ref = shift;
        my @lines      = split( /\n/, $$output_ref );
        my %data;
        my $last_product;

        my $comment = qr/^\=+/;

        foreach my $line (@lines) {
            next if ( ( $line eq '' ) or ( $line =~ $comment ) );
            my ( $key, $value ) = split( '=', $line );
            $value =~ s/^\s+//;
            $value =~ s/\s+$//;

            if ( $key eq 'PRODUCT_NAME' ) {

                # sane setting
                $last_product = undef;

                if ( exists( $data{$key} ) ) {
                    warn "invalid line '$line', $key already exists!";
                }
                else {
                    $data{$value} = {
                        name           => $value,
                        version        => undef,
                        build_time     => undef,
                        installed_time => undef
                    };
                    $last_product = $value;
                }
                next;

            }

            if (   ( $key eq 'VERSION' )
                or ( $key eq 'BUILD_TIME' )
                or ( $key eq 'INSTALLED_TIME' ) )
            {

                if ( exists( $data{$last_product} ) ) {
                    my $lc_key = lc($key);
                    $data{$last_product}->{$lc_key} = $value;
                }
                else {
                    warn "invalid line '$line', $last_product do no exists";
                    next;
                }

                next;

            }

            if ( $key eq 'COMPONENTS' ) {

                if ( exists( $data{$last_product} ) ) {
                    $value =~ s/^\s+//;
                    $value =~
                      s/\,+$//;    #removing empty commas to avoid undef values
                    $value =~ tr/"//d;
                    my @items = split( ',', $value );
                    $data{$last_product}->{components} = \@items;
                }
                else {
                    warn "invalid line '$line', $last_product do no exists";
                    next;
                }

                next;

            }

        }

        my @apps;
        foreach my $app ( keys(%data) ) {
            push(
                @apps,
                Oracle::EnvReview::Application::BRM->new(
                    {
                        name           => $data{$app}->{name},
                        version        => $data{$app}->{version},
                        build_time     => $data{$app}->{build_time},
                        installed_time => $data{$app}->{installed_time},
                        components     => $data{$app}->{components},
                        patches        => []
                    }
                )
            );
        }
        return \@apps;

    }

);
