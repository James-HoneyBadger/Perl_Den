#!/usr/bin/env perl
# ============================================================================
# Template: File Processing Script
# Description: Read, transform, and write files with error handling
# ============================================================================
use strict;
use warnings;
use File::Basename;
use Getopt::Long;

my $input;
my $output;
my $in_place = 0;

GetOptions(
    'input|i=s'  => \$input,
    'output|o=s' => \$output,
    'in-place'   => \$in_place,
) or die "Usage: $0 -i INPUT [-o OUTPUT | --in-place]\n";

die "Input file required\n" unless $input;
die "File not found: $input\n" unless -f $input;

# ── Read ───────────────────────────────────────────────────
open my $fh_in, '<', $input or die "Cannot open $input: $!\n";
my @lines = <$fh_in>;
close $fh_in;

# ── Transform ─────────────────────────────────────────────
my @processed;
my $line_num = 0;
for my $line (@lines) {
    $line_num++;
    chomp $line;

    # TODO: Add your transformation logic here
    # Example: convert to uppercase
    $line = uc($line);

    push @processed, "$line\n";
}

# ── Write ──────────────────────────────────────────────────
my $dest = $in_place ? $input : ($output // '-');
if ($dest eq '-') {
    print @processed;
} else {
    open my $fh_out, '>', $dest or die "Cannot write $dest: $!\n";
    print $fh_out @processed;
    close $fh_out;
    print STDERR "Wrote $line_num lines to $dest\n";
}
