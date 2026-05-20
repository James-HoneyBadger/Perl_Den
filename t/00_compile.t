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
    PerlDen::Config
    PerlDen::Util
    PerlDen::Runner
    PerlDen::BatchRunner
    PerlDen::ScriptRegistry
    PerlDen::Git
    PerlDen::Scheduler
    PerlDen::Scripts::SystemInfo
    PerlDen::Scripts::DiskUsage
    PerlDen::Scripts::ProcessManager
    PerlDen::Scripts::ServiceMonitor
    PerlDen::Scripts::FilePermissions
    PerlDen::Scripts::LogAnalyzer
    PerlDen::Scripts::UserAudit
    PerlDen::Scripts::NetworkDiag
    PerlDen::Scripts::PortScanner
    PerlDen::Scripts::BackupManager
    PerlDen::Scripts::DuplicateFinder
    PerlDen::Scripts::CronManager
    PerlDen::Scripts::SSLChecker
    PerlDen::Scripts::ConfigDiff
    PerlDen::Scripts::FailedLoginDetector
    PerlDen::Scripts::DockerMonitor
    PerlDen::Scripts::BandwidthMonitor
    PerlDen::Scripts::FirewallAuditor
    PerlDen::Scripts::PackageAuditor
    PerlDen::Scripts::SystemdAnalyzer
);

plan tests => scalar @modules;

for my $mod (@modules) {
    use_ok($mod) or BAIL_OUT("Cannot load $mod");
}
