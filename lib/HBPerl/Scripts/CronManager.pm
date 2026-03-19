package HBPerl::Scripts::CronManager;
# ============================================================================
# Cron manager — list, validate, and analyse crontabs
# ============================================================================
use strict;
use warnings;
use POSIX qw(strftime);

sub run {
    my (%args) = @_;
    my $user = $args{user};   # undef = all users (requires root for others)

    my %result;

    # ── User Crontabs ──
    $result{user_crons} = _get_user_crons($user);

    # ── System Crontabs ──
    $result{system_crons} = _get_system_crons();

    # ── Cron.d entries ──
    $result{cron_d} = _get_cron_d();

    # ── Anacron ──
    $result{anacron} = _get_anacron();

    # ── Systemd Timers (modern replacement) ──
    $result{timers} = _get_systemd_timers();

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                     CRON MANAGER                              ║
╚══════════════════════════════════════════════════════════════╝

EOF

    # User crontabs
    $report .= "── User Crontabs ─────────────────────────────────────────────\n";
    for my $user (sort keys %{$result->{user_crons} // {}}) {
        my @entries = @{$result->{user_crons}{$user}};
        $report .= "\n  [$user] — " . scalar(@entries) . " entries\n";
        for my $e (@entries) {
            if ($e->{type} eq 'job') {
                $report .= sprintf("    %-35s %s\n", $e->{schedule}, $e->{command});
            } elsif ($e->{type} eq 'env') {
                $report .= "    ENV: $e->{line}\n";
            }
        }
    }

    # System crontab
    $report .= "\n── System Crontab (/etc/crontab) ─────────────────────────────\n";
    for my $e (@{$result->{system_crons} // []}) {
        if ($e->{type} eq 'job') {
            $report .= sprintf("    %-35s %-10s %s\n",
                $e->{schedule}, $e->{user} // '', $e->{command});
        }
    }

    # /etc/cron.d
    $report .= "\n── /etc/cron.d Entries ────────────────────────────────────────\n";
    for my $file (sort keys %{$result->{cron_d} // {}}) {
        my @entries = @{$result->{cron_d}{$file}};
        $report .= "\n  [$file] — " . scalar(@entries) . " entries\n";
        for my $e (@entries) {
            if ($e->{type} eq 'job') {
                $report .= sprintf("    %-35s %-10s %s\n",
                    $e->{schedule}, $e->{user} // '', $e->{command});
            }
        }
    }

    # Systemd timers
    $report .= "\n── Systemd Timers ────────────────────────────────────────────\n";
    if (@{$result->{timers} // []}) {
        $report .= sprintf("  %-30s %-20s %s\n", 'Timer', 'Next Run', 'Unit');
        $report .= "  " . ("-" x 72) . "\n";
        for my $t (@{$result->{timers}}) {
            $report .= sprintf("  %-30s %-20s %s\n",
                $t->{timer}, $t->{next} // 'n/a', $t->{unit} // '');
        }
    } else {
        $report .= "  No active timers found.\n";
    }

    return $report;
}

sub _get_user_crons {
    my ($user) = @_;
    my %crons;

    if ($user) {
        # Validate username to prevent injection
        return \%crons unless $user =~ /^[a-zA-Z0-9._-]+$/;
        my $output;
        if (open(my $fh, '-|', 'crontab', '-l', '-u', $user)) {
            local $/; $output = <$fh>; close $fh;
        }
        $crons{$user} = _parse_crontab($output) if $output;
    } else {
        # Current user
        my $output;
        if (open(my $fh, '-|', 'crontab', '-l')) {
            local $/; $output = <$fh>; close $fh;
        }
        my $me = $ENV{USER} // getpwuid($<);
        $crons{$me} = _parse_crontab($output) if $output && $output !~ /no crontab/;

        # Try other users if root
        if ($< == 0) {
            if (open my $fh, '<', '/etc/passwd') {
                while (<$fh>) {
                    my ($uname) = split /:/;
                    next if $uname eq $me;
                    next unless $uname =~ /^[a-zA-Z0-9._-]+$/;
                    my $out;
                    if (open(my $cfh, '-|', 'crontab', '-l', '-u', $uname)) {
                        local $/; $out = <$cfh>; close $cfh;
                    }
                    $crons{$uname} = _parse_crontab($out)
                        if $out && $out !~ /no crontab/;
                }
                close $fh;
            }
        }
    }

    return \%crons;
}

sub _get_system_crons {
    return [] unless -f '/etc/crontab';
    my $content = _slurp('/etc/crontab');
    return _parse_crontab($content, 1);   # system format has user field
}

sub _get_cron_d {
    my %result;
    my $dir = '/etc/cron.d';
    return \%result unless -d $dir;
    opendir my $dh, $dir or return \%result;
    while (my $f = readdir $dh) {
        next if $f =~ /^\./;
        my $path = "$dir/$f";
        next unless -f $path;
        my $content = _slurp($path);
        $result{$f} = _parse_crontab($content, 1);
    }
    closedir $dh;
    return \%result;
}

sub _get_anacron {
    return [] unless -f '/etc/anacrontab';
    my @entries;
    if (open my $fh, '<', '/etc/anacrontab') {
        while (<$fh>) {
            chomp;
            next if /^\s*#/ || /^\s*$/;
            if (/^(\d+)\s+(\d+)\s+(\S+)\s+(.+)/) {
                push @entries, {
                    period  => $1,
                    delay   => $2,
                    id      => $3,
                    command => $4,
                };
            }
        }
        close $fh;
    }
    return \@entries;
}

sub _get_systemd_timers {
    my @timers;
    my @lines = `systemctl list-timers --no-pager --plain 2>/dev/null`;
    shift @lines;   # header
    for my $line (@lines) {
        chomp $line;
        last if $line =~ /^\s*$/;
        last if $line =~ /^\d+ timers/;
        # Format varies; try to grab timer name and unit
        my @fields = split /\s+/, $line;
        next unless @fields >= 2;
        # The last two fields are typically TIMER and ACTIVATES
        my $activates = pop @fields;
        my $timer = pop @fields;
        my $next = join(' ', @fields);
        push @timers, { timer => $timer, unit => $activates, next => $next };
    }
    return \@timers;
}

sub _parse_crontab {
    my ($text, $has_user) = @_;
    my @entries;
    return \@entries unless $text;

    for my $line (split /\n/, $text) {
        chomp $line;
        next if $line =~ /^\s*$/;

        # Comments
        next if $line =~ /^\s*#/;

        # Environment variable
        if ($line =~ /^\s*(\w+)\s*=\s*(.*)/) {
            push @entries, { type => 'env', var => $1, val => $2, line => $line };
            next;
        }

        # Cron job: 5 time fields + optional user + command
        if ($line =~ /^\s*(@\w+|\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(.+)/) {
            my ($sched, $rest) = ($1, $2);
            my %entry = (type => 'job', schedule => $sched);
            if ($has_user && $rest =~ /^(\S+)\s+(.+)/) {
                $entry{user}    = $1;
                $entry{command} = $2;
            } else {
                $entry{command} = $rest;
            }
            push @entries, \%entry;
        }
    }
    return \@entries;
}

sub _slurp {
    my ($f) = @_;
    open my $fh, '<', $f or return '';
    local $/;
    my $c = <$fh>;
    close $fh;
    return $c;
}

1;

__END__

=head1 NAME

HBPerl::Scripts::CronManager - Cron job listing and analysis

=head1 SYNOPSIS

    use HBPerl::Scripts::CronManager;
    my $r = HBPerl::Scripts::CronManager::run(user => 'root');
    print HBPerl::Scripts::CronManager::format_report($r);

=head1 DESCRIPTION

Lists and analyses scheduled tasks from user crontabs, system-wide
F</etc/crontab>, F</etc/cron.d/> entries, anacron jobs, and systemd
timers.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<user> (username, defaults to current user).

Returns a hash-ref containing cron jobs, system crons, anacron jobs,
and systemd timers.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
