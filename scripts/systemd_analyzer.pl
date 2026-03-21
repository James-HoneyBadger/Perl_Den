#!/usr/bin/env perl
# systemd_analyzer.pl — Systemd boot time and unit analysis
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use HBPerl::Scripts::SystemdAnalyzer;

my $result = HBPerl::Scripts::SystemdAnalyzer::run();
print HBPerl::Scripts::SystemdAnalyzer::format_report($result);
