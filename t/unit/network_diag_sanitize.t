#!/usr/bin/env perl
# ============================================================================
# t/unit/network_diag_sanitize.t — Unit tests for NetworkDiag input validation
# Tests hostname sanitization and _ping_test safety
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use_ok('HBPerl::Scripts::NetworkDiag');

# ---------------------------------------------------------------------------
# _ping_test hostname validation
# ---------------------------------------------------------------------------

subtest 'valid IPv4 address accepted' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('127.0.0.1');
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{success}, 'has success key');
    ok(exists $result->{output}, 'has output key');
    is($result->{host}, '127.0.0.1', 'host preserved');
};

subtest 'valid hostname accepted' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('localhost');
    ok(ref $result eq 'HASH', 'returns hashref');
    is($result->{host}, 'localhost', 'hostname preserved');
};

subtest 'valid FQDN accepted' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('my-host.example.com');
    ok(ref $result eq 'HASH', 'returns hashref');
    is($result->{host}, 'my-host.example.com', 'FQDN preserved');
};

subtest 'command injection via semicolon rejected' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('127.0.0.1; rm -rf /');
    is($result->{success}, 0, 'reports failure');
    like($result->{output}, qr/Invalid hostname/, 'rejects injection attempt');
};

subtest 'command injection via backtick rejected' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('`whoami`');
    is($result->{success}, 0, 'reports failure');
    like($result->{output}, qr/Invalid hostname/, 'rejects backtick injection');
};

subtest 'command injection via $() rejected' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('$(cat /etc/passwd)');
    is($result->{success}, 0, 'reports failure');
    like($result->{output}, qr/Invalid hostname/, 'rejects $() injection');
};

subtest 'command injection via pipe rejected' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('127.0.0.1 | cat /etc/passwd');
    is($result->{success}, 0, 'reports failure');
    like($result->{output}, qr/Invalid hostname/, 'rejects pipe injection');
};

subtest 'command injection via newline rejected' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test("127.0.0.1\nwhoami");
    is($result->{success}, 0, 'reports failure');
    like($result->{output}, qr/Invalid hostname/, 'rejects newline injection');
};

subtest 'empty hostname rejected' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::_ping_test('');
    is($result->{success}, 0, 'reports failure');
    like($result->{output}, qr/Invalid hostname/, 'rejects empty hostname');
};

# ---------------------------------------------------------------------------
# run() structure tests
# ---------------------------------------------------------------------------

subtest 'run returns expected structure' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::run(
        ping_host => '127.0.0.1',
        dns_host  => 'localhost',
    );
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{interfaces}, 'has interfaces');
    ok(exists $result->{routes}, 'has routes');
    ok(exists $result->{dns}, 'has dns');
    ok(exists $result->{dns_servers}, 'has dns_servers');
    ok(exists $result->{ping}, 'has ping');
    ok(exists $result->{gateway}, 'has gateway');
};

subtest 'dns lookup returns structure' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::run(
        dns_host  => 'localhost',
        ping_host => '127.0.0.1',
    );
    ok(ref $result->{dns} eq 'HASH', 'dns is hashref');
    is($result->{dns}{host}, 'localhost', 'dns host matches');
    ok(ref $result->{dns}{addresses} eq 'ARRAY', 'addresses is array');
};

# ---------------------------------------------------------------------------
# format_report
# ---------------------------------------------------------------------------

subtest 'format_report generates valid report' => sub {
    my $result = HBPerl::Scripts::NetworkDiag::run(
        ping_host => '127.0.0.1',
        dns_host  => 'localhost',
    );
    my $report = HBPerl::Scripts::NetworkDiag::format_report($result);
    ok(length($report) > 100, 'report has substantial content');
    like($report, qr/NETWORK DIAGNOSTICS/, 'has header');
    like($report, qr/Network Interfaces/, 'has interfaces section');
    like($report, qr/DNS/, 'has DNS section');
    like($report, qr/Ping Test/, 'has ping section');
};

done_testing();
