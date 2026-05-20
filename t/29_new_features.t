#!/usr/bin/env perl
# ============================================================================
# t/29_new_features.t — Tests for features added in the improvement sprint
# Covers: find_top_n, Scheduler enable/disable, BatchRunner timeout,
#         BatchRunner parallel, Runner run_stream, ServiceMonitor JSON path
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

my $HAS_TEST_EXCEPTION = eval { require Test::Exception; Test::Exception->import('dies_ok', 'lives_ok'); 1 };

# ── 1. ScriptRegistry::find_top_n ────────────────────────────────────────────
subtest 'find_top_n basic' => sub {
    use_ok('PerlDen::ScriptRegistry', qw(find_top_n script_index));

    my @top = find_top_n('system', 3);
    ok(scalar @top > 0,  'find_top_n returns results for "system"');
    ok(scalar @top <= 3, 'find_top_n honours limit of 3');
    for my $name (@top) {
        ok(defined $name && length $name, "result '$name' is non-empty string");
    }
};

subtest 'find_top_n with unknown query returns empty list gracefully' => sub {
    my @top = find_top_n('xyzzy_nonexistent_9999', 5);
    is(ref \@top, 'ARRAY', 'always returns a list');
    ok(scalar @top == 0, 'empty list for unrecognised query');
};

subtest 'find_top_n respects n=1' => sub {
    my @top = find_top_n('disk', 1);
    ok(scalar @top <= 1, 'at most 1 result when n=1');
};

