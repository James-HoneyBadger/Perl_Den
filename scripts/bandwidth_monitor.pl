#!/usr/bin/env perl
# bandwidth_monitor.pl — Per-interface network traffic monitoring
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use PerlDen::Scripts::BandwidthMonitor;

my $result = PerlDen::Scripts::BandwidthMonitor::run(interval => 2);
print PerlDen::Scripts::BandwidthMonitor::format_report($result);
