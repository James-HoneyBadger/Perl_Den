#!/usr/bin/env perl
# bandwidth_monitor.pl — Per-interface network traffic monitoring
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use BadgerOps::Scripts::BandwidthMonitor;

my $result = BadgerOps::Scripts::BandwidthMonitor::run(interval => 2);
print BadgerOps::Scripts::BandwidthMonitor::format_report($result);
