package Business::OnlinePayment::LinkPoint;

# $Id: LinkPoint.pm,v 1.6 2002/08/14 01:32:54 ivan Exp $

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Carp qw(croak);
use AutoLoader;
use Business::OnlinePayment;

use lperl; #lperl.pm from Linkpoint.

require Exporter;

@ISA = qw(Exporter AutoLoader Business::OnlinePayment);
@EXPORT = qw();
@EXPORT_OK = qw();
$VERSION = '0.02';

sub set_defaults {
    my $self = shift;

    #$self->server('staging.linkpt.net');
    $self->server('secure.linkpt.net');
    $self->port('1139');

}

sub map_fields {
    my($self) = @_;

    my %content = $self->content();

    #ACTION MAP
    my %actions = ('normal authorization' => 'ApproveSale',
                   'authorization only'   => 'CapturePayment',
                   'credit'               => 'ReturnOrder',
                   'post authorization'   => 'BillOrders',
                  );
    $content{'action'} = $actions{lc($content{'action'})} || $content{'action'};

    # stuff it back into %content
    $self->content(%content);
}

sub build_subs {
    my $self = shift;
    foreach(@_) {
        #no warnings; #not 5.005
        local($^W)=0;
        eval "sub $_ { my \$self = shift; if(\@_) { \$self->{$_} = shift; } return \$self->{$_}; }";
    }
}

sub remap_fields {
    my($self,%map) = @_;

    my %content = $self->content();
    foreach(keys %map) {
        $content{$map{$_}} = $content{$_};
    }
    $self->content(%content);
}

sub revmap_fields {
    my($self, %map) = @_;
    my %content = $self->content();
    foreach(keys %map) {
#    warn "$_ = ". ( ref($map{$_})
#                         ? ${ $map{$_} }
#                         : $content{$map{$_}} ). "\n";
        $content{$_} = ref($map{$_})
                         ? ${ $map{$_} }
                         : $content{$map{$_}};
    }
    $self->content(%content);
}

sub get_fields {
    my($self,@fields) = @_;

    my %content = $self->content();
    my %new = ();
    foreach( grep defined $content{$_}, @fields) { $new{$_} = $content{$_}; }
    return %new;
}

sub submit {
    my($self) = @_;


    $self->map_fields();

    my %content = $self->content;

    my($month, $year);
    unless ( $content{action} eq 'BillOrders' ) {

        if (  $self->transaction_type() =~
                /^(cc|visa|mastercard|american express|discover)$/i
           ) {
        } else {
            Carp::croak("LinkPoint can't handle transaction type: ".
                        $self->transaction_type());
        }

      $content{'expiration'} =~ /^(\d+)\D+\d*(\d{2})$/
        or croak "unparsable expiration $content{expiration}";

      ( $month, $year ) = ( $1, $2 );
      $month = '0'. $month if $month =~ /^\d$/;
      $year += 2000 if $year < 2000; #not y4k safe, oh shit
    }

    $content{'address'} =~ /^(\S+)\s/;
    my $addrnum = $1;

    $self->server('staging.linkpt.net') if $self->test_transaction;

    $self->revmap_fields(
      hostname     => \( $self->server ),
      port         => \( $self->port ),
      storename    => \( $self->storename ),
      keyfile      => \( $self->keyfile ),
      addrnum      => \$addrnum,

      cardNumber   => 'card_number',
      cardExpMonth => \$month,
      cardExpYear  => \$year,
    );

    my $lperl = new LPERL
      $self->lbin,
      'FILE',
      $self->can('tmp')
        ? $self->tmp
        : '/tmp';
    my $action = $content{action};

    $self->required_fields(qw/
      hostname port storename keyfile amount cardNumber cardExpMonth cardExpYear
    /);

    my %post_data = $self->get_fields(qw/
      hostname port storename keyfile
      result
      amount cardNumber cardExpMonth cardExpYear
      name email phone address city state zip country
    /);

    #print "$_ => $post_data{$_}\n" foreach keys %post_data;

    my %response;
    {
      local($^W)=0;
      %response = $lperl->$action(\%post_data);
    }

    if ( $response{'statusCode'} == 0 ) {
      $self->is_success(0);
      $self->result_code('');
      $self->error_message($response{'statusMessage'});
    } else {
      $self->is_success(1);
      $self->result_code($response{'AVCCode'});
      $self->authorization($response{'trackingID'});
#      $self->order_number($response{'neworderID'});
    }

}

1;
__END__

=head1 NAME

Business::OnlinePayment::LinkPoint - LinkPoint backend for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment;

  my $tx = new Business::OnlinePayment( 'LinkPoint',
    'storename' => 'your_store_number',
    'keyfile'   => '/path/to/keyfile.pem',
    'lbin'      => '/path/to/binary/lbin',
    'tmp'       => '/secure/tmp',          # a secure tmp directory
  );

  $tx->content(
      type           => 'VISA',
      action         => 'Normal Authorization',
      description    => 'Business::OnlinePayment test',
      amount         => '49.95',
      invoice_number => '100100',
      customer_id    => 'jsk',
      name           => 'Jason Kohles',
      address        => '123 Anystreet',
      city           => 'Anywhere',
      state          => 'UT',
      zip            => '84058',
      email          => 'ivan-linkpoint@420.am',
      card_number    => '4007000000027',
      expiration     => '09/99',
  );
  $tx->submit();

  if($tx->is_success()) {
      print "Card processed successfully: ".$tx->authorization."\n";
  } else {
      print "Card was rejected: ".$tx->error_message."\n";
  }

=head1 SUPPORTED TRANSACTION TYPES

=head2 Visa, MasterCard, American Express, JCB, Discover/Novus, Carte blanche/Diners Club

=head1 DESCRIPTION

For detailed information see L<Business::OnlinePayment>.

=head1 COMPATIBILITY

This module implements an interface to the LinkPoint Perl Wrapper
http://www.linkpoint.com/product_solutions/internet/lperl/lperl_main.html

=head1 BUGS

=head1 AUTHOR

Ivan Kohler <ivan-linkpoint@420.am>

Based on Busienss::OnlinePayment::AuthorizeNet written by Jason Kohles.

=head1 SEE ALSO

perl(1), L<Business::OnlinePayment>.

=cut

