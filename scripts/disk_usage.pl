#!/usr/bin/env perl
# ============================================================================
# disk_usage.pl — Analyse disk usage for a given directory
# Usage: disk_usage.pl [directory] [--depth N] [--min-size N] [--top N]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use HBPerl::Scripts::DiskUsage;

my $dir       = shift @ARGV // '.';
my $depth     = 3;
my $min_size  = 1_048_576;
my $top       = 20;
my $help;

GetOptions(
    'depth=i'    => \$depth,
    'min-size=i' => \$min_size,
    'top=i'      => \$top,
    'help|h'     => \$help,
) or die "Usage: $0 [dir] [--depth N] [--min-size N] [--top N]\n";

if ($help) {
    print "Usage: $0 [dir] [--depth N] [--min-size N] [--top N]\n";
    print "Analyze disk usage by directory.\n";
    exit 0;
}

my $result = HBPerl::Scripts::DiskUsage::run(
    target    => $dir,
    max_depth => $depth,
    min_size  => $min_size,
    top_n     => $top,
);
print HBPerl::Scripts::DiskUsage::format_report($result);
