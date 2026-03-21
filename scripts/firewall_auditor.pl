#!/usr/bin/env perl
# firewall_auditor.pl — Dump and analyze iptables/nftables rules
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use HBPerl::Scripts::FirewallAuditor;

my $result = HBPerl::Scripts::FirewallAuditor::run();
print HBPerl::Scripts::FirewallAuditor::format_report($result);
