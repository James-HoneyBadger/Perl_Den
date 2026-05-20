#!/usr/bin/env perl
# ============================================================================
# failed_login_detector.pl — Detect brute-force login attempts
# Usage: failed_login_detector.pl [--hours N] [--threshold N]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PerlDen::Scripts::FailedLoginDetector;

my $hours     = 24;
my $threshold = 5;
my $help;

GetOptions(
    'hours=i'     => \$hours,
    'threshold=i' => \$threshold,
    'help|h'      => \$help,
) or die "Usage: $0 [--hours N] [--threshold N]\n";

if ($help) {
    print "Usage: $0 [--hours N] [--threshold N]\n";
    print "Detect brute-force login attempts from auth logs.\n";
    exit 0;
}

my $result = PerlDen::Scripts::FailedLoginDetector::run(
    hours     => $hours,
    threshold => $threshold,
);
print PerlDen::Scripts::FailedLoginDetector::format_report($result);
