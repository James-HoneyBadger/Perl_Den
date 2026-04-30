#!/usr/bin/env perl
# systemd_analyzer.pl — Systemd boot time and unit analysis
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use BadgerOps::Scripts::SystemdAnalyzer;

my $result = BadgerOps::Scripts::SystemdAnalyzer::run();
print BadgerOps::Scripts::SystemdAnalyzer::format_report($result);
