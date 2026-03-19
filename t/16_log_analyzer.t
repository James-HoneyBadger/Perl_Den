#!/usr/bin/env perl
# ============================================================================
# t/16_log_analyzer.t — Test HBPerl::Scripts::LogAnalyzer
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempfile);

use_ok('HBPerl::Scripts::LogAnalyzer');

subtest 'parse syslog-format log file' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh <<'LOG';
Jun 15 08:01:22 myhost sshd[1234]: Accepted publickey for james from 192.168.1.1 port 22
Jun 15 08:02:33 myhost kernel: [12345.678] Out of memory: Kill process 5678
Jun 15 08:03:44 myhost cron[9012]: (root) CMD (/usr/sbin/logrotate)
Jun 15 09:00:00 myhost systemd[1]: Started Daily Cleanup
Jun 15 09:01:11 myhost sshd[2345]: error: Authentication failure for invalid user admin
LOG
    close $fh;

    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
    );

    ok(ref $result eq 'HASH', 'returns a hashref');
    ok(!$result->{error}, 'no error');
    is($result->{total_entries}, 5, 'parsed 5 entries');
    ok(ref $result->{entries} eq 'ARRAY', 'entries is an array');
    ok(exists $result->{severity_count}, 'has severity_count');
    ok(exists $result->{source_count}, 'has source_count');
    ok(exists $result->{hourly}, 'has hourly');

    # Check first entry parsed correctly
    my $first = $result->{entries}[0];
    is($first->{host}, 'myhost', 'host parsed');
    is($first->{source}, 'sshd', 'source parsed');
    like($first->{message}, qr/Accepted publickey/, 'message parsed');
};

subtest 'pattern filtering' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh <<'LOG';
Jun 15 08:01:22 myhost sshd[1234]: Accepted publickey for james
Jun 15 08:02:33 myhost kernel: something else entirely
Jun 15 08:03:44 myhost sshd[5678]: Failed password for root
LOG
    close $fh;

    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => $tmpfile,
        max_lines => 100,
        pattern   => 'sshd',
    );

    is($result->{total_entries}, 2, 'pattern filtered to 2 sshd entries');
};

subtest 'nonexistent file returns error' => sub {
    my $result = HBPerl::Scripts::LogAnalyzer::run(
        log_file => '/tmp/this_file_does_not_exist_' . $$,
    );
    ok($result->{error}, 'error is set');
    like($result->{error}, qr/not found|not readable/, 'meaningful error');
};

subtest 'format_report produces text' => sub {
    my ($fh, $tmpfile) = tempfile(SUFFIX => '.log', UNLINK => 1);
    print $fh "Jun 15 08:01:22 myhost sshd[1234]: Test message\n";
    close $fh;

    my $result = HBPerl::Scripts::LogAnalyzer::run(log_file => $tmpfile);
    my $report = HBPerl::Scripts::LogAnalyzer::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/LOG ANALYZER/i, 'report has header');
};

subtest 'format_report handles error' => sub {
    my $report = HBPerl::Scripts::LogAnalyzer::format_report({ error => 'test error' });
    like($report, qr/ERROR:.*test error/, 'error report works');
};

done_testing();
