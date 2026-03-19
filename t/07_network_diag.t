#!/usr/bin/env perl
# ============================================================================
# t/07_network_diag.t — Test HBPerl::Scripts::NetworkDiag
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('HBPerl::Scripts::NetworkDiag');

subtest 'run returns network data' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::run(
        ping_host => '127.0.0.1',
        dns_host  => 'localhost',
    );
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{interfaces}, 'has interfaces');
    ok(ref $result->{interfaces} eq 'ARRAY', 'interfaces is array');
    ok(exists $result->{routes}, 'has routes');
    ok(exists $result->{dns_servers}, 'has dns_servers');
};

subtest 'localhost ping should succeed' => sub {
    my $r = HBPerl::Scripts::NetworkDiag::run(ping_host => '127.0.0.1');
    ok($r->{ping}, 'ping result exists');
    ok($r->{ping}{success}, 'localhost ping succeeded');
};

subtest 'format_report works' => sub {
    my $r = HBPerl::Scripts::NetworkDiag::run(ping_host => '127.0.0.1');
    my $report = HBPerl::Scripts::NetworkDiag::format_report($r);
    ok(length($report) > 50, 'report has content');
    like($report, qr/NETWORK/i, 'report has network header');
};

done_testing();
