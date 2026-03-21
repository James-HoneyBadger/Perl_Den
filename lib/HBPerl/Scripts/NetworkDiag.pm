package HBPerl::Scripts::NetworkDiag;
# ============================================================================
# Network diagnostics — interfaces, DNS lookups, connectivity
# ============================================================================
use strict;
use warnings;
use Socket;
use HBPerl::Util qw(format_bytes);

sub run {
    my (%args) = @_;
    my $dns_host  = $args{dns_host}  // 'google.com';
    my $ping_host = $args{ping_host} // '8.8.8.8';

    my %result;

    # ── Network Interfaces ──
    $result{interfaces} = _get_interfaces();

    # ── Routing Table ──
    $result{routes} = _get_routes();

    # ── DNS Resolution ──
    $result{dns} = _dns_lookup($dns_host);

    # ── DNS Servers ──
    $result{dns_servers} = _get_dns_servers();

    # ── Ping Test ──
    $result{ping} = _ping_test($ping_host);

    # ── Connectivity ──
    $result{gateway} = _get_default_gateway();

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                NETWORK DIAGNOSTICS                           ║
╚══════════════════════════════════════════════════════════════╝

EOF

    # Interfaces
    $report .= "── Network Interfaces ────────────────────────────────────────\n";
    for my $iface (@{$result->{interfaces}}) {
        $report .= sprintf("  %-12s %-18s MAC: %-18s State: %s\n",
            $iface->{name}, $iface->{ip} // 'N/A',
            $iface->{mac} // 'N/A', $iface->{state} // 'unknown');
        if ($iface->{rx_bytes}) {
            $report .= sprintf("               RX: %s  TX: %s\n",
                _fmt_bytes($iface->{rx_bytes}), _fmt_bytes($iface->{tx_bytes}));
        }
    }

    # Default gateway
    $report .= "\n── Default Gateway ───────────────────────────────────────────\n";
    $report .= "  Gateway: " . ($result->{gateway} // 'not found') . "\n";

    # DNS servers
    $report .= "\n── DNS Servers ───────────────────────────────────────────────\n";
    for my $ns (@{$result->{dns_servers} // []}) {
        $report .= "  $ns\n";
    }

    # DNS resolution
    $report .= "\n── DNS Lookup ────────────────────────────────────────────────\n";
    if ($result->{dns} && $result->{dns}{addresses}) {
        $report .= "  $result->{dns}{host} resolves to:\n";
        for my $addr (@{$result->{dns}{addresses}}) {
            $report .= "    $addr\n";
        }
    } else {
        $report .= "  DNS resolution failed\n";
    }

    # Ping
    $report .= "\n── Ping Test ─────────────────────────────────────────────────\n";
    if ($result->{ping}) {
        $report .= "  $result->{ping}{output}\n";
    }

    # Routes
    $report .= "\n── Routing Table ─────────────────────────────────────────────\n";
    for my $r (@{$result->{routes} // []}) {
        $report .= "  $r\n";
    }

    return $report;
}

sub _get_interfaces {
    my @interfaces;
    my @lines;
    if (open my $fh, '-|', 'ip', '-o', 'addr', 'show') {
        @lines = <$fh>;
        close $fh;
    }
    my %seen;
    for my $line (@lines) {
        if ($line =~ /^\d+:\s+(\S+)\s+inet6?\s+([\d.a-f:]+(?:\/\d+)?)/) {
            my ($name, $ip) = ($1, $2);
            next if $seen{"$name:$ip"}++;
            my %iface = (name => $name, ip => $ip);

            # Get MAC and state
            my @link;
            if (open my $lnk_fh, '-|', 'ip', 'link', 'show', $name) {
                @link = <$lnk_fh>;
                close $lnk_fh;
            }
            for (@link) {
                $iface{state} = $1 if /state\s+(\w+)/;
                $iface{mac} = $1 if /link\/ether\s+([\da-f:]+)/i;
                $iface{mtu} = $1 if /mtu\s+(\d+)/;
            }

            # Get traffic stats from /proc/net/dev
            if (open my $fh, '<', '/proc/net/dev') {
                while (<$fh>) {
                    if (/^\s*$name:\s*(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/) {
                        $iface{rx_bytes} = $1;
                        $iface{tx_bytes} = $2;
                    }
                }
                close $fh;
            }

            push @interfaces, \%iface;
        }
    }
    return \@interfaces;
}

sub _get_routes {
    my @lines;
    if (open my $fh, '-|', 'ip', 'route', 'show') {
        @lines = <$fh>;
        close $fh;
    }
    chomp @lines;
    return \@lines;
}

sub _dns_lookup {
    my ($host) = @_;
    my @addresses;

    # Use getaddrinfo for resolution
    eval {
        my @addrs = gethostbyname($host);
        if (@addrs >= 5) {
            for my $addr (@addrs[4..$#addrs]) {
                push @addresses, inet_ntoa($addr);
            }
        }
    };

    return { host => $host, addresses => \@addresses };
}

sub _get_dns_servers {
    my @servers;
    if (open my $fh, '<', '/etc/resolv.conf') {
        while (<$fh>) {
            if (/^nameserver\s+([\d.:a-f]+)/i) {
                push @servers, $1;
            }
        }
        close $fh;
    }
    # Also check systemd-resolved
    if (!@servers) {
        my @lines;
        if (open my $fh, '-|', 'resolvectl', 'status') {
            @lines = <$fh>;
            close $fh;
        }
        for (@lines) {
            if (/DNS Servers:\s+(.+)/) {
                push @servers, split /\s+/, $1;
            }
        }
    }
    return \@servers;
}

sub _ping_test {
    my ($host) = @_;
    # Validate hostname/IP to prevent command injection
    unless ($host =~ /^[\w.\-:\[\]]+$/) {
        return { host => $host, success => 0, output => "Invalid hostname: $host" };
    }
    my $output = '';
    if (open(my $fh, '-|', 'ping', '-c', '3', '-W', '2', $host)) {
        local $/;
        $output = <$fh> // '';
        close $fh;
    }
    my $success = ($? >> 8) == 0;
    return { host => $host, success => $success, output => $output };
}

sub _get_default_gateway {
    my @lines;
    if (open my $fh, '-|', 'ip', 'route', 'show', 'default') {
        @lines = <$fh>;
        close $fh;
    }
    for (@lines) {
        return $1 if /via\s+([\d.]+)/;
    }
    return undef;
}

# _fmt_bytes is provided by HBPerl::Util::format_bytes
sub _fmt_bytes { goto &format_bytes }

1;

__END__

=head1 NAME

HBPerl::Scripts::NetworkDiag - Network diagnostics and analysis

=head1 SYNOPSIS

    use HBPerl::Scripts::NetworkDiag;
    my $r = HBPerl::Scripts::NetworkDiag::run(
        dns_host  => 'example.com',
        ping_host => '8.8.8.8',
    );
    print HBPerl::Scripts::NetworkDiag::format_report($r);

=head1 DESCRIPTION

Gathers network interface information, the routing table, DNS server
configuration, DNS resolution results, ICMP ping tests, and the
default gateway.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<dns_host> (hostname to resolve), C<ping_host> (host
to ping).

Returns a hash-ref with interfaces, routes, DNS details, and
connectivity results.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
