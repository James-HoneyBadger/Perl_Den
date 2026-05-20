#!/usr/bin/env perl
# ============================================================================
# t/13_failed_login.t — Test PerlDen::Scripts::FailedLoginDetector
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('PerlDen::Scripts::FailedLoginDetector');

SKIP: {
    my $has_log = -f '/var/log/auth.log' || -f '/var/log/secure'
                  || -d '/var/log/journal';
    skip 'No auth log files accessible', 8 unless $has_log;

subtest 'run returns expected structure' => sub {
    my $result = PerlDen::Scripts::FailedLoginDetector::run(hours => 1);
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{total_failed}, 'has total_failed');
    ok(exists $result->{total_success}, 'has total_success');
    ok(exists $result->{flagged_ips}, 'has flagged_ips');
    ok(exists $result->{flagged_users}, 'has flagged_users');
    ok(ref $result->{flagged_ips} eq 'ARRAY', 'flagged_ips is array');
};

subtest 'format_report works' => sub {
    my $r = PerlDen::Scripts::FailedLoginDetector::run(hours => 1);
    my $report = PerlDen::Scripts::FailedLoginDetector::format_report($r);
    ok(length($report) > 50, 'report has content');
    like($report, qr/FAILED LOGIN|BRUTE/i, 'has relevant header');
};

} # end SKIP

done_testing();
