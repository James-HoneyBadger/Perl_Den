#!/usr/bin/env perl
# ============================================================================
# log_analyzer.pl — Analyse system logs
# Usage: log_analyzer.pl [--lines N] [--pattern REGEX] [--source auto|syslog|journal]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use HBPerl::Scripts::LogAnalyzer;

my $lines   = 1000;
my $pattern = '';
my $source  = 'auto';
my $help;

GetOptions(
    'lines=i'   => \$lines,
    'pattern=s'  => \$pattern,
    'source=s'   => \$source,
    'help|h'     => \$help,
) or die "Usage: $0 [--lines N] [--pattern REGEX] [--source auto|syslog|journal]\n";

if ($help) {
    print "Usage: $0 [--lines N] [--pattern REGEX] [--source auto|syslog|journal]\n";
    print "Parse and analyze system logs.\n";
    exit 0;
}

my $result = HBPerl::Scripts::LogAnalyzer::run(
    max_lines => $lines,
    pattern   => $pattern,
    source    => $source,
);
print HBPerl::Scripts::LogAnalyzer::format_report($result);
