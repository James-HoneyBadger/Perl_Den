package PerlDen::Scripts::FirewallAuditor;
# ============================================================================
# FirewallAuditor — dump & analyze iptables/nftables rules
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my %result;

    # ── iptables rules ──
    $result{iptables} = _get_iptables();

    # ── nftables rules ──
    $result{nftables} = _get_nftables();

    # ── Active firewall detection ──
    $result{firewall_type} = _detect_firewall();

    # ── Open ports without matching rules ──
    $result{unmatched_ports} = _find_unmatched_ports($result{iptables});

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                   FIREWALL AUDIT REPORT                      ║
╚══════════════════════════════════════════════════════════════╝

EOF

    $report .= "  Active Firewall: " . ($result->{firewall_type} // 'unknown') . "\n\n";

    # iptables
    $report .= "── iptables Rules ────────────────────────────────────────────\n";
    my $ipt = $result->{iptables} // {};
    for my $chain (sort keys %$ipt) {
        $report .= "\n  Chain: $chain (policy: " . ($ipt->{$chain}{policy} // '-') . ")\n";
        for my $rule (@{$ipt->{$chain}{rules} // []}) {
            $report .= "    $rule\n";
        }
    }

    # nftables
    $report .= "\n── nftables Ruleset ──────────────────────────────────────────\n";
    if ($result->{nftables} && @{$result->{nftables}}) {
        $report .= "  $_\n" for @{$result->{nftables}};
    } else {
        $report .= "  No nftables rules found.\n";
    }

    # Unmatched ports
    $report .= "\n── Listening Ports Without Explicit Rules ─────────────────────\n";
    my @unmatched = @{$result->{unmatched_ports} // []};
    if (@unmatched) {
        $report .= sprintf("  %-8s %-8s %s\n", 'Proto', 'Port', 'Process');
        $report .= "  " . ("-" x 40) . "\n";
        $report .= sprintf("  %-8s %-8s %s\n", $_->{proto}, $_->{port}, $_->{process} // '-')
            for @unmatched;
    } else {
        $report .= "  All listening ports have matching rules (or no ports open).\n";
    }

    $report .= "\n  ⚑ Review ACCEPT rules that may be overly permissive.\n";
    return $report;
}

# ── Internal helpers ──

sub _detect_firewall {
    # Check if nftables or iptables is in use
    my $nft = '';
    if (open my $fh, '-|', 'which', 'nft') {
        $nft = <$fh> // '';
        chomp $nft;
        close $fh;
    }
    if ($nft && -x $nft) {
        my $rules = '';
        if (open my $fh, '-|', 'nft', 'list', 'ruleset') {
            local $/;
            $rules = <$fh> // '';
            close $fh;
        }
        return 'nftables' if $rules && $rules =~ /table/;
    }
    my $ipt = '';
    if (open my $fh, '-|', 'which', 'iptables') {
        $ipt = <$fh> // '';
        chomp $ipt;
        close $fh;
    }
    return 'iptables' if $ipt && -x $ipt;
    return 'unknown';
}

sub _get_iptables {
    my %chains;
    my $output = '';
    if (open my $fh, '-|', 'iptables', '-L', '-n', '--line-numbers') {
        local $/;
        $output = <$fh> // '';
        close $fh;
    }
    my $current_chain;

    for my $line (split /\n/, $output) {
        if ($line =~ /^Chain\s+(\S+)\s+\(policy\s+(\S+)/) {
            $current_chain = $1;
            $chains{$current_chain} = { policy => $2, rules => [] };
        } elsif ($current_chain && $line =~ /^\d+/) {
            push @{$chains{$current_chain}{rules}}, $line;
        }
    }
    return \%chains;
}

sub _get_nftables {
    my $output = '';
    if (open my $fh, '-|', 'nft', 'list', 'ruleset') {
        local $/;
        $output = <$fh> // '';
        close $fh;
    }
    return [] unless $output;
    return [ split /\n/, $output ];
}

sub _find_unmatched_ports {
    my ($iptables) = @_;
    my @unmatched;

    # Get listening ports
    my @ss_lines;
    if (open my $fh, '-|', 'ss', '-tlnp') {
        @ss_lines = <$fh>;
        close $fh;
    }
    shift @ss_lines;  # header

    # Collect allowed ports from iptables ACCEPT rules
    my %allowed;
    for my $chain (values %{$iptables // {}}) {
        for my $rule (@{$chain->{rules} // []}) {
            if ($rule =~ /ACCEPT/ && $rule =~ /dpt:(\d+)/) {
                $allowed{$1} = 1;
            }
        }
    }

    for my $line (@ss_lines) {
        my @fields = split /\s+/, $line;
        next unless @fields >= 5;
        my $local = $fields[3] // '';
        my $process = $fields[5] // '-';
        if ($local =~ /:(\d+)$/) {
            my $port = $1;
            unless ($allowed{$port}) {
                push @unmatched, {
                    proto   => 'tcp',
                    port    => $port,
                    process => $process,
                };
            }
        }
    }
    return \@unmatched;
}

sub metadata {
    return {
        name        => 'Firewall Auditor',
        filename    => 'firewall_auditor.pl',
        description => 'Audit iptables/nftables firewall rules',
        category    => 'Security',
        icon        => 'security-high-symbolic',
        emoji       => '🔒',
    };
}

1;

__END__

=head1 NAME

PerlDen::Scripts::FirewallAuditor - Dump and analyze firewall rules

=head1 SYNOPSIS

    use PerlDen::Scripts::FirewallAuditor;
    my $result = PerlDen::Scripts::FirewallAuditor::run();
    print PerlDen::Scripts::FirewallAuditor::format_report($result);

=head1 DESCRIPTION

Collects iptables/nftables rules, detects the active firewall, and
identifies listening ports that lack explicit firewall rules.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Runs C<iptables-save> and C<nft list ruleset> (non-destructively), then
cross-references listening ports from C<ss> against ACCEPT rules.

=item B<format_report($result)>

Formats the firewall audit as a human-readable text report.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<iptables>

Hashref of chain name E<rarr> hashref with C<policy> and C<rules> arrayref.

=item C<nftables>

Raw C<nft list ruleset> output as a string, or empty string if unavailable.

=item C<firewall_type>

String: C<'iptables'>, C<'nftables'>, C<'both'>, or C<'none'>.

=item C<unmatched_ports>

Arrayref of hashrefs C<{ proto, port, process }> for ports that are
listening but have no matching ACCEPT rule.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
