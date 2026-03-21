#!/usr/bin/env perl
# bandwidth_monitor.pl — Per-interface network traffic monitoring
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use HBPerl::Scripts::BandwidthMonitor;

my $result = HBPerl::Scripts::BandwidthMonitor::run(interval => 2);
print HBPerl::Scripts::BandwidthMonitor::format_report($result);
