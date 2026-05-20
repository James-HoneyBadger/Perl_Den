#!/usr/bin/env perl
# systemd_analyzer.pl — Systemd boot time and unit analysis
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use PerlDen::Scripts::SystemdAnalyzer;

my $result = PerlDen::Scripts::SystemdAnalyzer::run();
print PerlDen::Scripts::SystemdAnalyzer::format_report($result);
