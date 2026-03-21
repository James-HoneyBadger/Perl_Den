package HBPerl::Scripts::SystemdAnalyzer;
# ============================================================================
# SystemdAnalyzer — boot time analysis, failed units deep dive
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my %result;

    $result{available} = _systemd_available();
    return \%result unless $result{available};

    $result{boot_time}    = _get_boot_time();
    $result{blame}        = _get_blame();
    $result{failed_units} = _get_failed_units();
    $result{timers}       = _get_active_timers();
    $result{unit_count}   = _get_unit_counts();

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                 SYSTEMD ANALYZER REPORT                      ║
╚══════════════════════════════════════════════════════════════╝

EOF

    unless ($result->{available}) {
        $report .= "  ⚠ systemd is not available on this system.\n";
        return $report;
    }

    # Boot time
    $report .= "── Boot Time Analysis ────────────────────────────────────────\n";
    if ($result->{boot_time}) {
        $report .= "  $_\n" for @{$result->{boot_time}};
    }

    # Unit counts
    $report .= "\n── Unit Summary ──────────────────────────────────────────────\n";
    my $uc = $result->{unit_count} // {};
    $report .= sprintf("  Loaded: %-6s  Active: %-6s  Failed: %s\n",
        $uc->{loaded} // '?', $uc->{active} // '?', $uc->{failed} // '?');

    # Blame (slowest units)
    $report .= "\n── Slowest Boot Units (systemd-analyze blame) ─────────────────\n";
    $report .= sprintf("  %10s  %s\n", 'Time', 'Unit');
    $report .= "  " . ("-" x 50) . "\n";
    for my $b (@{$result->{blame} // []}[0 .. 14]) {
        last unless $b;
        $report .= sprintf("  %10s  %s\n", $b->{time}, $b->{unit});
    }

    # Failed units
    $report .= "\n── Failed Units ──────────────────────────────────────────────\n";
    my @failed = @{$result->{failed_units} // []};
    if (@failed) {
        for my $f (@failed) {
            $report .= sprintf("  ✗ %-40s %s\n", $f->{unit}, $f->{reason} // '');
        }
        $report .= "\n  ⚑ Run: systemctl status <unit> for details.\n";
    } else {
        $report .= "  No failed units. ✓\n";
    }

    # Active timers
    $report .= "\n── Active Timers ─────────────────────────────────────────────\n";
    my @timers = @{$result->{timers} // []};
    if (@timers) {
        $report .= sprintf("  %-30s %-20s %s\n", 'Timer', 'Next Run', 'Unit');
        $report .= "  " . ("-" x 70) . "\n";
        $report .= sprintf("  %-30s %-20s %s\n", $_->{timer}, $_->{next} // '-', $_->{activates} // '-')
            for @timers;
    } else {
        $report .= "  No active timers found.\n";
    }

    return $report;
}

# ── Internal helpers ──

sub _systemd_available {
    my $out = '';
    if (open my $fh, '-|', 'which', 'systemctl') {
        $out = <$fh> // '';
        chomp $out;
        close $fh;
    }
    return ($out && -x $out) ? 1 : 0;
}

sub _get_boot_time {
    my $out = '';
    if (open my $fh, '-|', 'systemd-analyze') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    return [ grep { length } split /\n/, $out ];
}

sub _get_blame {
    my @blame;
    my $out = '';
    if (open my $fh, '-|', 'systemd-analyze', 'blame') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    for my $line (split /\n/, $out) {
        if ($line =~ /^\s*(\S+)\s+(.+)$/) {
            push @blame, { time => $1, unit => $2 };
        }
    }
    return \@blame;
}

sub _get_failed_units {
    my @failed;
    my $out = '';
    if (open my $fh, '-|', 'systemctl', '--failed', '--no-legend', '--plain') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    for my $line (split /\n/, $out) {
        next unless $line =~ /\S/;
        my @parts = split /\s+/, $line;
        next unless @parts >= 1;
        push @failed, {
            unit   => $parts[0],
            reason => (@parts >= 4) ? $parts[3] : '',
        };
    }
    return \@failed;
}

sub _get_active_timers {
    my @timers;
    my $out = '';
    if (open my $fh, '-|', 'systemctl', 'list-timers', '--no-legend', '--plain') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    for my $line (split /\n/, $out) {
        next unless $line =~ /\S/;
        my @parts = split /\s{2,}/, $line;
        next unless @parts >= 2;
        push @timers, {
            next      => $parts[0] // '-',
            timer     => $parts[-2] // '-',
            activates => $parts[-1] // '-',
        };
    }
    return \@timers;
}

sub _get_unit_counts {
    my %counts;
    my $out = '';
    if (open my $fh, '-|', 'systemctl', 'list-units', '--no-legend', '--plain') {
        local $/;
        $out = <$fh> // '';
        close $fh;
    }
    my @lines = split /\n/, $out;
    $counts{loaded} = scalar @lines;

    my @active = grep { /\bactive\b/ } @lines;
    $counts{active} = scalar @active;

    my $failed = '';
    if (open my $fh, '-|', 'systemctl', '--failed', '--no-legend', '--plain') {
        local $/;
        $failed = <$fh> // '';
        close $fh;
    }
    my @flines = grep { /\S/ } split /\n/, $failed;
    $counts{failed} = scalar @flines;

    return \%counts;
}

1;

__END__

=head1 NAME

HBPerl::Scripts::SystemdAnalyzer - Systemd boot time and unit analysis

=head1 DESCRIPTION

Uses C<systemd-analyze> and C<systemctl> to report boot times, identify
the slowest-starting units, list failed units, and show active timers.

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
