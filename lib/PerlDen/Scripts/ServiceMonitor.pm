package PerlDen::Scripts::ServiceMonitor;
# ============================================================================
# Monitor systemd services — status, failed, enabled/disabled
# ============================================================================
use strict;
use warnings;

# Minimum systemd version that supports --json=short (systemd 247, released 2020)
my $SYSTEMD_MIN_JSON = 247;

sub _systemd_version {
    my $ver = qx{systemctl --version 2>/dev/null} // '';
    return ($ver =~ /systemd\s+(\d+)/)[0] // 0;
}

sub run {
    my (%args) = @_;
    my $filter = $args{filter} // '';

    # Prefer JSON output for robustness; fall back to text on older systemd
    return _run_json($filter) if _systemd_version() >= $SYSTEMD_MIN_JSON;
    return _run_text($filter);
}

sub _run_json {
    my ($filter) = @_;
    require JSON::MaybeXS;

    my $raw = '';
    if (open my $fh, '-|', 'systemctl', 'list-units', '--type=service',
                            '--all', '--no-pager', '--json=short') {
        local $/;
        $raw = <$fh> // '';
        close $fh;
    }

    my $data = eval { JSON::MaybeXS->new->decode($raw) } // [];

    my (@services, @failed);
    for my $u (@$data) {
        my $unit = $u->{unit} // '';
        my $desc = $u->{description} // '';
        next if $filter && $unit !~ /\Q$filter\E/i && $desc !~ /\Q$filter\E/i;

        my $svc = {
            unit        => $unit,
            load_state  => $u->{load}   // '',
            active      => $u->{active} // '',
            sub_state   => $u->{sub}    // '',
            description => $desc,
            enabled     => 'unknown',
        };
        push @services, $svc;
        push @failed,   $svc if ($svc->{active} eq 'failed');
    }

    # Merge enabled/disabled state (still text output — no JSON for list-unit-files)
    _merge_enabled(\@services);

    my %counts;
    $counts{$_->{active}}++ for @services;
    return { services => \@services, failed => \@failed, counts => \%counts, total => scalar @services };
}

sub _run_text {
    my ($filter) = @_;

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
            load_state  => $load   // '',
            active      => $active // '',
            sub_state   => $sub    // '',
            description => $desc   // '',
        };
        push @services, $svc;
        push @failed, $svc if ($active // '') eq 'failed';
    }

    _merge_enabled(\@services);

    my %counts;
    $counts{$_->{active}}++ for @services;
    return { services => \@services, failed => \@failed, counts => \%counts, total => scalar @services };
}

sub _merge_enabled {
    my ($services) = @_;
    my %enabled;
    my @lines;
    if (open my $fh, '-|', 'systemctl', 'list-unit-files', '--type=service', '--no-legend', '--no-pager') {
        @lines = <$fh>;
        close $fh;
    }
    for my $line (@lines) {
        $line =~ s/^\s+//;
        my ($unit, $state) = split /\s+/, $line;
        $enabled{$unit} = $state if $unit;
    }
    $_->{enabled} = $enabled{$_->{unit}} // 'unknown' for @$services;
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

sub metadata {
    return {
        name        => 'Service Monitor',
        filename    => 'service_monitor.pl',
        description => 'Check systemd service status',
        category    => 'System Info',
        icon        => 'computer-symbolic',
        emoji       => '🖥',
    };
}

1;

__END__

=head1 NAME

PerlDen::Scripts::ServiceMonitor - Systemd service monitoring and status

=head1 SYNOPSIS

    use PerlDen::Scripts::ServiceMonitor;
    my $r = PerlDen::Scripts::ServiceMonitor::run(filter => 'ssh');
    print PerlDen::Scripts::ServiceMonitor::format_report($r);

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

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<services>

Arrayref of service hashrefs C<{ name, active, sub, description }>.

=item C<failed>

Arrayref of failed service hashrefs (subset of C<services>).

=item C<counts>

Hashref of active-state E<rarr> count (e.g. C<active>, C<inactive>, C<failed>).

=item C<total>

Total number of services returned.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
