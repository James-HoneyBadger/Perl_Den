#!/usr/bin/env perl
# package_auditor.pl — System package auditing
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use BadgerOps::Scripts::PackageAuditor;

my $result = BadgerOps::Scripts::PackageAuditor::run();
print BadgerOps::Scripts::PackageAuditor::format_report($result);
