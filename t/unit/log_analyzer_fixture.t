#!/usr/bin/env perl
# ============================================================================
# t/unit/log_analyzer_fixture.t — Fixture-based LogAnalyzer tests
# Uses t/fixtures/syslog.sample to test parsing against realistic syslog data
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use_ok('HBPerl::Scripts::LogAnalyzer');

my $fixture = "$FindBin::Bin/../fixtures/syslog.sample";
plan skip_all => 'syslog.sample fixture not found' unless -f $fixture;

subtest 'parse fixture syslog' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $fixture,
        max_lines => 100,
    );
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(!$result->{error}, 'no error');
    is($result->{total_entries}, 10, 'parsed all 10 fixture lines');
    ok(ref $result->{entries} eq 'ARRAY', 'entries is array');
};

subtest 'source_count tracks services' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $fixture,
        max_lines => 100,
    );
    my $src = $result->{source_count};
    ok(ref $src eq 'HASH', 'source_count is hash');
    ok(exists $src->{kernel}, 'kernel source present');
    ok(exists $src->{sshd},   'sshd source present');
};

subtest 'severity classification on fixture' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $fixture,
        max_lines => 100,
    );
    my $sev = $result->{severity_count};
    ok(ref $sev eq 'HASH', 'severity_count is hash');
    # The fixture has OOM, SSL error, FAILURE — should have errors
    cmp_ok(($sev->{error} // 0), '>=', 1, 'at least 1 error-level entry');
    cmp_ok(($sev->{warning} // 0), '>=', 1, 'at least 1 warning-level entry');
};

subtest 'pattern filter on fixture - kernel' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $fixture,
        max_lines => 100,
        pattern   => 'kernel',
    );
    ok(!$result->{error}, 'no error');
    cmp_ok($result->{total_entries}, '>=', 2, 'at least 2 kernel entries');
    for my $e (@{$result->{entries}}) {
        like($e->{source}, qr/kernel/i, "source is kernel: $e->{source}");
    }
};

subtest 'pattern filter on fixture - sshd' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $fixture,
        max_lines => 100,
        pattern   => 'sshd',
    );
    ok(!$result->{error}, 'no error');
    cmp_ok($result->{total_entries}, '>=', 1, 'at least 1 sshd entry');
};

subtest 'hourly distribution from fixture' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $fixture,
        max_lines => 100,
    );
    ok(exists $result->{hourly}, 'has hourly');
    ok(ref $result->{hourly} eq 'HASH', 'hourly is hash');
    # All fixture entries are in hour 10
    ok(exists $result->{hourly}{'10'}, 'entries in hour 10');
    is($result->{hourly}{'10'}, 10, 'all 10 entries in hour 10');
};

subtest 'format_report from fixture data' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $fixture,
        max_lines => 100,
    );
    my $report = HBPerl::Scripts::LogAnalyzer::format_report($result);
    ok(length($report) > 200, 'report has substantial content');
    like($report, qr/LOG ANALYZER/i, 'has header');
    like($report, qr/(?:10 entries|entries.*10)/, 'mentions entry count');
};

done_testing();
