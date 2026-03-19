#!/usr/bin/env perl
# ============================================================================
# t/19_runner.t — Test HBPerl::Runner (synchronous mode)
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

# Runner requires Glib — skip if not available
eval { require Glib };
if ($@) {
    plan skip_all => 'Glib not available';
}

use_ok('HBPerl::Runner');

subtest 'constructor' => sub {
    my $runner = HBPerl::Runner->new();
    ok($runner, 'created runner');
    ok(!$runner->is_running, 'not running initially');
};

subtest 'constructor with callbacks' => sub {
    my @out;
    my $runner = HBPerl::Runner->new(
        on_stdout => sub { push @out, $_[0] },
        on_stderr => sub {},
        on_exit   => sub {},
    );
    ok($runner, 'created runner with callbacks');
};

subtest 'run_sync captures stdout' => sub {
    my ($stdout, $stderr, $exit) = HBPerl::Runner->run_sync('echo', 'hello world');
    chomp $stdout;
    is($stdout, 'hello world', 'stdout captured');
    is($exit, 0, 'exit code 0');
};

subtest 'run_sync captures stderr' => sub {
    my ($stdout, $stderr, $exit) = HBPerl::Runner->run_sync(
        'bash', '-c', 'echo err >&2'
    );
    like($stderr, qr/err/, 'stderr captured');
};

subtest 'run_sync returns exit code' => sub {
    my ($stdout, $stderr, $exit) = HBPerl::Runner->run_sync('false');
    isnt($exit, 0, 'non-zero exit code for false');
};

subtest 'run_sync single string fallback' => sub {
    my ($stdout, $stderr, $exit) = HBPerl::Runner->run_sync('echo single_string_mode');
    like($stdout, qr/single_string_mode/, 'single string mode works via bash -c');
};

subtest 'run_sync with perl one-liner' => sub {
    my ($stdout, $stderr, $exit) = HBPerl::Runner->run_sync(
        'perl', '-e', 'print "42\n"'
    );
    chomp $stdout;
    is($stdout, '42', 'perl one-liner output captured');
    is($exit, 0, 'perl one-liner exits cleanly');
};

done_testing();
