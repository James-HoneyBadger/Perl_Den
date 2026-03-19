#!/usr/bin/env perl
# ============================================================================
# t/unit/failed_login_parse.t — Unit tests for FailedLoginDetector parsing
# Tests _parse_auth_lines and _syslog_to_epoch with synthetic log data
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use_ok('HBPerl::Scripts::FailedLoginDetector');

# ---------------------------------------------------------------------------
# _parse_auth_lines tests
# ---------------------------------------------------------------------------

subtest 'parse SSH failed password' => sub {
    my @lines = (
        "Mar 15 10:22:33 myhost sshd[1234]: Failed password for james from 192.168.1.100 port 22 ssh2\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 1, 'one entry parsed');
    is($entries[0]{type}, 'fail', 'type is fail');
    is($entries[0]{user}, 'james', 'user parsed');
    is($entries[0]{ip}, '192.168.1.100', 'IP parsed');
    is($entries[0]{service}, 'sshd', 'service is sshd');
    is($entries[0]{detail}, 'Failed password', 'detail correct');
    like($entries[0]{time}, qr/Mar\s+15\s+10:22:33/, 'timestamp parsed');
};

subtest 'parse SSH failed password for invalid user' => sub {
    my @lines = (
        "Mar 15 10:22:33 myhost sshd[1234]: Failed password for invalid user admin from 10.0.0.5 port 22 ssh2\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 1, 'one entry parsed');
    is($entries[0]{type}, 'fail', 'type is fail');
    is($entries[0]{user}, 'admin', 'invalid user name parsed');
    is($entries[0]{ip}, '10.0.0.5', 'IP parsed');
};

subtest 'parse Invalid user line' => sub {
    my @lines = (
        "Mar 15 10:23:00 myhost sshd[1235]: Invalid user hacker from 10.0.0.99\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 1, 'one entry parsed');
    is($entries[0]{type}, 'fail', 'type is fail');
    is($entries[0]{user}, 'hacker', 'user parsed');
    is($entries[0]{ip}, '10.0.0.99', 'IP parsed');
    is($entries[0]{detail}, 'Invalid user', 'detail correct');
};

subtest 'parse PAM authentication failure' => sub {
    my @lines = (
        "Mar 15 11:00:00 myhost login: authentication failure; logname= uid=0 euid=0 tty=/dev/tty1 ruser=root rhost=192.168.1.50\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 1, 'one entry parsed');
    is($entries[0]{type}, 'fail', 'type is fail');
    is($entries[0]{user}, 'root', 'user parsed');
    is($entries[0]{ip}, '192.168.1.50', 'IP parsed');
    is($entries[0]{service}, 'pam', 'service is pam');
};

subtest 'parse Connection closed during auth' => sub {
    my @lines = (
        "Mar 15 12:00:00 myhost sshd[5678]: Connection closed by authenticating user deploy 172.16.0.1 port 22\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 1, 'one entry parsed');
    is($entries[0]{type}, 'fail', 'type is fail');
    is($entries[0]{user}, 'deploy', 'user parsed');
    is($entries[0]{ip}, '172.16.0.1', 'IP parsed');
    is($entries[0]{detail}, 'Connection closed during auth', 'detail correct');
};

subtest 'parse Accepted login' => sub {
    my @lines = (
        "Mar 15 12:30:00 myhost sshd[9999]: Accepted publickey for james from 192.168.1.1 port 22 ssh2\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 1, 'one entry parsed');
    is($entries[0]{type}, 'success', 'type is success');
    is($entries[0]{method}, 'publickey', 'method parsed');
    is($entries[0]{user}, 'james', 'user parsed');
    is($entries[0]{ip}, '192.168.1.1', 'IP parsed');
};

subtest 'parse sudo auth failure' => sub {
    my @lines = (
        "Mar 15 13:00:00 myhost sudo: pam_unix(sudo:auth): authentication failure; logname= uid=1000 user james\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 1, 'one entry parsed');
    is($entries[0]{type}, 'fail', 'type is fail');
    is($entries[0]{user}, 'james', 'user parsed');
    is($entries[0]{ip}, 'local', 'IP is local');
    is($entries[0]{service}, 'sudo', 'service is sudo');
};

subtest 'parse mixed log entries' => sub {
    my @lines = (
        "Mar 15 10:00:00 myhost sshd[100]: Failed password for root from 10.0.0.1 port 22 ssh2\n",
        "Mar 15 10:00:01 myhost sshd[101]: Failed password for root from 10.0.0.1 port 22 ssh2\n",
        "Mar 15 10:00:02 myhost sshd[102]: Failed password for root from 10.0.0.1 port 22 ssh2\n",
        "Mar 15 10:00:03 myhost sshd[103]: Accepted password for james from 192.168.1.1 port 22 ssh2\n",
        "Mar 15 10:00:04 myhost sshd[104]: Invalid user test from 10.0.0.2\n",
        "Mar 15 10:00:05 myhost kernel: [12345.678] some kernel message\n",
    );
    my @entries = HBPerl::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    is(scalar @entries, 5, 'parsed 5 of 6 lines (kernel message ignored)');

    my @fails = grep { $_->{type} eq 'fail' } @entries;
    my @successes = grep { $_->{type} eq 'success' } @entries;
    is(scalar @fails, 4, '4 failed entries');
    is(scalar @successes, 1, '1 success entry');
};

# ---------------------------------------------------------------------------
# _syslog_to_epoch tests
# ---------------------------------------------------------------------------

subtest 'syslog_to_epoch parses syslog format' => sub {
    my $epoch = HBPerl::Scripts::FailedLoginDetector::_syslog_to_epoch('Mar 15 10:22:33');
    ok(defined $epoch, 'returns a defined value');
    ok($epoch > 0, 'returns positive epoch');

    my @t = localtime($epoch);
    is($t[2], 10, 'hour is 10');
    is($t[1], 22, 'minute is 22');
    is($t[0], 33, 'second is 33');
    is($t[3], 15, 'day is 15');
    is($t[4], 2, 'month is March (2)');
};

subtest 'syslog_to_epoch parses journalctl format' => sub {
    my $epoch = HBPerl::Scripts::FailedLoginDetector::_syslog_to_epoch('Mon 2026-03-15 14:30:00');
    ok(defined $epoch, 'returns a defined value');
    ok($epoch > 0, 'returns positive epoch');

    my @t = localtime($epoch);
    is($t[2], 14, 'hour is 14');
    is($t[1], 30, 'minute is 30');
    is($t[5] + 1900, 2026, 'year is 2026');
};

subtest 'syslog_to_epoch handles unknown' => sub {
    my $epoch = HBPerl::Scripts::FailedLoginDetector::_syslog_to_epoch('unknown');
    ok(!defined $epoch, 'returns undef for unknown');
};

subtest 'syslog_to_epoch handles undef' => sub {
    my $epoch = HBPerl::Scripts::FailedLoginDetector::_syslog_to_epoch(undef);
    ok(!defined $epoch, 'returns undef for undef input');
};

# ---------------------------------------------------------------------------
# _extract_time tests
# ---------------------------------------------------------------------------

subtest 'extract_time syslog format' => sub {
    my $t = HBPerl::Scripts::FailedLoginDetector::_extract_time(
        'Mar 15 10:22:33 myhost sshd[1234]: something');
    like($t, qr/Mar\s+15\s+10:22:33/, 'extracted syslog timestamp');
};

subtest 'extract_time journalctl format' => sub {
    my $t = HBPerl::Scripts::FailedLoginDetector::_extract_time(
        'Mon 2026-03-15 14:30:00 myhost sshd[1234]: something');
    like($t, qr/Mon\s+2026-03-15\s+14:30:00/, 'extracted journalctl timestamp');
};

subtest 'extract_time unrecognized' => sub {
    my $t = HBPerl::Scripts::FailedLoginDetector::_extract_time('garbage line');
    is($t, 'unknown', 'returns unknown for unrecognized format');
};

# ---------------------------------------------------------------------------
# run + format_report with synthetic data (via source=auto on a system without auth logs)
# ---------------------------------------------------------------------------

subtest 'format_report handles empty results' => sub {
    my $result = {
        total_failed  => 0,
        total_success => 0,
        by_ip         => {},
        by_user       => {},
        by_service    => {},
        flagged_ips   => [],
        flagged_users => [],
        banned        => [],
        hours         => 1,
        threshold     => 5,
        recent        => [],
    };
    my $report = HBPerl::Scripts::FailedLoginDetector::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/FAILED LOGIN|BRUTE/i, 'has header');
    like($report, qr/None detected/, 'reports none detected');
};

subtest 'format_report handles flagged IPs and users' => sub {
    my $result = {
        total_failed  => 100,
        total_success => 5,
        by_ip         => { '10.0.0.1' => 50, '10.0.0.2' => 30, '10.0.0.3' => 2 },
        by_user       => { 'root' => 60, 'admin' => 20 },
        by_service    => { 'sshd' => 80, 'pam' => 20 },
        flagged_ips   => [
            { ip => '10.0.0.1', attempts => 50 },
            { ip => '10.0.0.2', attempts => 30 },
        ],
        flagged_users => [
            { user => 'root', attempts => 60 },
            { user => 'admin', attempts => 20 },
        ],
        banned        => ['10.0.0.1'],
        hours         => 24,
        threshold     => 5,
        recent        => [
            { time => 'Mar 15 10:00:00', ip => '10.0.0.1', user => 'root',
              service => 'sshd', detail => 'Failed password' },
        ],
    };
    my $report = HBPerl::Scripts::FailedLoginDetector::format_report($result);
    like($report, qr/10\.0\.0\.1/, 'contains flagged IP');
    like($report, qr/root/, 'contains flagged user');
    like($report, qr/50 failed attempts/, 'shows attempt count');
    like($report, qr/10\.0\.0\.1/, 'shows banned IP');
};

done_testing();
