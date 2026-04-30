#!/usr/bin/env perl
# firewall_auditor.pl — Dump and analyze iptables/nftables rules
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use BadgerOps::Scripts::FirewallAuditor;

my $result = BadgerOps::Scripts::FirewallAuditor::run();
print BadgerOps::Scripts::FirewallAuditor::format_report($result);