# ── 2. Scheduler::disable_job / enable_job ───────────────────────────────────
subtest 'Scheduler disable and enable job' => sub {
    unless ($HAS_TEST_EXCEPTION) {
        plan skip_all => 'Test::Exception required';
        return;
    }

    require PerlDen::Scheduler;

    my @MOCK = ();
    {
        no warnings 'redefine';
        *PerlDen::Scheduler::_read_crontab  = sub { return @MOCK };
        *PerlDen::Scheduler::_write_crontab = sub { @MOCK = @_ };
        *PerlDen::Scheduler::_hbperl_cli_path = sub { '/usr/local/bin/perlden-cli' };
    }

    # Set up an active job
    @MOCK = ('0 6 * * * /usr/local/bin/perlden-cli run disk_usage # hbperl-job script=disk_usage');

    # disable_job
    PerlDen::Scheduler::disable_job('disk_usage');
    ok(scalar @MOCK == 1, 'still one crontab line after disable');
    like($MOCK[0], qr/^#\s*DISABLED:/, 'disabled line starts with # DISABLED:');
    like($MOCK[0], qr/disk_usage/,     'disabled line still references script');

    # list_jobs sees it as disabled
    my @jobs = PerlDen::Scheduler::list_jobs();
    is(scalar @jobs, 1, 'list_jobs still returns 1 job');
    ok(!$jobs[0]{enabled}, 'job is marked as disabled');

    # enable_job restores it
    PerlDen::Scheduler::enable_job('disk_usage');
    ok(scalar @MOCK == 1, 'still one line after enable');
    unlike($MOCK[0], qr/^#\s*DISABLED:/, 'line no longer has DISABLED prefix');

    # list_jobs sees it as enabled
    @jobs = PerlDen::Scheduler::list_jobs();
    ok($jobs[0]{enabled}, 'job is now enabled');

    # disable_job dies if job not found
    ok(eval { PerlDen::Scheduler::disable_job('nonexistent_xyz'); 1 } ? 0 : 1,
        'disable_job dies when script not found');

    # enable_job dies if no disabled job found (disk_usage is now active, not disabled)
    ok(eval { PerlDen::Scheduler::enable_job('disk_usage'); 1 } ? 0 : 1,
        'enable_job dies when no disabled entry found');
};

# ── 3. BatchRunner timeout option ────────────────────────────────────────────
subtest 'BatchRunner timeout kills slow script' => sub {
    use_ok('PerlDen::BatchRunner');

    # Inject a slow script module directly
    {
        no strict 'refs';
        *{'PerlDen::Scripts::SlowTest::run'} = sub { sleep 30; return { done => 1 } };
        # Mark the module as loaded so require doesn't fail
        $INC{'PerlDen/Scripts/SlowTest.pm'} = 1;
    }

    # Mock find_script in BatchRunner's namespace (it was imported, so patch there)
    no warnings 'redefine';
    local *PerlDen::BatchRunner::find_script = sub {
        my ($name) = @_;
        return () unless $name eq '_slow_test_';
        return ('Slow Test', '_slow_test_.pl',
                'PerlDen::Scripts::SlowTest', 'Intentionally slow', 'Test');
    };

    my $br = PerlDen::BatchRunner->new();
    my $t0 = time();
    my $results = $br->run_batch('_slow_test_', { timeout_seconds => 2 });
    my $elapsed = time() - $t0;

    ok($results->[0]{error}, 'timed-out script produces an error result');
    ok($elapsed >= 2 && $elapsed <= 5, "ran for ~2-3 seconds (elapsed=${elapsed}s)");
};

# ── 4. BatchRunner run_batch_parallel ────────────────────────────────────────
subtest 'run_batch_parallel returns results in order' => sub {
    my $br = PerlDen::BatchRunner->new();
    my $results = $br->run_batch_parallel('system_info', 'disk_usage', { parallel => 2 });
    ok(ref $results eq 'ARRAY', 'returns arrayref');
    is(scalar @$results, 2, '2 results for 2 scripts');
    is($results->[0]{name}, 'System Information', 'first result is system_info');
    ok(!$results->[0]{error}, 'system_info succeeded');
    ok(!$results->[1]{error}, 'disk_usage succeeded');
};

subtest 'run_batch_parallel handles unknown scripts gracefully' => sub {
    my $br = PerlDen::BatchRunner->new();
    my $results = $br->run_batch_parallel('system_info', 'nonexistent_xyz_999');
    is(scalar @$results, 2, '2 results returned');
    ok(!$results->[0]{error}, 'valid script succeeded');
    ok($results->[1]{error},  'unknown script has error');
};

# ── 5. Runner::run_stream ─────────────────────────────────────────────────────
subtest 'Runner run_stream basic output capture' => sub {
    use_ok('PerlDen::Runner');

    my $buf = '';
    open my $fh, '>', \$buf or die "Cannot open string buffer: $!";
    my $exit = PerlDen::Runner->run_stream($fh, 'echo', 'hello_stream');
    close $fh;

    is($exit, 0, 'run_stream exits 0');
    like($buf, qr/hello_stream/, 'streamed output contains expected text');
};

subtest 'Runner run_stream timeout kills command' => sub {
    my $buf = '';
    open my $fh, '>', \$buf or die "Cannot open string buffer: $!";
    my $t0   = time();
    my $exit = PerlDen::Runner->run_stream($fh, 'sleep', '30', { timeout => 2 });
    my $elapsed = time() - $t0;
    close $fh;

    is($exit, 124, 'exit code 124 on timeout');
    like($buf, qr/timed out/i, 'timeout message in output');
    ok($elapsed <= 5, 'completed within 5 seconds (not 30)');
};

subtest 'Runner run_stream exit code passthrough' => sub {
    my $buf = '';
    open my $fh, '>', \$buf or die "Cannot open string buffer: $!";
    my $exit = PerlDen::Runner->run_stream($fh, 'false');
    close $fh;
    isnt($exit, 0, 'non-zero exit code from false');
};

# ── 6. Scheduler cron validation (range checks) ──────────────────────────────
subtest 'Scheduler _validate_cron_expr range enforcement' => sub {
    require PerlDen::Scheduler;

    unless ($HAS_TEST_EXCEPTION) {
        plan skip_all => 'Test::Exception required';
        return;
    }

    my @MOCK = ();
    {
        no warnings 'redefine';
        *PerlDen::Scheduler::_read_crontab  = sub { @MOCK };
        *PerlDen::Scheduler::_write_crontab = sub { @MOCK = @_ };
        *PerlDen::Scheduler::_hbperl_cli_path = sub { '/usr/local/bin/perlden-cli' };
    }

    # Invalid: minute 60 (max is 59)
    ok(eval { PerlDen::Scheduler::add_job(script => 'disk_usage', schedule => '60 * * * *'); 1 } ? 0 : 1,
        'minute=60 is rejected');

    # Invalid: hour 24
    ok(eval { PerlDen::Scheduler::add_job(script => 'disk_usage', schedule => '0 24 * * *'); 1 } ? 0 : 1,
        'hour=24 is rejected');

    # Valid: */15 step
    @MOCK = ();
    ok(eval { PerlDen::Scheduler::add_job(script => 'disk_usage', schedule => '*/15 * * * *'); 1 },
        '*/15 step is valid');

    # Valid: range
    @MOCK = ();
    ok(eval { PerlDen::Scheduler::add_job(script => 'disk_usage', schedule => '0-30 9-17 * * 1-5'); 1 },
        'range expressions are valid');
};

done_testing();
