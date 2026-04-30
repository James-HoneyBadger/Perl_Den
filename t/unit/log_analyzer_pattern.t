#!/usr/bin/env perl
# ============================================================================
# t/unit/log_analyzer_pattern.t — Unit tests for LogAnalyzer pattern handling
# Tests regex validation, pattern filtering, and edge cases
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use File::Temp qw(tempfile);

use_ok('BadgerOps::Scripts::LogAnalyzer');

# ---------------------------------------------------------------------------
# Invalid regex pattern handling
# ---------------------------------------------------------------------------

subtest 'invalid regex returns error' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh "Jun 15 08:01:22 myhost sshd[1234]: Test message\n";
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
        pattern   => '(unclosed[paren',
    );

    ok($result->{error}, 'error is set for invalid regex');
    like($result->{error}, qr/Invalid regex pattern/, 'error mentions invalid regex');
};

subtest 'another invalid regex' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh "Jun 15 08:01:22 myhost sshd[1234]: Test message\n";
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
        pattern   => '*bad',
    );

    ok($result->{error}, 'error is set for quantifier-only regex');
    like($result->{error}, qr/Invalid regex pattern/, 'error mentions invalid regex');
};

# ---------------------------------------------------------------------------
# Valid pattern filtering
# ---------------------------------------------------------------------------

subtest 'valid pattern filters correctly' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh <<'LOG';
Jun 15 08:01:22 myhost sshd[1234]: Accepted publickey for james
Jun 15 08:02:33 myhost kernel: something else entirely
Jun 15 08:03:44 myhost sshd[5678]: Failed password for root
Jun 15 08:04:55 myhost cron[9012]: (root) CMD (/usr/sbin/logrotate)
LOG
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
        pattern   => 'sshd',
    );

    ok(!$result->{error}, 'no error');
    is($result->{total_entries}, 2, 'filtered to 2 sshd entries');
};

subtest 'regex pattern with metacharacters' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh <<'LOG';
Jun 15 08:01:22 myhost sshd[1234]: Failed password for root
Jun 15 08:02:33 myhost sshd[5678]: Accepted publickey for james
Jun 15 08:03:44 myhost sshd[9012]: Failed password for admin
LOG
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
        pattern   => 'Failed.*root',
    );

    ok(!$result->{error}, 'no error');
    is($result->{total_entries}, 1, 'regex matched 1 entry');
    like($result->{entries}[0]{message}, qr/Failed password for root/, 'correct entry matched');
};

subtest 'empty pattern returns all entries' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh <<'LOG';
Jun 15 08:01:22 myhost sshd[1234]: Message one
Jun 15 08:02:33 myhost sshd[5678]: Message two
Jun 15 08:03:44 myhost sshd[9012]: Message three
LOG
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
        pattern   => '',
    );

    ok(!$result->{error}, 'no error');
    is($result->{total_entries}, 3, 'all 3 entries returned with empty pattern');
};

# ---------------------------------------------------------------------------
# Severity detection
# ---------------------------------------------------------------------------

subtest 'severity classification' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh <<'LOG';
Jun 15 08:01:00 myhost sshd[100]: fatal error occurred segfault
Jun 15 08:02:00 myhost sshd[101]: warning timeout connecting
Jun 15 08:03:00 myhost systemd[1]: Started Daily Cleanup
Jun 15 08:04:00 myhost sshd[102]: normal informational message
LOG
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
    );

    ok(!$result->{error}, 'no error');
    ok($result->{severity_count}{error} >= 1, 'at least 1 error');
    ok($result->{severity_count}{warning} >= 1, 'at least 1 warning');
    ok($result->{severity_count}{notice} >= 1, 'at least 1 notice');
};

# ---------------------------------------------------------------------------
# max_lines limit
# ---------------------------------------------------------------------------

subtest 'max_lines limits entries' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    for my $i (1..50) {
        printf $fh "Jun 15 08:%02d:00 myhost test[$i]: Message $i\n", $i % 60;
    }
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 10,
    );

    ok(!$result->{error}, 'no error');
    is($result->{total_entries}, 10, 'capped at 10 entries');
};

# ---------------------------------------------------------------------------
# format_report
# ---------------------------------------------------------------------------

subtest 'format_report error result' => sub {
    my $result = { error => 'Something went wrong' };
    my $report = BadgerOps::Scripts::LogAnalyzer::format_report($result);
    like($report, qr/ERROR.*Something went wrong/, 'error report contains message');
};

subtest 'format_report hourly histogram' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    for my $i (1..20) {
        print $fh "Jun 15 08:00:00 myhost sshd[100]: Test message\n";
    }
    for my $i (1..5) {
        print $fh "Jun 15 14:00:00 myhost sshd[200]: Test message\n";
    }
    close $fh;

    my $result = BadgerOps::Scripts::LogAnalyzer::run(log_file => $tmpfile);
    my $report = BadgerOps::Scripts::LogAnalyzer::format_report($result);
    like($report, qr/Hourly Activity/, 'has hourly section');
    like($report, qr/08:00/, 'shows hour 08');
};

done_testing();
