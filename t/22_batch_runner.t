#!/usr/bin/env perl
# ============================================================================
# t/22_batch_runner.t — Test BadgerOps::BatchRunner
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('BadgerOps::BatchRunner');

subtest 'constructor defaults' => sub {
    my $br = BadgerOps::BatchRunner->new();
    ok($br, 'created BatchRunner');
    is(ref $br->{on_progress}, 'CODE', 'on_progress default is coderef');
    is(ref $br->{on_error}, 'CODE', 'on_error default is coderef');
};

subtest 'batch with system_info' => sub {
    my $br = BadgerOps::BatchRunner->new();
    my $results = $br->run_batch('system_info');
    ok(ref $results eq 'ARRAY', 'returns arrayref');
    is(scalar @$results, 1, 'one result');
    ok(!$results->[0]{error}, 'no error for system_info');
    is($results->[0]{name}, 'System Information', 'correct display name');
    ok(ref $results->[0]{data} eq 'HASH', 'data is hashref');
    ok(length($results->[0]{report}) > 100, 'report has content');
};

subtest 'batch with unknown script' => sub {
    my @errors;
    my $br = BadgerOps::BatchRunner->new(
        on_error => sub { push @errors, [@_] },
    );
    my $results = $br->run_batch('nonexistent_xyz');
    is(scalar @$results, 1, 'one result');
    ok($results->[0]{error}, 'error is set');
    like($results->[0]{error}, qr/Unknown script/, 'meaningful error');
    is(scalar @errors, 1, 'on_error callback fired');
};

subtest 'batch with multiple scripts' => sub {
    my @progress;
    my $br = BadgerOps::BatchRunner->new(
        on_progress => sub { push @progress, [@_] },
    );
    my $results = $br->run_batch('system_info', 'disk_usage');
    is(scalar @$results, 2, 'two results');
    ok(!$results->[0]{error}, 'system_info succeeded');
    ok(!$results->[1]{error}, 'disk_usage succeeded');
    is(scalar @progress, 2, 'progress called twice');
    is($progress[0][1], 1, 'first progress index is 1');
    is($progress[0][2], 2, 'total is 2');
    is($progress[1][1], 2, 'second progress index is 2');
};

subtest 'format_batch_report' => sub {
    my $br = BadgerOps::BatchRunner->new();
    my $results = $br->run_batch('system_info');
    my $report = $br->format_batch_report($results);
    ok(length($report) > 100, 'batch report has content');
    like($report, qr/BATCH REPORT/, 'has batch header');
    like($report, qr/1 succeeded/, 'shows success count');
    like($report, qr/0 failed/, 'shows failure count');
};

subtest 'format_batch_report with mixed results' => sub {
    my $br = BadgerOps::BatchRunner->new();
    my $results = $br->run_batch('system_info', 'nonexistent_xyz');
    my $report = $br->format_batch_report($results);
    like($report, qr/1 succeeded/, 'shows 1 success');
    like($report, qr/1 failed/, 'shows 1 failure');
    like($report, qr/ERROR.*Unknown script/, 'shows error detail');
};

subtest 'format_batch_report with empty results' => sub {
    my $br = BadgerOps::BatchRunner->new();
    my $report = $br->format_batch_report([]);
    like($report, qr/0 script/, 'handles empty results');
};

done_testing();
