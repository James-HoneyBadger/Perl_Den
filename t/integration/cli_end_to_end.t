#!/usr/bin/env perl
# ============================================================================
# t/integration/cli_end_to_end.t — CLI launcher integration tests
# Tests: badgerops-cli --list, --run system_info, --help
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";

my $cli = "$FindBin::Bin/../../bin/badgerops-cli";

SKIP: {
    skip "CLI launcher not found at $cli", 6 unless -f $cli;

    subtest 'cli help exits cleanly' => sub {
        my $out = `perl $cli help 2>&1`;
        is($? >> 8, 0, 'exit code 0');
        like($out, qr/usage|help|hbperl/i, 'help text shown');
    };

    subtest 'cli list shows scripts' => sub {
        my $out = `perl $cli list 2>&1`;
        is($? >> 8, 0, 'exit code 0');
        like($out, qr/system.?info/i, 'lists system_info script');
    };

    subtest 'cli run system_info produces output' => sub {
        my $out = `perl $cli run system_info 2>&1`;
        is($? >> 8, 0, 'exit code 0');
        like($out, qr/system information|hostname/i, 'produces report');
    };
}

done_testing();
