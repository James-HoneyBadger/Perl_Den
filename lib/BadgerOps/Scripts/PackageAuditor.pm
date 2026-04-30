package BadgerOps::Scripts::PackageAuditor;
# ============================================================================
# PackageAuditor — installed packages, available updates, orphaned packages
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my %result;

    $result{pkg_manager} = _detect_pkg_manager();
    $result{installed}   = _get_installed_count($result{pkg_manager});
    $result{updates}     = _get_available_updates($result{pkg_manager});
    $result{orphaned}    = _get_orphaned($result{pkg_manager});
    $result{recent}      = _get_recently_installed($result{pkg_manager});

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                  PACKAGE AUDIT REPORT                        ║
╚══════════════════════════════════════════════════════════════╝

EOF

    $report .= "  Package Manager: " . ($result->{pkg_manager} // 'unknown') . "\n";
    $report .= "  Installed Packages: " . ($result->{installed} // '?') . "\n\n";

    # Available updates
    $report .= "── Available Updates ─────────────────────────────────────────\n";
    my @updates = @{$result->{updates} // []};
    if (@updates) {
        $report .= sprintf("  %-35s %-15s %s\n", 'Package', 'Current', 'Available');
        $report .= "  " . ("-" x 65) . "\n";
        for my $u (@updates[0 .. ($#updates > 24 ? 24 : $#updates)]) {
            $report .= sprintf("  %-35s %-15s %s\n",
                $u->{name}, $u->{current} // '?', $u->{available} // '?');
        }
        $report .= sprintf("\n  Total packages with updates: %d\n", scalar @updates);
        $report .= "  (showing first 25)\n" if @updates > 25;
    } else {
        $report .= "  System is up to date.\n";
    }

    # Orphaned packages
    $report .= "\n── Orphaned Packages ─────────────────────────────────────────\n";
    my @orphaned = @{$result->{orphaned} // []};
    if (@orphaned) {
        $report .= "  $_\n" for @orphaned[0 .. ($#orphaned > 19 ? 19 : $#orphaned)];
        $report .= sprintf("\n  Total orphaned: %d\n", scalar @orphaned);
    } else {
        $report .= "  No orphaned packages found.\n";
    }

    # Recently installed
    $report .= "\n── Recently Installed (last 20) ──────────────────────────────\n";
    my @recent = @{$result->{recent} // []};
    if (@recent) {
        $report .= "  $_\n" for @recent;
    } else {
        $report .= "  No recent installation history available.\n";
    }

    return $report;
}

# ── Internal helpers ──

sub _detect_pkg_manager {
    for my $pm (
        ['dnf',    'dnf'],
        ['apt',    'apt'],
        ['pacman', 'pacman'],
        ['zypper', 'zypper'],
    ) {
        my $path = '';
        if (open my $wh_fh, '-|', 'which', $pm->[1]) {
            $path = <$wh_fh> // '';
            chomp $path;
            close $wh_fh;
        }
        return $pm->[0] if $path && -x $path;
    }
    return 'unknown';
}

sub _get_installed_count {
    my ($pm) = @_;
    if ($pm eq 'dnf' || $pm eq 'rpm') {
        my $count = 0;
        if (open my $fh, '-|', 'rpm', '-qa') {
            $count++ while <$fh>;
            close $fh;
        }
        return $count;
    } elsif ($pm eq 'apt') {
        my $count = 0;
        if (open my $fh, '-|', 'dpkg', '-l') {
            while (<$fh>) { $count++ if /^ii/ }
            close $fh;
        }
        return $count;
    } elsif ($pm eq 'pacman') {
        my $count = 0;
        if (open my $fh, '-|', 'pacman', '-Q') {
            $count++ while <$fh>;
            close $fh;
        }
        return $count;
    }
    return '?';
}

sub _get_available_updates {
    my ($pm) = @_;
    my @updates;

    if ($pm eq 'dnf') {
        my $out = '';
        if (open my $fh, '-|', 'dnf', 'check-update', '--quiet') {
            local $/;
            $out = <$fh> // '';
            close $fh;
        }
        for my $line (split /\n/, $out) {
            next if $line =~ /^\s*$/ || $line =~ /^Last metadata/;
            my @parts = split /\s+/, $line;
            next unless @parts >= 2;
            push @updates, { name => $parts[0], available => $parts[1], current => '-' };
        }
    } elsif ($pm eq 'apt') {
        my $out = '';
        if (open my $fh, '-|', 'apt', 'list', '--upgradable') {
            local $/;
            $out = <$fh> // '';
            close $fh;
        }
        for my $line (split /\n/, $out) {
            next unless $line =~ /^(\S+)\/\S+\s+(\S+)\s+.*\[.*?(\S+)\]/;
            push @updates, { name => $1, available => $2, current => $3 };
        }
    } elsif ($pm eq 'pacman') {
        my $out = '';
        if (open my $fh, '-|', 'checkupdates') {
            local $/;
            $out = <$fh> // '';
            close $fh;
        }
        for my $line (split /\n/, $out) {
            my @parts = split /\s+/, $line;
            next unless @parts >= 4;
            push @updates, { name => $parts[0], current => $parts[1], available => $parts[3] };
        }
    }

    return \@updates;
}

sub _get_orphaned {
    my ($pm) = @_;
    my @orphaned;

    if ($pm eq 'dnf') {
        my $out = '';
        if (open my $fh, '-|', 'package-cleanup', '--orphans') {
            local $/;
            $out = <$fh> // '';
            close $fh;
        }
        @orphaned = grep { length && !/^Loaded/ } split /\n/, $out;
    } elsif ($pm eq 'apt') {
        my $out = '';
        if (open my $fh, '-|', 'deborphan') {
            local $/;
            $out = <$fh> // '';
            close $fh;
        }
        @orphaned = grep { length } split /\n/, $out;
    } elsif ($pm eq 'pacman') {
        my $out = '';
        if (open my $fh, '-|', 'pacman', '-Qtd') {
            local $/;
            $out = <$fh> // '';
            close $fh;
        }
        @orphaned = grep { length } split /\n/, $out;
    }

    return \@orphaned;
}

sub _get_recently_installed {
    my ($pm) = @_;
    my @recent;

    if ($pm eq 'dnf') {
        if (open my $fh, '-|', 'dnf', 'history', 'list', '--reverse') {
            my @all = <$fh>;
            close $fh;
            @recent = grep { length } @all[-20..-1] if @all > 0;
        }
    } elsif ($pm eq 'apt') {
        if (open my $fh, '<', '/var/log/dpkg.log') {
            while (<$fh>) {
                next unless / install /;
                push @recent, $_;
                shift @recent if @recent > 20;
            }
            close $fh;
        }
    } elsif ($pm eq 'pacman') {
        if (open my $fh, '<', '/var/log/pacman.log') {
            while (<$fh>) {
                next unless /installed/;
                push @recent, $_;
                shift @recent if @recent > 20;
            }
            close $fh;
        }
    }

    chomp @recent;
    return \@recent;
}

sub metadata {
    return {
        name        => 'Package Auditor',
        filename    => 'package_auditor.pl',
        description => 'Installed packages, updates, orphans',
        category    => 'System Info',
        icon        => 'computer-symbolic',
        emoji       => '🖥',
    };
}

1;

__END__

=head1 NAME

BadgerOps::Scripts::PackageAuditor - System package auditing

=head1 SYNOPSIS

    use BadgerOps::Scripts::PackageAuditor;
    my $result = BadgerOps::Scripts::PackageAuditor::run();
    print BadgerOps::Scripts::PackageAuditor::format_report($result);

=head1 DESCRIPTION

Detects the system package manager (dnf/apt/pacman/zypper), counts
installed packages, checks for available updates, finds orphaned
packages, and lists recently installed packages.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Auto-detects the package manager and queries it for installed package
counts, available updates, orphaned packages, and recently installed
packages (last 20 by install date).

=item B<format_report($result)>

Formats the package audit data as a human-readable text report.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<pkg_manager>

String: C<'apt'>, C<'dnf'>, C<'pacman'>, C<'zypper'>, or C<'unknown'>.

=item C<installed>

Integer count of installed packages.

=item C<updates>

Arrayref of update hashrefs C<{ name, current, available }>.

=item C<orphaned>

Arrayref of orphaned/auto-removable package name strings.

=item C<recent>

Arrayref of recently installed package name strings.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
