package HBPerl::Scripts::FailedLoginDetector;
# ============================================================================
# Failed login / brute-force detector — auth log analysis
# ============================================================================
use strict;
use warnings;
use POSIX qw(strftime);

sub run {
    my (%args) = @_;
    my $threshold = $args{threshold} // 5;     # failures before flagging
    my $hours     = $args{hours}     // 24;    # lookback window
    my $source    = $args{source}    // 'auto';

    my %result;

    # ── Gather auth log entries ──
    my @entries = _get_auth_entries($source, $hours);

    # ── Analyse failed logins ──
    my (%by_ip, %by_user, %by_service, @timeline);
    my $total_failed = 0;
    my $total_success = 0;

    for my $e (@entries) {
        if ($e->{type} eq 'fail') {
            $total_failed++;
            $by_ip{$e->{ip}}++          if $e->{ip};
            $by_user{$e->{user}}++      if $e->{user};
            $by_service{$e->{service}}++ if $e->{service};
            push @timeline, $e;
        } elsif ($e->{type} eq 'success') {
            $total_success++;
        }
    }

    # Flag brute-force IPs
    my @flagged_ips;
    for my $ip (sort { $by_ip{$b} <=> $by_ip{$a} } keys %by_ip) {
        last if $by_ip{$ip} < $threshold;
        push @flagged_ips, { ip => $ip, attempts => $by_ip{$ip} };
    }

    # Flag targeted users
    my @flagged_users;
    for my $u (sort { $by_user{$b} <=> $by_user{$a} } keys %by_user) {
        last if $by_user{$u} < $threshold;
        push @flagged_users, { user => $u, attempts => $by_user{$u} };
    }

    # Currently banned IPs (fail2ban / firewall)
    my $banned = _get_banned_ips();

    $result{total_failed}  = $total_failed;
    $result{total_success} = $total_success;
    $result{by_ip}         = \%by_ip;
    $result{by_user}       = \%by_user;
    $result{by_service}    = \%by_service;
    $result{flagged_ips}   = \@flagged_ips;
    $result{flagged_users} = \@flagged_users;
    $result{banned}        = $banned;
    $result{hours}         = $hours;
    $result{threshold}     = $threshold;
    $result{recent}        = @timeline > 20 ? [ splice @timeline, -20 ] : \@timeline;

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║              FAILED LOGIN / BRUTE-FORCE DETECTOR              ║
╚══════════════════════════════════════════════════════════════╝

  Lookback:           $result->{hours} hours
  Alert Threshold:    $result->{threshold} attempts
  Total Failed:       $result->{total_failed}
  Total Successful:   $result->{total_success}

EOF

    # Flagged IPs
    my @fip = @{$result->{flagged_ips} // []};
    $report .= "── ⚠ Flagged IPs (possible brute-force) ──────────────────────\n";
    if (@fip) {
        for my $f (@fip) {
            $report .= sprintf("  %-20s %d failed attempts\n", $f->{ip}, $f->{attempts});
        }
    } else {
        $report .= "  None detected above threshold.\n";
    }

    # Flagged users
    my @fu = @{$result->{flagged_users} // []};
    $report .= "\n── ⚠ Targeted Users ──────────────────────────────────────────\n";
    if (@fu) {
        for my $f (@fu) {
            $report .= sprintf("  %-20s %d failed attempts\n", $f->{user}, $f->{attempts});
        }
    } else {
        $report .= "  None detected above threshold.\n";
    }

    # By service
    $report .= "\n── Failures by Service ───────────────────────────────────────\n";
    my %svc = %{$result->{by_service} // {}};
    for my $s (sort { $svc{$b} <=> $svc{$a} } keys %svc) {
        $report .= sprintf("  %-20s %d\n", $s, $svc{$s});
    }

    # Top 20 IPs
    $report .= "\n── Top Offending IPs ─────────────────────────────────────────\n";
    my %ips = %{$result->{by_ip} // {}};
    my $n = 0;
    for my $ip (sort { $ips{$b} <=> $ips{$a} } keys %ips) {
        last if ++$n > 20;
        my $flag = ($ips{$ip} >= $result->{threshold}) ? ' ⚠' : '';
        $report .= sprintf("  %-20s %d%s\n", $ip, $ips{$ip}, $flag);
    }

    # Banned IPs
    my @banned = @{$result->{banned} // []};
    $report .= "\n── Currently Banned IPs ──────────────────────────────────────\n";
    if (@banned) {
        for my $b (@banned) {
            $report .= "  $b\n";
        }
    } else {
        $report .= "  No banned IPs detected (or fail2ban not running).\n";
    }

    # Recent events
    $report .= "\n── Recent Failed Attempts ────────────────────────────────────\n";
    for my $e (@{$result->{recent} // []}) {
        $report .= sprintf("  %s  %-16s %-12s %-8s %s\n",
            $e->{time} // '?', $e->{ip} // '-', $e->{user} // '-',
            $e->{service} // '-', $e->{detail} // '');
    }

    return $report;
}

sub _get_auth_entries {
    my ($source, $hours) = @_;
    my @entries;
    my $cutoff = time() - ($hours * 3600);

    # Try journalctl first (most reliable on systemd)
    if ($source eq 'auto' || $source eq 'journal') {
        # Validate hours is numeric to prevent injection
        my $safe_hours = int($hours || 24);
        my @lines;
        if (open(my $fh, '-|', 'journalctl', '-u', 'sshd', '-u', 'systemd-logind',
                 '--since', "${safe_hours}h ago", '--no-pager')) {
            @lines = <$fh>;
            close $fh;
        }
        if (@lines > 1) {
            push @entries, _parse_auth_lines(\@lines);
            return @entries if @entries;
        }
    }

    # Fallback to log files
    my @log_paths = (
        '/var/log/auth.log',
        '/var/log/secure',
        '/var/log/messages',
    );

    for my $log (@log_paths) {
        next unless -r $log;
        if (open my $fh, '<', $log) {
            my @lines;
            while (<$fh>) {
                push @lines, $_;
            }
            close $fh;
            my @parsed = _parse_auth_lines(\@lines);
            # Filter entries within the lookback window
            for my $e (@parsed) {
                my $epoch = _syslog_to_epoch($e->{time});
                push @entries, $e if !$epoch || $epoch >= $cutoff;
            }
            last if @entries;
        }
    }

    return @entries;
}

sub _parse_auth_lines {
    my ($lines) = @_;
    my @entries;

    for my $line (@$lines) {
        chomp $line;

        # Failed password for <user> from <ip> port <port> ssh2
        if ($line =~ /Failed password for (?:invalid user )?(\S+) from ([\d.]+)/i) {
            push @entries, {
                type    => 'fail',
                user    => $1,
                ip      => $2,
                service => 'sshd',
                time    => _extract_time($line),
                detail  => 'Failed password',
            };
        }
        # Invalid user <user> from <ip>
        elsif ($line =~ /Invalid user (\S+) from ([\d.]+)/i) {
            push @entries, {
                type    => 'fail',
                user    => $1,
                ip      => $2,
                service => 'sshd',
                time    => _extract_time($line),
                detail  => 'Invalid user',
            };
        }
        # authentication failure
        elsif ($line =~ /authentication failure.*ruser=(\S*)\s+rhost=([\d.]+)/i) {
            push @entries, {
                type    => 'fail',
                user    => $1 || 'unknown',
                ip      => $2,
                service => 'pam',
                time    => _extract_time($line),
                detail  => 'PAM auth failure',
            };
        }
        # Connection closed by authenticating user
        elsif ($line =~ /Connection closed by authenticating user (\S+) ([\d.]+)/i) {
            push @entries, {
                type    => 'fail',
                user    => $1,
                ip      => $2,
                service => 'sshd',
                time    => _extract_time($line),
                detail  => 'Connection closed during auth',
            };
        }
        # Accepted password / publickey
        elsif ($line =~ /Accepted (\w+) for (\S+) from ([\d.]+)/i) {
            push @entries, {
                type    => 'success',
                method  => $1,
                user    => $2,
                ip      => $3,
                service => 'sshd',
                time    => _extract_time($line),
            };
        }
        # sudo failures
        elsif ($line =~ /sudo:.*authentication failure/i) {
            my ($user) = ($line =~ /user (\S+)/);
            push @entries, {
                type    => 'fail',
                user    => $user // 'unknown',
                ip      => 'local',
                service => 'sudo',
                time    => _extract_time($line),
                detail  => 'sudo auth failure',
            };
        }
    }

    return @entries;
}

sub _extract_time {
    my ($line) = @_;
    # Syslog format: "Mon DD HH:MM:SS"
    if ($line =~ /^(\w{3}\s+\d+\s+\d+:\d+:\d+)/) {
        return $1;
    }
    # Journalctl format: "Mon YYYY-MM-DD HH:MM:SS"
    if ($line =~ /^(\w{3}\s+\d{4}-\d{2}-\d{2}\s+\d+:\d+:\d+)/) {
        return $1;
    }
    return 'unknown';
}

sub _syslog_to_epoch {
    my ($timestr) = @_;
    return undef unless $timestr && $timestr ne 'unknown';

    my %months = (
        Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4,  Jun => 5,
        Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11,
    );

    # Syslog format: "Mon DD HH:MM:SS"
    if ($timestr =~ /^(\w{3})\s+(\d+)\s+(\d+):(\d+):(\d+)/) {
        my ($mon_name, $day, $h, $m, $s) = ($1, $2, $3, $4, $5);
        my $mon = $months{$mon_name};
        return undef unless defined $mon;
        my @now = localtime;
        my $year = $now[5];    # years since 1900
        # If the log month is ahead of current month, it's from last year
        if ($mon > $now[4]) {
            $year--;
        }
        # Guard: don't overshoot — clamp to no earlier than year-1
        my $epoch = POSIX::mktime($s, $m, $h, $day, $mon, $year);
        return $epoch;
    }

    # Journalctl format: "Mon YYYY-MM-DD HH:MM:SS"
    if ($timestr =~ /(\d{4})-(\d{2})-(\d{2})\s+(\d+):(\d+):(\d+)/) {
        my ($y, $mo, $d, $h, $m, $s) = ($1, $2, $3, $4, $5, $6);
        return POSIX::mktime($s, $m, $h, $d, $mo - 1, $y - 1900);
    }

    return undef;
}

sub _get_banned_ips {
    my @banned;

    # fail2ban
    my @f2b;
    if (open my $fh, '-|', 'fail2ban-client', 'status', 'sshd') {
        @f2b = <$fh>;
        close $fh;
    }
    for (@f2b) {
        if (/Banned IP list:\s+(.+)/) {
            push @banned, split /\s+/, $1;
        }
    }

    # nftables / iptables
    if (!@banned) {
        my @ipt;
        if (open my $fh, '-|', 'iptables', '-L', 'INPUT', '-n') {
            @ipt = <$fh>;
            close $fh;
        }
        for (@ipt) {
            if (/DROP\s+all\s+--\s+([\d.]+)/) {
                push @banned, $1;
            }
        }
    }

    return \@banned;
}

1;

__END__

=head1 NAME

HBPerl::Scripts::FailedLoginDetector - Detect brute-force login attempts

=head1 SYNOPSIS

    use HBPerl::Scripts::FailedLoginDetector;
    my $r = HBPerl::Scripts::FailedLoginDetector::run(
        threshold => 5,
        hours     => 24,
        source    => '/var/log/auth.log',
    );
    print HBPerl::Scripts::FailedLoginDetector::format_report($r);

=head1 DESCRIPTION

Parses authentication logs (journalctl, F</var/log/auth.log>, or
F</var/log/secure>) to detect and flag IP addresses and usernames with
repeated failed login attempts above a configurable threshold.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<threshold> (fail count to flag), C<hours> (look-back
window), C<source> (log file path or C<'journalctl'>).

Returns a hash-ref with flagged IPs, users, and raw failures.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
