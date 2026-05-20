#!/usr/bin/env perl
# ============================================================================
# t/unit/port_scanner_internals.t — Unit tests for PortScanner internals
# Tests _parse_range, _service_map, and scan mode
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use_ok('PerlDen::Scripts::PortScanner');

# ---------------------------------------------------------------------------
# _parse_range tests
# ---------------------------------------------------------------------------

subtest 'parse valid range' => sub {
    my ($start, $end) = PerlDen::Scripts::PortScanner::_parse_range('1-1024');
    is($start, 1, 'start is 1');
    is($end, 1024, 'end is 1024');
};

subtest 'parse custom range' => sub {
    my ($start, $end) = PerlDen::Scripts::PortScanner::_parse_range('8000-9000');
    is($start, 8000, 'start is 8000');
    is($end, 9000, 'end is 9000');
};

subtest 'parse single port range' => sub {
    my ($start, $end) = PerlDen::Scripts::PortScanner::_parse_range('80-80');
    is($start, 80, 'start is 80');
    is($end, 80, 'end is 80');
};

subtest 'parse invalid range falls back to default' => sub {
    my ($start, $end) = PerlDen::Scripts::PortScanner::_parse_range('garbage');
    is($start, 1, 'default start is 1');
    is($end, 1024, 'default end is 1024');
};

subtest 'parse empty string falls back to default' => sub {
    my ($start, $end) = PerlDen::Scripts::PortScanner::_parse_range('');
    is($start, 1, 'default start is 1');
    is($end, 1024, 'default end is 1024');
};

# ---------------------------------------------------------------------------
# _service_map tests
# ---------------------------------------------------------------------------

subtest 'service map covers well-known ports' => sub {
    my $map = PerlDen::Scripts::PortScanner::_service_map();
    ok(ref $map eq 'HASH', 'returns hashref');

    is($map->{21}, 'FTP', 'port 21 = FTP');
    is($map->{22}, 'SSH', 'port 22 = SSH');
    is($map->{25}, 'SMTP', 'port 25 = SMTP');
    is($map->{53}, 'DNS', 'port 53 = DNS');
    is($map->{80}, 'HTTP', 'port 80 = HTTP');
    is($map->{443}, 'HTTPS', 'port 443 = HTTPS');
    is($map->{3306}, 'MySQL', 'port 3306 = MySQL');
    is($map->{5432}, 'PostgreSQL', 'port 5432 = PostgreSQL');
    is($map->{6379}, 'Redis', 'port 6379 = Redis');
    is($map->{27017}, 'MongoDB', 'port 27017 = MongoDB');
};

subtest 'service map has no undef values' => sub {
    my $map = PerlDen::Scripts::PortScanner::_service_map();
    for my $port (keys %$map) {
        ok(defined $map->{$port}, "port $port has defined service name");
        ok(length($map->{$port}) > 0, "port $port has non-empty service name");
    }
};

# ---------------------------------------------------------------------------
# scan mode (localhost, tiny range)
# ---------------------------------------------------------------------------

subtest 'scan mode returns structure' => sub {
    my $result = PerlDen::Scripts::PortScanner::run(
        mode       => 'scan',
        host       => '127.0.0.1',
        port_range => '1-5',
        timeout    => 0.2,
    );
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{scan}, 'has scan results');
    is($result->{scan}{host}, '127.0.0.1', 'scan host correct');
    is($result->{scan}{start}, 1, 'scan start correct');
    is($result->{scan}{end}, 5, 'scan end correct');
    ok(ref $result->{scan}{open} eq 'ARRAY', 'open ports is array');
};

# ---------------------------------------------------------------------------
# listen mode structure
# ---------------------------------------------------------------------------

subtest 'listen mode returns arrays' => sub {
    my $result = PerlDen::Scripts::PortScanner::run(mode => 'listen');
    ok(ref $result->{listening} eq 'ARRAY', 'listening is array');
    ok(ref $result->{established} eq 'ARRAY', 'established is array');
    ok(ref $result->{service_map} eq 'HASH', 'service_map is hash');

    # Verify listening entry structure (if any ports are listening)
    if (@{$result->{listening}}) {
        my $first = $result->{listening}[0];
        ok(exists $first->{proto}, 'entry has proto');
        ok(exists $first->{state}, 'entry has state');
        ok(exists $first->{local}, 'entry has local');
    }
};

# ---------------------------------------------------------------------------
# format_report
# ---------------------------------------------------------------------------

subtest 'format_report for listen mode' => sub {
    my $result = PerlDen::Scripts::PortScanner::run(mode => 'listen');
    my $report = PerlDen::Scripts::PortScanner::format_report($result);
    ok(length($report) > 100, 'report has content');
    like($report, qr/PORT.*CONNECTION/i, 'has header');
    like($report, qr/Listening Ports/, 'has listening section');
    like($report, qr/Established Connections/, 'has established section');
};

subtest 'format_report for scan mode' => sub {
    my $result = PerlDen::Scripts::PortScanner::run(
        mode       => 'scan',
        host       => '127.0.0.1',
        port_range => '1-5',
        timeout    => 0.2,
    );
    my $report = PerlDen::Scripts::PortScanner::format_report($result);
    like($report, qr/Port Scan Results/, 'has scan results section');
    like($report, qr/127\.0\.0\.1/, 'shows scan host');
};

done_testing();
