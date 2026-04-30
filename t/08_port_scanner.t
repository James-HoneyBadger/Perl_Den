#!/usr/bin/env perl
# ============================================================================
# t/08_port_scanner.t — Test BadgerOps::Scripts::PortScanner
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('BadgerOps::Scripts::PortScanner');

subtest 'listen mode returns data' => sub {
    my $result = BadgerOps::Scripts::PortScanner::run(mode => 'listen');
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{listening}, 'has listening');
    ok(ref $result->{listening} eq 'ARRAY', 'listening is array');
    ok(exists $result->{established}, 'has established');
    ok(exists $result->{service_map}, 'has service_map');
};

subtest 'service_map has common ports' => sub {
    my $r = BadgerOps::Scripts::PortScanner::run(mode => 'listen');
    my $map = $r->{service_map};
    is($map->{22}, 'SSH', 'port 22 = SSH');
    is($map->{80}, 'HTTP', 'port 80 = HTTP');
    is($map->{443}, 'HTTPS', 'port 443 = HTTPS');
};

subtest 'format_report works' => sub {
    my $r = BadgerOps::Scripts::PortScanner::run(mode => 'listen');
    my $report = BadgerOps::Scripts::PortScanner::format_report($r);
    ok(length($report) > 50, 'report has content');
    like($report, qr/PORT|CONNECTION/i, 'report has relevant header');
};

done_testing();
