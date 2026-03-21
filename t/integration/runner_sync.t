#!/usr/bin/env perl
# ============================================================================
# t/integration/runner_sync.t — Integration tests for Runner::run_sync
# Tests: timeout, large output, concurrent stdout+stderr, command not found
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";

eval { require Glib };
plan skip_all => 'Glib not available' if $@;

use_ok('HBPerl::Runner');

subtest 'basic echo' => sub {
    my ($out, $err, $rc) = HBPerl::Runner->run_sync('echo', 'hello world');
    chomp $out;
    is($out, 'hello world', 'captured stdout');
    is($err, '', 'no stderr');
    is($rc, 0, 'exit code 0');
};

subtest 'exit code propagation' => sub {
    my ($out, $err, $rc) = HBPerl::Runner->run_sync('bash', '-c', 'exit 42');
    is($rc, 42, 'captures non-zero exit code');
};

subtest 'stderr capture' => sub {
    my ($out, $err, $rc) = HBPerl::Runner->run_sync('bash', '-c', 'echo ERR >&2');
    chomp $err;
    is($err, 'ERR', 'captured stderr');
    is($out, '', 'stdout empty');
};

subtest 'concurrent stdout and stderr (deadlock prevention)' => sub {
    # Generate >64KB on both streams simultaneously
    my $cmd = 'perl -e "for(1..5000){print STDOUT qq{OUT-line-\$_\\n}; print STDERR qq{ERR-line-\$_\\n}}"';
    my ($out, $err, $rc) = HBPerl::Runner->run_sync($cmd);
    is($rc, 0, 'exit code 0');
    my @out_lines = split /\n/, $out;
    my @err_lines = split /\n/, $err;
    is(scalar @out_lines, 5000, 'got all 5000 stdout lines');
    is(scalar @err_lines, 5000, 'got all 5000 stderr lines');
    like($out_lines[0], qr/^OUT-line-1$/, 'first stdout line correct');
    like($err_lines[-1], qr/^ERR-line-5000$/, 'last stderr line correct');
};

subtest 'command not found' => sub {
    my ($out, $err, $rc) = HBPerl::Runner->run_sync('nonexistent_command_xyz');
    isnt($rc, 0, 'non-zero exit code for missing command');
};

subtest 'timeout kills long-running command' => sub {
    my ($out, $err, $rc) = HBPerl::Runner->run_sync(
        'sleep', '30',
        { timeout => 2 },
    );
    is($rc, 124, 'timeout returns exit code 124');
    like($err, qr/timed out/i, 'stderr mentions timeout');
};

subtest 'timeout not triggered for fast command' => sub {
    my ($out, $err, $rc) = HBPerl::Runner->run_sync(
        'echo', 'fast',
        { timeout => 10 },
    );
    chomp $out;
    is($out, 'fast', 'output captured');
    is($rc, 0, 'no timeout for fast command');
};

subtest 'single string command (backward compat)' => sub {
    my ($out, $err, $rc) = HBPerl::Runner->run_sync('echo "hello from bash"');
    chomp $out;
    is($out, 'hello from bash', 'single string routed through bash');
    is($rc, 0, 'exit code 0');
};

done_testing();
