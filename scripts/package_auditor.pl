#!/usr/bin/env perl
# package_auditor.pl — System package auditing
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use PerlDen::Scripts::PackageAuditor;

my $result = PerlDen::Scripts::PackageAuditor::run();
print PerlDen::Scripts::PackageAuditor::format_report($result);
