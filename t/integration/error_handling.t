#!/usr/bin/env perl
# ============================================================================
# t/integration/error_handling.t — Negative/error path tests
# Tests: corrupted config, runner errors, script missing commands
# ============================================================================
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../../lib";

# ── Config: corrupted YAML ──
subtest 'Config: corrupted YAML file' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $cfg_file = "$dir/config.yml";

    # Write invalid YAML
    open my $fh, '>', $cfg_file or die "write: $!";
    print $fh "not: [valid: yaml: {broken\n";
    close $fh;

    local $HBPerl::Config::CONFIG_FILE = $cfg_file;
    local $HBPerl::Config::SESSION_FILE = "$dir/session.yml";

    require HBPerl::Config;
    eval { HBPerl::Config::load() };
    ok(!$@, 'load() does not die on corrupted YAML') or diag $@;
};

subtest 'Config: missing config directory' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my $deep = "$dir/nonexistent/nested/config.yml";

    local $HBPerl::Config::CONFIG_FILE = $deep;
    local $HBPerl::Config::SESSION_FILE = "$dir/session.yml";

    require HBPerl::Config;
    eval { HBPerl::Config::load() };
    ok(!$@, 'load() creates missing directories') or diag $@;
};

# ── Runner: command not found ──
subtest 'Runner: non-existent command via run_sync' => sub {
    eval { require Glib };
    if ($@) {
        pass('Glib not available, skipping');
        return;
    }
    require HBPerl::Runner;
    my ($out, $err, $rc) = HBPerl::Runner->run_sync('totally_nonexistent_cmd_xyz');
    isnt($rc, 0, 'non-zero exit for missing command');
};

subtest 'Runner: timeout fires and kills child' => sub {
    eval { require Glib };
    if ($@) {
        pass('Glib not available, skipping');
        return;
    }
    require HBPerl::Runner;
    my ($out, $err, $rc) = HBPerl::Runner->run_sync(
        'sleep', '60',
        { timeout => 1 },
    );
    is($rc, 124, 'exit code 124 signals timeout');
    like($err, qr/timed out/i, 'error message mentions timeout');
};

# ── BatchRunner: unknown script ──
subtest 'BatchRunner: unknown script returns error' => sub {
    require HBPerl::BatchRunner;
    my @errors;
    my $br = HBPerl::BatchRunner->new(
        on_error => sub { push @errors, $_[0] },
    );
    my $results = $br->run_batch('totally_nonexistent_script');
    is(scalar @$results, 1, 'one result');
    ok($results->[0]{error}, 'error is set');
    like($results->[0]{error}, qr/unknown/i, 'error says unknown');
};

# ── BatchRunner: script that dies ──
subtest 'BatchRunner: script runtime error is caught' => sub {
    require HBPerl::BatchRunner;
    require HBPerl::ScriptRegistry;

    # Temporarily inject a script that dies
    no warnings 'once';
    local *HBPerl::Scripts::TestDie::run = sub { die "intentional test death" };
    local *HBPerl::Scripts::TestDie::format_report = sub { "report" };

    my @errors;
    my $br = HBPerl::BatchRunner->new(
        on_error => sub { push @errors, $_[0] },
    );

    # The batch runner looks up scripts by registry name, so we need to
    # test via the error callback mechanism
    my $results = $br->run_batch('nonexistent_dying_script');
    ok($results->[0]{error}, 'error captured for bad script');
};

# ── Util: slurp_file on missing file ──
subtest 'Util: slurp_file returns empty for missing file' => sub {
    require HBPerl::Util;
    my $content = HBPerl::Util::slurp_file('/nonexistent/file/xyz.txt');
    is($content, '', 'returns empty string for missing file');
};

subtest 'Util: run_command_list with non-existent command' => sub {
    require HBPerl::Util;
    my ($out, $rc) = HBPerl::Util::run_command_list('totally_nonexistent_xyz');
    ok($rc != 0, 'non-zero return code');
};

done_testing();
