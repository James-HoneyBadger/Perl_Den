#!/usr/bin/env perl
# ============================================================================
# t/11_cron_manager.t — Test PerlDen::Scripts::CronManager
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('PerlDen::Scripts::CronManager');

subtest 'run returns cron data' => sub {
    my $result = PerlDen::Scripts::CronManager::run();
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{user_crons}, 'has user_crons');
    ok(exists $result->{system_crons}, 'has system_crons');
    ok(exists $result->{timers}, 'has timers');
};

subtest 'timers is an array' => sub {
    my $r = PerlDen::Scripts::CronManager::run();
    ok(ref $r->{timers} eq 'ARRAY', 'timers is array');
};

subtest 'format_report works' => sub {
    my $r = PerlDen::Scripts::CronManager::run();
    my $report = PerlDen::Scripts::CronManager::format_report($r);
    ok(length($report) > 30, 'report has content');
    like($report, qr/CRON/i, 'report has cron header');
};

done_testing();
