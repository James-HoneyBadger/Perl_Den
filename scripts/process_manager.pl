#!/usr/bin/env perl
# ============================================================================
# process_manager.pl — List and analyse running processes
# Usage: process_manager.pl [--sort cpu|mem|pid|rss] [--top N]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use HBPerl::Scripts::ProcessManager;

my $sort_by = 'cpu';
my $top     = 25;
my $help;

GetOptions(
    'sort=s' => \$sort_by,
    'top=i'  => \$top,
    'help|h' => \$help,
) or die "Usage: $0 [--sort cpu|mem|pid|rss] [--top N]\n";

if ($help) {
    print "Usage: $0 [--sort cpu|mem|pid|rss] [--top N]\n";
    print "List and analyse running processes.\n";
    exit 0;
}

my $result = HBPerl::Scripts::ProcessManager::run(
    sort_by => $sort_by,
    top_n   => $top,
);
print HBPerl::Scripts::ProcessManager::format_report($result);
