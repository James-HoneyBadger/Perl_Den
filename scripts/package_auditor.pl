#!/usr/bin/env perl
# package_auditor.pl — System package auditing
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use HBPerl::Scripts::PackageAuditor;

my $result = HBPerl::Scripts::PackageAuditor::run();
print HBPerl::Scripts::PackageAuditor::format_report($result);
