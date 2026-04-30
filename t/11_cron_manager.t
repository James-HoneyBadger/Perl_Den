#!/usr/bin/env perl
# ============================================================================
# t/11_cron_manager.t — Test BadgerOps::Scripts::CronManager
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('BadgerOps::Scripts::CronManager');

subtest 'run returns cron data' => sub {
    my $result = BadgerOps::Scripts::CronManager::run();
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{user_crons}, 'has user_crons');
    ok(exists $result->{system_crons}, 'has system_crons');
    ok(exists $result->{timers}, 'has timers');
};

subtest 'timers is an array' => sub {
    my $r = BadgerOps::Scripts::CronManager::run();
    ok(ref $r->{timers} eq 'ARRAY', 'timers is array');
};

subtest 'format_report works' => sub {
    my $r = BadgerOps::Scripts::CronManager::run();
    my $report = BadgerOps::Scripts::CronManager::format_report($r);
    ok(length($report) > 30, 'report has content');
    like($report, qr/CRON/i, 'report has cron header');
};

done_testing();
