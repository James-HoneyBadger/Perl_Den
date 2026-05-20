package PerlDen::Scripts::PortScanner;
# ============================================================================
# Port scanner — listening ports, open TCP ports, service detection
# ============================================================================
use strict;
use warnings;
use IO::Socket::INET;

sub run {
    my (%args) = @_;
    my $host        = $args{host}        // '127.0.0.1';
    my $port_range  = $args{port_range}  // '1-1024';
    my $timeout     = $args{timeout}     // 1;
    my $mode        = $args{mode}        // 'listen';   # 'listen' or 'scan'
    my $run_timeout = $args{run_timeout} // 30;

    local $SIG{ALRM} = sub { die "PortScanner timed out after ${run_timeout}s\n" };
    alarm($run_timeout);

    my %result;

    # ── Listening Ports (from ss) ──
    $result{listening} = _get_listening_ports();

    # ── Established Connections ──
    $result{established} = _get_established();

    # ── Port Scan (optional) ──
    if ($mode eq 'scan') {
        my ($start, $end) = _parse_range($port_range);
        $result{scan} = _scan_ports($host, $start, $end, $timeout);
    }

    # ── Well-known service info ──
    $result{service_map} = _service_map();

    alarm(0);
    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                PORT & CONNECTION ANALYSIS                     ║
╚══════════════════════════════════════════════════════════════╝

EOF

    # Listening ports
    $report .= "── Listening Ports ───────────────────────────────────────────\n";
    $report .= sprintf("  %-8s %-8s %-22s %-22s %s\n",
        'Proto', 'State', 'Local Address', 'Peer', 'Process');
    $report .= "  " . ("-" x 72) . "\n";
    for my $p (@{$result->{listening} // []}) {
        $report .= sprintf("  %-8s %-8s %-22s %-22s %s\n",
            $p->{proto}, $p->{state}, $p->{local}, $p->{peer}, $p->{process} // '-');
    }

    $report .= sprintf("\n  Total listening: %d\n", scalar @{$result->{listening} // []});

    # Established connections
    $report .= "\n── Established Connections ────────────────────────────────────\n";
    my @est = @{$result->{established} // []};
    if (@est) {
        $report .= sprintf("  %-8s %-22s %-22s %s\n",
            'Proto', 'Local', 'Remote', 'Process');
        $report .= "  " . ("-" x 72) . "\n";
        for my $c (splice @est, 0, 50) {
            $report .= sprintf("  %-8s %-22s %-22s %s\n",
                $c->{proto}, $c->{local}, $c->{peer}, $c->{process} // '-');
        }
    }
    $report .= sprintf("  Total established: %d\n", scalar @{$result->{established} // []});

    # Port scan results
    if ($result->{scan}) {
        my $smap = $result->{service_map};
        $report .= "\n── Port Scan Results ─────────────────────────────────────────\n";
        $report .= sprintf("  Host: %s\n", $result->{scan}{host});
        $report .= sprintf("  Ports scanned: %d-%d\n", $result->{scan}{start}, $result->{scan}{end});
        $report .= sprintf("  Open ports: %d\n\n", scalar @{$result->{scan}{open}});
        for my $p (@{$result->{scan}{open}}) {
            my $svc = $smap->{$p} // 'unknown';
            $report .= sprintf("  Port %-6d open    %s\n", $p, $svc);
        }
    }

    # Summary by port
    $report .= "\n── Listening Port Summary ────────────────────────────────────\n";
    my %by_port;
    for my $p (@{$result->{listening} // []}) {
        my ($port) = ($p->{local} =~ /:(\d+)$/);
        next unless defined $port;
        $by_port{$port}++;
    }
    my $smap = $result->{service_map};
    for my $port (sort { $a <=> $b } keys %by_port) {
        my $svc = $smap->{$port} // '';
        $report .= sprintf("  :%- 6d %s\n", $port, $svc);
    }

    return $report;
}

sub _get_listening_ports {
    my @ports;
    my @lines;
    if (open my $fh, '-|', 'ss', '-tlnpH') {
        @lines = <$fh>;
        close $fh;
    }
    if (!@lines) {
        if (open my $fh, '-|', 'ss', '-tlnp') {
            @lines = <$fh>;
            close $fh;
        }
        shift @lines;  # skip header
    }
    for my $line (@lines) {
        chomp $line;
        next unless $line =~ /\S/;
        my @f = split /\s+/, $line;
        next unless @f >= 4;
        my %entry = (
            proto => 'tcp',
            state => $f[0],
            local => $f[3],
            peer  => $f[4] // '*:*',
        );
        if ($line =~ /users:\(\("([^"]+)",pid=(\d+)/) {
            $entry{process} = "$1 (pid $2)";
        }
        push @ports, \%entry;
    }

    # Also get UDP
    my @ulines;
    if (open my $fh, '-|', 'ss', '-ulnpH') {
        @ulines = <$fh>;
        close $fh;
    }
    if (!@ulines) {
        if (open my $fh, '-|', 'ss', '-ulnp') {
            @ulines = <$fh>;
            close $fh;
        }
        shift @ulines;
    }
    for my $line (@ulines) {
        chomp $line;
        next unless $line =~ /\S/;
        my @f = split /\s+/, $line;
        next unless @f >= 4;
        my %entry = (
            proto => 'udp',
            state => $f[0],
            local => $f[3],
            peer  => $f[4] // '*:*',
        );
        if ($line =~ /users:\(\("([^"]+)",pid=(\d+)/) {
            $entry{process} = "$1 (pid $2)";
        }
        push @ports, \%entry;
    }
    return \@ports;
}

sub _get_established {
    my @conns;
    my @lines;
    if (open my $fh, '-|', 'ss', '-tnpH') {
        @lines = <$fh>;
        close $fh;
    }
    if (!@lines) {
        if (open my $fh, '-|', 'ss', '-tnp') {
            @lines = <$fh>;
            close $fh;
        }
        shift @lines;
    }
    for my $line (@lines) {
        chomp $line;
        next unless $line =~ /ESTAB/;
        my @f = split /\s+/, $line;
        next unless @f >= 5;
        my %entry = (
            proto => 'tcp',
            local => $f[3],
            peer  => $f[4],
        );
        if ($line =~ /users:\(\("([^"]+)",pid=(\d+)/) {
            $entry{process} = "$1 (pid $2)";
        }
        push @conns, \%entry;
    }
    return \@conns;
}

sub _parse_range {
    my ($range) = @_;
    if ($range =~ /^(\d+)-(\d+)$/) {
        return ($1, $2);
    }
    return (1, 1024);
}

sub _scan_ports {
    my ($host, $start, $end, $timeout) = @_;
    my @open;
    for my $port ($start .. $end) {
        my $sock = IO::Socket::INET->new(
            PeerAddr => $host,
            PeerPort => $port,
            Proto    => 'tcp',
            Timeout  => $timeout,
        );
        if ($sock) {
            push @open, $port;
            close $sock;
        }
    }
    return { host => $host, start => $start, end => $end, open => \@open };
}

sub _service_map {
    return {
        20    => 'FTP Data',
        21    => 'FTP',
        22    => 'SSH',
        23    => 'Telnet',
        25    => 'SMTP',
        53    => 'DNS',
        80    => 'HTTP',
        110   => 'POP3',
        143   => 'IMAP',
        443   => 'HTTPS',
        465   => 'SMTPS',
        587   => 'SMTP Submission',
        993   => 'IMAPS',
        995   => 'POP3S',
        3306  => 'MySQL',
        5432  => 'PostgreSQL',
        6379  => 'Redis',
        8080  => 'HTTP Alt',
        8443  => 'HTTPS Alt',
        27017 => 'MongoDB',
    };
}

sub metadata {
    return {
        name        => 'Port Scanner',
        filename    => 'port_scanner.pl',
        description => 'Scan listening ports and services',
        category    => 'Network',
        icon        => 'network-wired-symbolic',
        emoji       => '🌐',
        run_timeout => 30,
    };
}

1;

__END__

=head1 NAME

PerlDen::Scripts::PortScanner - Port scanning and connection analysis

=head1 SYNOPSIS

    use PerlDen::Scripts::PortScanner;
    my $r = PerlDen::Scripts::PortScanner::run(
        host       => '127.0.0.1',
        port_range => '1-1024',
        timeout    => 1,
        mode       => 'scan',
    );
    print PerlDen::Scripts::PortScanner::format_report($r);

=head1 DESCRIPTION

Lists listening ports and established connections via C<ss>, and
optionally performs a TCP connect scan against a host and port range.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<host>, C<port_range> (e.g. C<'1-1024'>), C<timeout>
(seconds per port), C<mode> (C<'listen'> or C<'scan'>).

Returns a hash-ref with listening ports, connections, and scan results.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<listening>

Arrayref of listening port hashrefs C<{ proto, addr, port, process }>
from C<ss -tulnp>.

=item C<established>

Arrayref of established connection hashrefs C<{ proto, local, remote, pid }>.

=item C<scan>

Present only when C<scan_range> is specified.  Arrayref of
C<{ port, open, service }> hashrefs.

=item C<service_map>

Hashref of well-known port number (string) E<rarr> service name.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
