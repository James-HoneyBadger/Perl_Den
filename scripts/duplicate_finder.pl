#!/usr/bin/env perl
# ============================================================================
# duplicate_finder.pl — Find duplicate files by content hash
# Usage: duplicate_finder.pl [directory] [--min-size N] [--max-depth N]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PerlDen::Scripts::DuplicateFinder;

my $min_size  = 1;
my $max_depth;
my $help;

GetOptions(
    'min-size=i'  => \$min_size,
    'max-depth=i' => \$max_depth,
    'help|h'      => \$help,
) or die "Usage: $0 [dir] [--min-size N] [--max-depth N]\n";

if ($help) {
    print "Usage: $0 [dir] [--min-size N] [--max-depth N]\n";
    print "Find duplicate files by content hash.\n";
    exit 0;
}

my $dir = shift @ARGV // '.';

my $result = PerlDen::Scripts::DuplicateFinder::run(
    directory => $dir,
    min_size  => $min_size,
    max_depth => $max_depth,
);
print PerlDen::Scripts::DuplicateFinder::format_report($result);
