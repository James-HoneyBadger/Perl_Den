#!/usr/bin/env perl
# ============================================================================
# t/06_service_monitor.t — Test HBPerl::Scripts::ServiceMonitor
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('HBPerl::Scripts::ServiceMonitor');

subtest 'run returns service data' => sub {
    my $result = HBPerl::Scripts::ServiceMonitor::run();
    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{services}, 'has services key');
    ok(ref $result->{services} eq 'ARRAY', 'services is array');
    ok(exists $result->{total}, 'has total count');
};

subtest 'format_report works' => sub {
    my $r = HBPerl::Scripts::ServiceMonitor::run();
    my $report = HBPerl::Scripts::ServiceMonitor::format_report($r);
    ok(length($report) > 20, 'report has content');
};

done_testing();
