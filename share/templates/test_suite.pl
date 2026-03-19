#!/usr/bin/env perl
# ============================================================================
# Template: Test Suite
# Description: A comprehensive test file using Test::More
# ============================================================================
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir tempfile);

# ── Plan ───────────────────────────────────────────────────
# Use 'plan tests => N' for fixed count, or 'done_testing' at end
# plan tests => 10;

# ── Load Module ────────────────────────────────────────────
BEGIN { use_ok('My::Module') }

# ── Constructor Tests ──────────────────────────────────────
subtest 'Constructor' => sub {
    my $obj = My::Module->new(name => 'test');
    isa_ok($obj, 'My::Module', 'Object created correctly');
    is($obj->name, 'test', 'Name attribute set');
};

# ── Method Tests ───────────────────────────────────────────
subtest 'Greet method' => sub {
    my $obj = My::Module->new(name => 'World');
    like($obj->greet(), qr/World/, 'Greeting contains name');
};

subtest 'Process method' => sub {
    my $obj = My::Module->new();
    is($obj->process('hello'), 'HELLO', 'Processing works');
    eval { $obj->process(undef) };
    like($@, qr/No data/, 'Dies on undef input');
};

# ── Edge Cases ─────────────────────────────────────────────
subtest 'Edge cases' => sub {
    my $obj = My::Module->new();
    is($obj->process(''), '', 'Empty string OK');
    is($obj->process('123'), '123', 'Numbers pass through');
};

# ── File I/O Tests (example with temp files) ──────────────
subtest 'File operations' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my ($fh, $filename) = tempfile(DIR => $dir, SUFFIX => '.txt');
    print $fh "test data\n";
    close $fh;

    ok(-f $filename, 'Temp file created');
    open my $rfh, '<', $filename or die $!;
    my $content = <$rfh>;
    close $rfh;
    is($content, "test data\n", 'File content matches');
};

# ── Cleanup ────────────────────────────────────────────────
done_testing();
