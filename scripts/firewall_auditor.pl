#!/usr/bin/env perl
# firewall_auditor.pl — Dump and analyze iptables/nftables rules
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use PerlDen::Scripts::FirewallAuditor;

my $result = PerlDen::Scripts::FirewallAuditor::run();
print PerlDen::Scripts::FirewallAuditor::format_report($result);
