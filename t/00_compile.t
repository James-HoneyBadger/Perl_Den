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
    HBPerl::Config
    HBPerl::Util
    HBPerl::Runner
    HBPerl::ScriptRegistry
    HBPerl::Scripts::SystemInfo
    HBPerl::Scripts::DiskUsage
    HBPerl::Scripts::ProcessManager
    HBPerl::Scripts::ServiceMonitor
    HBPerl::Scripts::FilePermissions
    HBPerl::Scripts::LogAnalyzer
    HBPerl::Scripts::UserAudit
    HBPerl::Scripts::NetworkDiag
    HBPerl::Scripts::PortScanner
    HBPerl::Scripts::BackupManager
    HBPerl::Scripts::DuplicateFinder
    HBPerl::Scripts::CronManager
    HBPerl::Scripts::SSLChecker
    HBPerl::Scripts::ConfigDiff
    HBPerl::Scripts::FailedLoginDetector
);

plan tests => scalar @modules;

for my $mod (@modules) {
    use_ok($mod) or BAIL_OUT("Cannot load $mod");
}
