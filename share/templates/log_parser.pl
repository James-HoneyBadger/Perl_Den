#!/usr/bin/env perl
# ============================================================================
# Template: Log Parser / Report Generator
# Description: Parse structured or unstructured logs and generate reports
# ============================================================================
use strict;
use warnings;
use Getopt::Long;
use POSIX qw(strftime);

my $logfile;
my $pattern = '';
my $top_n   = 20;
my $output  = '-';

GetOptions(
    'file|f=s'    => \$logfile,
    'pattern|p=s' => \$pattern,
    'top=i'       => \$top_n,
    'output|o=s'  => \$output,
) or die "Usage: $0 --file LOGFILE [--pattern REGEX] [--top N] [--output FILE]\n";

die "Log file required (--file)\n" unless $logfile;
die "File not found: $logfile\n"   unless -f $logfile;

# ── Parse ──────────────────────────────────────────────────
my (%counts, %by_hour, @errors, $total);

open my $fh, '<', $logfile or die "Cannot open $logfile: $!\n";
while (my $line = <$fh>) {
    chomp $line;
    $total++;

    # Skip if pattern specified and doesn't match
    next if $pattern && $line !~ /$pattern/i;

    # TODO: Customise parsing for your log format
    # Example: syslog format "Mon DD HH:MM:SS host service[pid]: message"
    if ($line =~ /^(\w{3}\s+\d+\s+(\d+):\d+:\d+)\s+\S+\s+(\S+?)(?:\[\d+\])?:\s+(.*)/) {
        my ($timestamp, $hour, $source, $message) = ($1, $2, $3, $4);
        $counts{$source}++;
        $by_hour{$hour}++;

        # Detect errors
        if ($message =~ /error|fail|critical|panic/i) {
            push @errors, { time => $timestamp, source => $source, msg => $message };
        }
    }
}
close $fh;

# ── Report ─────────────────────────────────────────────────
my $report = '';
$report .= "=" x 60 . "\n";
$report .= "  LOG ANALYSIS REPORT\n";
$report .= "  File: $logfile\n";
$report .= "  Total lines: $total\n";
$report .= "  Generated: " . strftime('%Y-%m-%d %H:%M:%S', localtime()) . "\n";
$report .= "=" x 60 . "\n\n";

# Top sources
$report .= "Top Sources:\n";
my $n = 0;
for my $src (sort { $counts{$b} <=> $counts{$a} } keys %counts) {
    last if ++$n > $top_n;
    $report .= sprintf("  %-30s %d\n", $src, $counts{$src});
}

# Hourly distribution
$report .= "\nHourly Distribution:\n";
for my $h (sort keys %by_hour) {
    my $bar = '█' x int($by_hour{$h} / (($total / 24) || 1) * 20);
    $report .= sprintf("  %02d:00  %5d  %s\n", $h, $by_hour{$h}, $bar);
}

# Errors
$report .= sprintf("\nErrors Found: %d\n", scalar @errors);
for my $e (splice @errors, 0, 20) {
    $report .= "  [$e->{time}] $e->{source}: $e->{msg}\n";
}

# ── Output ─────────────────────────────────────────────────
if ($output eq '-') {
    print $report;
} else {
    open my $ofh, '>', $output or die "Cannot write $output: $!\n";
    print $ofh $report;
    close $ofh;
    print "Report written to $output\n";
}
