BEGIN { $| = 1; print "1..2\n"; }

use Business::OnlinePayment;

my $tx = new Business::OnlinePayment("LinkPoint",
  'storename' => '000000',
  'keyfile'   => '/path/to/cert.pem',
  'lbin'      => '/path/to/lbin',
  'tmp'       => '/path/to/secure/tempdir',
);

$tx->content(
    type           => 'VISA',
    action         => 'Normal Authorization',
    description    => 'Business::OnlinePayment::LinkPoint visa test',
    amount         => '0.01',
    first_name     => 'Tofu',
    last_name      => 'Beast',
    address        => '123 Anystreet',
    city           => 'Anywhere',
    state          => 'UT',
    zip            => '84058',
    country        => 'US',
    email          => 'ivan-linkpoint@420.am',
    card_number    => '4007000000027',
    expiration     => '12/2002',
    result         => 'DECLINE',
);

$tx->test_transaction(1);

$tx->submit();

if($tx->is_success()) {
    print "not ok 1\n";
    $auth = $tx->authorization;
    warn "********* $auth ***********\n";
} else {
    print "ok 1\n";
    warn '***** '. $tx->error_message. " *****\n";
    exit;
}

