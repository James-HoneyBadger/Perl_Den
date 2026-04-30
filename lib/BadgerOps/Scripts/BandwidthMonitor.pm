package BadgerOps::Scripts::BandwidthMonitor;
# ============================================================================
# BandwidthMonitor — per-interface traffic stats from /proc/net/dev
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my $interval    = $args{interval}    // 2;    # seconds between samples
    my $run_timeout = $args{run_timeout} // 60;
    my %result;

    local $SIG{ALRM} = sub { die "BandwidthMonitor timed out after ${run_timeout}s\n" };
    alarm($run_timeout);

    # Take two readings to calculate rates
    my $t1 = _read_proc_net_dev();
    sleep($interval) if $interval > 0;
    my $t2 = _read_proc_net_dev();

    $result{interfaces} = [];
    for my $iface (sort keys %$t2) {
        my $prev = $t1->{$iface} // {};
        my $curr = $t2->{$iface};

        my $rx_bytes = $curr->{rx_bytes} - ($prev->{rx_bytes} // $curr->{rx_bytes});
        my $tx_bytes = $curr->{tx_bytes} - ($prev->{tx_bytes} // $curr->{tx_bytes});

        push @{$result{interfaces}}, {
            name       => $iface,
            rx_bytes   => $curr->{rx_bytes},
            tx_bytes   => $curr->{tx_bytes},
            rx_packets => $curr->{rx_packets},
            tx_packets => $curr->{tx_packets},
            rx_errors  => $curr->{rx_errors},
            tx_errors  => $curr->{tx_errors},
            rx_rate    => $interval > 0 ? $rx_bytes / $interval : 0,
            tx_rate    => $interval > 0 ? $tx_bytes / $interval : 0,
        };
    }

    $result{interval} = $interval;
    alarm(0);
    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                  BANDWIDTH MONITOR REPORT                    ║
╚══════════════════════════════════════════════════════════════╝

EOF

    $report .= sprintf("  Sample interval: %ds\n\n", $result->{interval} // 0);

    $report .= "── Interface Traffic ─────────────────────────────────────────\n";
    $report .= sprintf("  %-12s %12s %12s %10s %10s %8s %8s\n",
        'Interface', 'RX Total', 'TX Total', 'RX Rate', 'TX Rate', 'RX Err', 'TX Err');
    $report .= "  " . ("-" x 78) . "\n";

    for my $iface (@{$result->{interfaces} // []}) {
        $report .= sprintf("  %-12s %12s %12s %10s %10s %8d %8d\n",
            $iface->{name},
            _human_bytes($iface->{rx_bytes}),
            _human_bytes($iface->{tx_bytes}),
            _human_rate($iface->{rx_rate}),
            _human_rate($iface->{tx_rate}),
            $iface->{rx_errors} // 0,
            $iface->{tx_errors} // 0,
        );
    }

    my $total_rx = 0;
    my $total_tx = 0;
    for my $i (@{$result->{interfaces} // []}) {
        $total_rx += $i->{rx_bytes} // 0;
        $total_tx += $i->{tx_bytes} // 0;
    }
    $report .= "\n  Total RX: " . _human_bytes($total_rx) .
               "  Total TX: " . _human_bytes($total_tx) . "\n";

    return $report;
}

# ── Internal helpers ──

sub _read_proc_net_dev {
    my %interfaces;
    open my $fh, '<', '/proc/net/dev' or return {};
    while (<$fh>) {
        next unless /^\s*(\w+):\s*(.+)/;
        my $iface = $1;
        my @vals = split /\s+/, $2;
        $interfaces{$iface} = {
            rx_bytes   => $vals[0] // 0,
            rx_packets => $vals[1] // 0,
            rx_errors  => $vals[2] // 0,
            tx_bytes   => $vals[8] // 0,
            tx_packets => $vals[9] // 0,
            tx_errors  => $vals[10] // 0,
        };
    }
    close $fh;
    return \%interfaces;
}

sub _human_bytes {
    my ($bytes) = @_;
    $bytes //= 0;
    my @units = ('B', 'KB', 'MB', 'GB', 'TB');
    my $i = 0;
    my $val = $bytes;
    while ($val >= 1024 && $i < $#units) {
        $val /= 1024;
        $i++;
    }
    return sprintf("%.1f %s", $val, $units[$i]);
}

sub _human_rate {
    my ($bytes_per_sec) = @_;
    $bytes_per_sec //= 0;
    return _human_bytes($bytes_per_sec) . '/s';
}

sub metadata {
    return {
        name        => 'Bandwidth Monitor',
        filename    => 'bandwidth_monitor.pl',
        description => 'Per-interface network traffic rates',
        category    => 'Network',
        icon        => 'network-wired-symbolic',
        emoji       => '🌐',
        run_timeout => 60,
    };
}

1;

__END__

=head1 NAME

BadgerOps::Scripts::BandwidthMonitor - Per-interface network traffic monitoring

=head1 SYNOPSIS

    use BadgerOps::Scripts::BandwidthMonitor;
    my $result = BadgerOps::Scripts::BandwidthMonitor::run(interval => 2);
    print BadgerOps::Scripts::BandwidthMonitor::format_report($result);

=head1 DESCRIPTION

Reads C</proc/net/dev> twice with a configurable interval to calculate
per-interface receive/transmit rates, totals, and error counts.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Accepts optional C<interval =E<gt> $seconds> (default 2).  Samples
C</proc/net/dev> before and after sleeping for C<interval> seconds.

=item B<format_report($result)>

Formats the bandwidth data as a human-readable text table.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<interfaces>

Arrayref of interface hashrefs, each containing: C<name>, C<rx_bytes>,
C<tx_bytes>, C<rx_rate>, C<tx_rate>, C<rx_errors>, C<tx_errors>.

=item C<interval>

The sampling interval in seconds actually used.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
