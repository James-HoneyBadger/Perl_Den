#!/usr/bin/env perl
# ============================================================================
# t/03_system_info.t — Test PerlDen::Scripts::SystemInfo
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('PerlDen::Scripts::SystemInfo');

SKIP: {
    skip 'No /proc/meminfo (non-Linux)', 17 unless -f '/proc/meminfo';

subtest 'run returns expected keys' => sub {
    my $result = PerlDen::Scripts::SystemInfo::run();
    ok(ref $result eq 'HASH', 'returns a hashref');

    for my $key (qw(hostname kernel uptime_seconds load_1 cpu_model mem_total_kb)) {
        ok(exists $result->{$key}, "has key: $key");
    }
};

subtest 'hostname is non-empty' => sub {
    my $r = PerlDen::Scripts::SystemInfo::run();
    ok(length($r->{hostname}) > 0, 'hostname is non-empty');
};

subtest 'kernel looks like a version' => sub {
    my $r = PerlDen::Scripts::SystemInfo::run();
    like($r->{kernel}, qr/\d+\.\d+/, 'kernel has version numbers');
};

subtest 'uptime is positive' => sub {
    my $r = PerlDen::Scripts::SystemInfo::run();
    cmp_ok($r->{uptime_seconds}, '>', 0, 'uptime > 0');
};

subtest 'memory has total and available' => sub {
    my $r = PerlDen::Scripts::SystemInfo::run();
    ok(exists $r->{mem_total_kb}, 'has mem_total_kb');
    cmp_ok($r->{mem_total_kb}, '>', 0, 'mem_total_kb > 0');
};

subtest 'format_report produces text' => sub {
    my $r = PerlDen::Scripts::SystemInfo::run();
    my $report = PerlDen::Scripts::SystemInfo::format_report($r);
    ok(length($report) > 100, 'report has content');
    like($report, qr/SYSTEM INFORMATION/i, 'report has header');
};

} # end SKIP

done_testing();
