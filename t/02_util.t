#!/usr/bin/env perl
# ============================================================================
# t/02_util.t — Test BadgerOps::Util
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('BadgerOps::Util');

subtest 'format_bytes' => sub {
    is(BadgerOps::Util::format_bytes(0), '0 B', 'zero bytes');
    is(BadgerOps::Util::format_bytes(512), '512 B', '512 bytes');
    is(BadgerOps::Util::format_bytes(1024), '1.0 KB', '1 KB');
    is(BadgerOps::Util::format_bytes(1536), '1.5 KB', '1.5 KB');
    is(BadgerOps::Util::format_bytes(1048576), '1.0 MB', '1 MB');
    is(BadgerOps::Util::format_bytes(1073741824), '1.0 GB', '1 GB');
};

subtest 'format_number' => sub {
    is(BadgerOps::Util::format_number(1000), '1,000', 'one thousand');
    is(BadgerOps::Util::format_number(1234567), '1,234,567', 'millions');
    is(BadgerOps::Util::format_number(42), '42', 'small number');
};

subtest 'trim' => sub {
    is(BadgerOps::Util::trim('  hello  '), 'hello', 'trims both sides');
    is(BadgerOps::Util::trim("  \t\n  "), '', 'all whitespace');
    is(BadgerOps::Util::trim('clean'), 'clean', 'already clean');
};

subtest 'timestamp' => sub {
    my $ts = BadgerOps::Util::timestamp();
    like($ts, qr/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/, 'valid timestamp format');
};

subtest 'run_command' => sub {
    my ($out, $rc) = BadgerOps::Util::run_command('echo hello');
    like($out, qr/hello/, 'captured output');
    is($rc, 0, 'zero exit code');

    my ($out2, $rc2) = BadgerOps::Util::run_command('false');
    isnt($rc2, 0, 'non-zero exit code on failure');
};

subtest 'is_root' => sub {
    my $root = BadgerOps::Util::is_root();
    if ($< == 0) {
        ok($root, 'correctly detects root');
    } else {
        ok(!$root, 'correctly detects non-root');
    }
};

done_testing();
