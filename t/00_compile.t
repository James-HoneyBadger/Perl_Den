#!/usr/bin/env perl
# ============================================================================
# t/00_compile.t — Verify all modules compile without errors
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

my @modules = qw(
    BadgerOps::Config
    BadgerOps::Util
    BadgerOps::Runner
    BadgerOps::BatchRunner
    BadgerOps::ScriptRegistry
    BadgerOps::Git
    BadgerOps::Scheduler
    BadgerOps::Scripts::SystemInfo
    BadgerOps::Scripts::DiskUsage
    BadgerOps::Scripts::ProcessManager
    BadgerOps::Scripts::ServiceMonitor
    BadgerOps::Scripts::FilePermissions
    BadgerOps::Scripts::LogAnalyzer
    BadgerOps::Scripts::UserAudit
    BadgerOps::Scripts::NetworkDiag
    BadgerOps::Scripts::PortScanner
    BadgerOps::Scripts::BackupManager
    BadgerOps::Scripts::DuplicateFinder
    BadgerOps::Scripts::CronManager
    BadgerOps::Scripts::SSLChecker
    BadgerOps::Scripts::ConfigDiff
    BadgerOps::Scripts::FailedLoginDetector
    BadgerOps::Scripts::DockerMonitor
    BadgerOps::Scripts::BandwidthMonitor
    BadgerOps::Scripts::FirewallAuditor
    BadgerOps::Scripts::PackageAuditor
    BadgerOps::Scripts::SystemdAnalyzer
);

plan tests => scalar @modules;

for my $mod (@modules) {
    use_ok($mod) or BAIL_OUT("Cannot load $mod");
}
