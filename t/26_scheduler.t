#!/usr/bin/perl
# ============================================================================
# t/26_scheduler.t - HBPerl::Scheduler tests (mocked crontab)
# ============================================================================
use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Temp qw(tempfile);
use FindBin qw($RealBin);
use lib File::Spec->catdir($RealBin, '..', 'lib');

require HBPerl::Scheduler;

# ── Mock crontab I/O ──────────────────────────────────────────────────────────
# We override _read_crontab and _write_crontab so no real crontab is touched.

my @MOCK_CRONTAB = ();  # simulated crontab lines

{
    no warnings 'redefine';

    *HBPerl::Scheduler::_read_crontab = sub { return @MOCK_CRONTAB };

    *HBPerl::Scheduler::_write_crontab = sub {
        my @lines = @_;
        @MOCK_CRONTAB = @lines;
    };

    # Mock _hbperl_cli_path so we don't need the binary present
    *HBPerl::Scheduler::_hbperl_cli_path = sub { '/usr/local/bin/hb_perl_cli' };
}

# ── Helper to reset state ─────────────────────────────────────────────────────
sub reset_crontab { @MOCK_CRONTAB = () }

# ── 1. add_job() basic add ────────────────────────────────────────────────────
{
    reset_crontab();
    HBPerl::Scheduler::add_job(script => 'system_info', schedule => '0 * * * *');
    is scalar @MOCK_CRONTAB, 1, 'add_job() adds one crontab line';
    like $MOCK_CRONTAB[0], qr/0 \* \* \* \*/, 'line contains cron schedule';
    like $MOCK_CRONTAB[0], qr/system_info/,    'line references the script name';
    like $MOCK_CRONTAB[0], qr/hbperl-job/,     'line has HB Perl marker';
}

# ── 2. add_job() with extra args ──────────────────────────────────────────────
{
    reset_crontab();
    HBPerl::Scheduler::add_job(
        script   => 'port_scanner',
        schedule => '30 2 * * *',
        args     => '--host 127.0.0.1',
    );
    like $MOCK_CRONTAB[0], qr/--host 127\.0\.0\.1/, 'extra args appear in crontab line';
}

# ── 3. Duplicate job is rejected ─────────────────────────────────────────────
{
    reset_crontab();
    HBPerl::Scheduler::add_job(script => 'disk_usage', schedule => '0 6 * * *');
    dies_ok {
        HBPerl::Scheduler::add_job(script => 'disk_usage', schedule => '0 12 * * *');
    } 'add_job() dies when script is already scheduled';
}

# ── 4. list_jobs() returns job info ──────────────────────────────────────────
{
    reset_crontab();
    HBPerl::Scheduler::add_job(script => 'disk_usage',   schedule => '0 6 * * *');
    HBPerl::Scheduler::add_job(script => 'service_monitor', schedule => '*/5 * * * *');
    my @jobs = HBPerl::Scheduler::list_jobs();
    is scalar @jobs, 2, 'list_jobs() returns 2 jobs';

    my ($dj) = grep { $_->{script} eq 'disk_usage' } @jobs;
    ok defined $dj, 'disk_usage job found';
    like $dj->{schedule}, qr/0 6/, 'schedule field is set';

    my ($smj) = grep { $_->{script} eq 'service_monitor' } @jobs;
    ok defined $smj, 'service_monitor job found';
}

# ── 5. remove_job() removes matching entry ───────────────────────────────────
{
    reset_crontab();
    HBPerl::Scheduler::add_job(script => 'log_analyzer', schedule => '0 * * * *');
    HBPerl::Scheduler::add_job(script => 'user_audit',   schedule => '0 0 * * *');
    is scalar @MOCK_CRONTAB, 2, 'two jobs added';

    my $removed = HBPerl::Scheduler::remove_job('log_analyzer');
    is $removed, 1, 'remove_job() returns 1 on success';
    is scalar @MOCK_CRONTAB, 1, 'one job remains after remove';
    unlike $MOCK_CRONTAB[0], qr/log_analyzer/, 'log_analyzer is gone from crontab';
    like   $MOCK_CRONTAB[0], qr/user_audit/,   'user_audit is still present';
}

# ── 6. remove_job() returns 0 when not found ─────────────────────────────────
{
    reset_crontab();
    my $removed = HBPerl::Scheduler::remove_job('nonexistent_script');
    is $removed, 0, 'remove_job() returns 0 when script not in crontab';
}

# ── 7. Invalid script name is rejected ───────────────────────────────────────
{
    reset_crontab();
    dies_ok {
        HBPerl::Scheduler::add_job(script => '../../../etc/cron.d/evil', schedule => '* * * * *');
    } 'add_job() dies on path-traversal script name';

    dies_ok {
        HBPerl::Scheduler::add_job(script => 'foo;rm -rf /', schedule => '* * * * *');
    } 'add_job() dies on shell-injection script name';
}

# ── 8. Invalid cron expression is rejected ───────────────────────────────────
{
    reset_crontab();
    dies_ok {
        HBPerl::Scheduler::add_job(script => 'disk_usage', schedule => '@reboot');
    } 'add_job() dies on @-style cron expression (not 5 fields)';

    dies_ok {
        HBPerl::Scheduler::add_job(script => 'disk_usage', schedule => '* * * *');
    } 'add_job() dies on 4-field cron expression';
}

# ── 9. Non-HB-Perl crontab lines are preserved ───────────────────────────────
{
    reset_crontab();
    @MOCK_CRONTAB = (
        '# User crontab',
        '0 3 * * * /usr/local/bin/backup.sh',
    );
    HBPerl::Scheduler::add_job(script => 'disk_usage', schedule => '0 6 * * *');
    is scalar @MOCK_CRONTAB, 3, 'existing crontab lines preserved after add_job()';
    is $MOCK_CRONTAB[0], '# User crontab', 'user comment line preserved';
    is $MOCK_CRONTAB[1], '0 3 * * * /usr/local/bin/backup.sh', 'user job preserved';

    HBPerl::Scheduler::remove_job('disk_usage');
    is scalar @MOCK_CRONTAB, 2, 'only HB Perl job removed, user lines intact';
}

# ── 10. list_jobs() returns empty list when no hbperl jobs ───────────────────
{
    @MOCK_CRONTAB = ('0 3 * * * /usr/local/bin/backup.sh');
    my @jobs = HBPerl::Scheduler::list_jobs();
    is scalar @jobs, 0, 'list_jobs() returns empty list when no hbperl jobs';
}

done_testing();
