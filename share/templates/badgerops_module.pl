#!/usr/bin/env perl
# Name: My Custom Script
# Description: Brief description of what this script does
# ============================================================================
# BadgerOps Module Script Template
#
# This template follows the BadgerOps script convention:
#   - run(%args)        → collects data, returns a hashref
#   - format_report($r) → formats the hashref as a human-readable string
#
# To register as a user script, save to: ~/.config/badgerops/scripts/
# The first "# Name:" and "# Description:" comments are used in the IDE.
# ============================================================================
use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

# ── Main ──
my $result = run();
print format_report($result);

# ── Data Collection ──
sub run {
    my (%args) = @_;
    my %result;

    # TODO: Replace with your data collection logic
    $result{hostname} = `hostname 2>/dev/null` // 'unknown';
    chomp $result{hostname};

    $result{items} = [
        { name => 'Example Item 1', value => 42 },
        { name => 'Example Item 2', value => 99 },
    ];

    $result{timestamp} = scalar localtime;

    return \%result;
}

# ── Report Formatting ──
sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                   MY CUSTOM REPORT                           ║
╚══════════════════════════════════════════════════════════════╝

EOF

    $report .= "  Host: " . ($result->{hostname} // '?') . "\n";
    $report .= "  Time: " . ($result->{timestamp} // '?') . "\n\n";

    $report .= "── Results ───────────────────────────────────────────────────\n";
    $report .= sprintf("  %-30s %s\n", 'Name', 'Value');
    $report .= "  " . ("-" x 40) . "\n";

    for my $item (@{$result->{items} // []}) {
        $report .= sprintf("  %-30s %s\n", $item->{name}, $item->{value});
    }

    $report .= "\n  Total items: " . scalar(@{$result->{items} // []}) . "\n";

    return $report;
}
