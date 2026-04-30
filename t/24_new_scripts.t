#!/usr/bin/env perl
# t/24_new_scripts.t - Tests for Phase 5 scripts (deeper coverage)
use strict;
use warnings;
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

# ── FirewallAuditor ──
use_ok('BadgerOps::Scripts::FirewallAuditor');
can_ok('BadgerOps::Scripts::FirewallAuditor', qw(run format_report));
{
    my $result = BadgerOps::Scripts::FirewallAuditor::run();
    is(ref $result, 'HASH', 'FirewallAuditor::run returns hashref');
    ok(exists $result->{firewall_type}, 'result has firewall_type');
    like($result->{firewall_type}, qr/^(nftables|iptables|unknown)$/, 'firewall_type is valid');
    ok(exists $result->{iptables}, 'result has iptables key');
    ok(exists $result->{unmatched_ports}, 'result has unmatched_ports');
    is(ref($result->{unmatched_ports} // []), 'ARRAY', 'unmatched_ports is array');
    my $report = BadgerOps::Scripts::FirewallAuditor::format_report($result);
    like($report, qr/FIREWALL AUDIT/, 'report contains title');
    ok(length($report) > 50, 'report has substantial content');
}

# ── DockerMonitor ──
use_ok('BadgerOps::Scripts::DockerMonitor');
can_ok('BadgerOps::Scripts::DockerMonitor', qw(run format_report));
{
    my $result = BadgerOps::Scripts::DockerMonitor::run();
    is(ref $result, 'HASH', 'DockerMonitor::run returns hashref');
    ok(exists $result->{available}, 'result has available key');
    ok(exists $result->{containers}, 'result has containers key');
    ok(exists $result->{images}, 'result has images key');
    is(ref $result->{containers}, 'ARRAY', 'containers is array');
    is(ref $result->{images}, 'ARRAY', 'images is array');
    my $report = BadgerOps::Scripts::DockerMonitor::format_report($result);
    like($report, qr/DOCKER MONITOR/, 'report contains title');
    if (!$result->{available}) {
        like($report, qr/not available|not installed|not running/i,
             'report indicates docker unavailable');
    }
}

# ── BandwidthMonitor ──
use_ok('BadgerOps::Scripts::BandwidthMonitor');
can_ok('BadgerOps::Scripts::BandwidthMonitor', qw(run format_report));
SKIP: {
    skip 'No /proc/net/dev (non-Linux)', 6 unless -f '/proc/net/dev';
    my $result = BadgerOps::Scripts::BandwidthMonitor::run(interval => 0);
    is(ref $result, 'HASH', 'BandwidthMonitor::run returns hashref');
    ok(exists $result->{interfaces}, 'result has interfaces');
    is(ref $result->{interfaces}, 'ARRAY', 'interfaces is an array');
    ok(scalar @{$result->{interfaces}} > 0, 'at least one interface found');
    my $iface = $result->{interfaces}[0];
    ok(exists $iface->{name}, 'interface has name');
    my $report = BadgerOps::Scripts::BandwidthMonitor::format_report($result);
    like($report, qr/BANDWIDTH MONITOR/, 'report contains title');
}

# ── PackageAuditor ──
use_ok('BadgerOps::Scripts::PackageAuditor');
can_ok('BadgerOps::Scripts::PackageAuditor', qw(run format_report));
{
    my $result = BadgerOps::Scripts::PackageAuditor::run();
    is(ref $result, 'HASH', 'PackageAuditor::run returns hashref');
    ok(exists $result->{pkg_manager}, 'result has pkg_manager');
    like($result->{pkg_manager}, qr/^(dnf|apt|pacman|zypper|unknown)$/, 'valid pkg manager');
    ok(exists $result->{installed}, 'result has installed');
    ok(exists $result->{updates}, 'result has updates');
    is(ref $result->{updates}, 'ARRAY', 'updates is array');
    my $report = BadgerOps::Scripts::PackageAuditor::format_report($result);
    like($report, qr/PACKAGE AUDIT/, 'report contains title');
    ok(length($report) > 50, 'report has substantial content');
}

# ── SystemdAnalyzer ──
use_ok('BadgerOps::Scripts::SystemdAnalyzer');
can_ok('BadgerOps::Scripts::SystemdAnalyzer', qw(run format_report));
{
    my $result = BadgerOps::Scripts::SystemdAnalyzer::run();
    is(ref $result, 'HASH', 'SystemdAnalyzer::run returns hashref');
    ok(exists $result->{available}, 'result has available key');
    my $report = BadgerOps::Scripts::SystemdAnalyzer::format_report($result);
    like($report, qr/SYSTEMD ANALYZER/, 'report contains title');
    if ($result->{available}) {
        ok(exists $result->{boot_time}, 'has boot_time when available');
        ok(exists $result->{blame}, 'has blame when available');
        is(ref $result->{blame}, 'ARRAY', 'blame is array');
        ok(exists $result->{failed_units}, 'has failed_units');
        ok(exists $result->{unit_count}, 'has unit_count');
        is(ref $result->{unit_count}, 'HASH', 'unit_count is hash');
    }
}

done_testing();
