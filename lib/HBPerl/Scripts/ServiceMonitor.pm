package HBPerl::Scripts::ServiceMonitor;
# ============================================================================
# Monitor systemd services — status, failed, enabled/disabled
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my $filter = $args{filter} // '';

    my @services;
    my @failed;
    my @lines;
    if (open my $fh, '-|', 'systemctl', 'list-units', '--type=service', '--all', '--no-legend', '--no-pager') {
        @lines = <$fh>;
        close $fh;
    }

    for my $line (@lines) {
        $line =~ s/^\s+//;
        # Format: UNIT LOAD ACTIVE SUB DESCRIPTION
        my ($unit, $load, $active, $sub, $desc) = split /\s+/, $line, 5;
        next unless $unit;
        $unit =~ s/●\s*//;  # Remove bullet prefix

        if ($filter) {
            next unless $unit =~ /\Q$filter\E/i || ($desc // '') =~ /\Q$filter\E/i;
        }

        my $svc = {
            unit        => $unit,
            load_state  => $load // '',
            active      => $active // '',
            sub_state   => $sub // '',
            description => $desc // '',
        };
        push @services, $svc;
        push @failed, $svc if ($active // '') eq 'failed';
    }

    # Get enabled/disabled info
    my %enabled;
    my @enabled_lines;
    if (open my $fh, '-|', 'systemctl', 'list-unit-files', '--type=service', '--no-legend', '--no-pager') {
        @enabled_lines = <$fh>;
        close $fh;
    }
    for my $line (@enabled_lines) {
        $line =~ s/^\s+//;
        my ($unit, $state) = split /\s+/, $line;
        $enabled{$unit} = $state if $unit;
    }

    # Merge enabled status
    for my $svc (@services) {
        $svc->{enabled} = $enabled{$svc->{unit}} // 'unknown';
    }

    # Summary counts
    my %counts;
    for my $svc (@services) {
        $counts{$svc->{active}}++;
    }

    return {
        services => \@services,
        failed   => \@failed,
        counts   => \%counts,
        total    => scalar @services,
    };
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                    SERVICE MONITOR                           ║
╚══════════════════════════════════════════════════════════════╝

Total services: $result->{total}
EOF

    # Counts
    for my $state (sort keys %{$result->{counts}}) {
        $report .= "  $state: $result->{counts}{$state}\n";
    }

    # Failed services (highlight)
    if (@{$result->{failed}}) {
        $report .= "\n⚠  FAILED SERVICES (" . scalar(@{$result->{failed}}) . "):\n";
        for my $svc (@{$result->{failed}}) {
            $report .= "   ✗ $svc->{unit}  — $svc->{description}\n";
        }
    } else {
        $report .= "\n✓ No failed services\n";
    }

    # Full list
    $report .= "\n── Service List ──────────────────────────────────────────────\n";
    $report .= sprintf("  %-40s %-10s %-10s %-10s\n",
        'UNIT', 'ACTIVE', 'SUB', 'ENABLED');
    $report .= "  " . "-" x 72 . "\n";

    for my $svc (sort { $a->{unit} cmp $b->{unit} } @{$result->{services}}) {
        my $marker = $svc->{active} eq 'active'  ? '●' :
                     $svc->{active} eq 'failed'  ? '✗' : '○';
        $report .= sprintf("  %s %-38s %-10s %-10s %-10s\n",
            $marker, $svc->{unit}, $svc->{active}, $svc->{sub_state}, $svc->{enabled});
    }

    return $report;
}

1;

__END__

=head1 NAME

HBPerl::Scripts::ServiceMonitor - Systemd service monitoring and status

=head1 SYNOPSIS

    use HBPerl::Scripts::ServiceMonitor;
    my $r = HBPerl::Scripts::ServiceMonitor::run(filter => 'ssh');
    print HBPerl::Scripts::ServiceMonitor::format_report($r);

=head1 DESCRIPTION

Lists all systemd services with their active, sub, and enabled states.
Highlights failed services for quick triage.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<filter> (regex to match unit names).

Returns a hash-ref with service list and failed-service count.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
