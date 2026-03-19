#!/usr/bin/env perl
# ============================================================================
# t/05_process_manager.t — Test HBPerl::Scripts::ProcessManager
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('HBPerl::Scripts::ProcessManager');

subtest 'run returns process data' => sub {
    my $result = HBPerl::Scripts::ProcessManager::run(top_n => 5);
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{processes}, 'has processes key');
    ok(ref $result->{processes} eq 'ARRAY', 'processes is array');
    cmp_ok(scalar @{$result->{processes}}, '>', 0, 'has at least one process');
};

subtest 'process entry has expected fields' => sub {
    my $r = HBPerl::Scripts::ProcessManager::run(top_n => 1);
    my $proc = $r->{processes}[0];
    ok(defined $proc, 'got a process');
    for my $key (qw(user pid cpu mem command)) {
        ok(exists $proc->{$key}, "process has key: $key");
    }
};

subtest 'format_report works' => sub {
    my $r = HBPerl::Scripts::ProcessManager::run(top_n => 5);
    my $report = HBPerl::Scripts::ProcessManager::format_report($r);
    ok(length($report) > 50, 'report has content');
    like($report, qr/PROCESS/, 'report mentions processes');
};

done_testing();
