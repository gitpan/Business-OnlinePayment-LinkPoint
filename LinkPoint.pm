package Business::OnlinePayment::LinkPoint;

# $Id: LinkPoint.pm,v 1.22 2004/06/24 15:32:33 ivan Exp $

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Carp qw(croak);
use AutoLoader;
use Business::OnlinePayment;

require Exporter;

@ISA = qw(Exporter AutoLoader Business::OnlinePayment);
@EXPORT = qw();
@EXPORT_OK = qw();
$VERSION = '0.04';

use lpperl; #3;  #lperl.pm from LinkPoint
$LPPERL::VERSION =~ /^(\d+\.\d+)/
  or die "can't parse lperl.pm version: $LPPERL::VERSION";
die "lpperl.pm minimum version 3 required\n" unless $1 >= 3;

sub set_defaults {
    my $self = shift;

    #$self->server('staging.linkpt.net');
    $self->server('secure.linkpt.net');
    $self->port('1129');

    $self->build_subs(qw(order_number avs_code));

}

sub map_fields {
    my($self) = @_;

    my %content = $self->content();

    #ACTION MAP
    my %actions = ('normal authorization' => 'SALE',
                   'authorization only'   => 'PREAUTH',
                   'credit'               => 'CREDIT',
                   'post authorization'   => 'POSTAUTH',
                   'void'                 => 'VOID',
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
    unless ( $content{action} eq 'POSTAUTH' ) {

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
    }

    $content{'address'} =~ /^(\S+)\s/;
    my $addrnum = $1;

    my $result = $content{'result'};
    if ( $self->test_transaction) {
      $result ||= 'GOOD';
      #$self->server('staging.linkpt.net');
    } else {
      $result ||= 'LIVE';
    }

    $self->revmap_fields(
      host         => \( $self->server ),
      port         => \( $self->port ),
      #storename    => \( $self->storename ),
      configfile   => \( $self->storename ),
      keyfile      => \( $self->keyfile ),
      addrnum      => \$addrnum,
      result       => \$result,
      cardnumber   => 'card_number',
      cardexpmonth => \$month,
      cardexpyear  => \$year,
      chargetotal  => 'amount',
    );

    my $lperl = new LPPERL;

    $self->required_fields(qw/
      host port configfile keyfile amount cardnumber cardexpmonth cardexpyear
    /);

    my %post_data = $self->get_fields(qw/
      host port configfile keyfile
      result
      chargetotal cardnumber cardexpmonth cardexpyear
      name email phone addrnum city state zip country
    /);

    $post_data{'ordertype'} = $content{action};

    if ( $content{'cvv2'} ) { 
      $post_data{cvmindicator} = 'provided';
      $post_data{cvmvalue} = $content{'cvv2'};
    }

    warn "$_ => $post_data{$_}\n" foreach keys %post_data;

    my %response;
    #{
    #  local($^W)=0;
    #  %response = $lperl->$action(\%post_data);
    #}
    %response = $lperl->curl_process(\%post_data);

    warn "$_ => $response{$_}\n" for keys %response;

    if ( $response{'r_approved'} eq 'APPROVED' ) {
      $self->is_success(1);
      $self->result_code($response{'r_code'});
      $self->authorization($response{'r_ref'});
      $self->order_number($response{'r_ordernum'});
      $self->avs_code($response{'r_avs'});
    } else {
      $self->is_success(0);
      $self->result_code('');
      $self->error_message($response{'r_error'});
    }

}

1;
__END__

=head1 NAME

Business::OnlinePayment::LinkPoint - LinkPoint (Cardservice) backend for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment;

  my $tx = new Business::OnlinePayment( 'LinkPoint',
    'storename' => 'your_store_number',
    'keyfile'   => '/path/to/keyfile.pem',
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

Version 0.4 of this module has been updated for the LinkPoint Perl Wrapper
version 3.5.

=head1 BUGS

=head1 AUTHOR

Ivan Kohler <ivan-linkpoint@420.am>

Based on Busienss::OnlinePayment::AuthorizeNet written by Jason Kohles.

=head1 SEE ALSO

perl(1), L<Business::OnlinePayment>.

=cut

