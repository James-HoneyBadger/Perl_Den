package BadgerOps::Scripts::ProcessManager;
# ============================================================================
# List, analyze, and manage running processes
# ============================================================================
use strict;
use warnings;

sub run {
    my (%args) = @_;
    my $sort_by  = $args{sort_by}  // 'cpu';   # cpu, mem, pid, time
    my $top_n    = $args{top_n}    // 25;
    my $filter   = $args{filter}   // '';

    my @processes;

    # Parse ps output (more portable than Proc::ProcessTable for display)
    my @lines;
    if (open my $fh, '-|', 'ps', 'aux', '--sort=-%cpu') {
        @lines = <$fh>;
        close $fh;
    }
    shift @lines;  # header

    for my $line (@lines) {
        my @f = split /\s+/, $line, 11;
        next unless @f >= 11;

        my $proc = {
            user    => $f[0],
            pid     => $f[1] + 0,
            cpu     => $f[2] + 0,
            mem     => $f[3] + 0,
            vsz     => $f[4] + 0,
            rss     => $f[5] + 0,
            tty     => $f[6],
            stat    => $f[7],
            start   => $f[8],
            time    => $f[9],
            command => $f[10] // '',
        };

        # Apply filter
        if ($filter) {
            next unless $proc->{command} =~ /\Q$filter\E/i
                     || $proc->{user} =~ /\Q$filter\E/i
                     || $proc->{pid} == $filter;
        }

        push @processes, $proc;
    }

    # Sort
    if ($sort_by eq 'mem') {
        @processes = sort { $b->{mem} <=> $a->{mem} } @processes;
    } elsif ($sort_by eq 'pid') {
        @processes = sort { $a->{pid} <=> $b->{pid} } @processes;
    } elsif ($sort_by eq 'rss') {
        @processes = sort { $b->{rss} <=> $a->{rss} } @processes;
    }
    # Default is already sorted by CPU

    splice @processes, $top_n if @processes > $top_n;

    # Find zombies
    my @zombies = grep { $_->{stat} =~ /^Z/ } @processes;

    # Find high-CPU processes
    my @high_cpu = grep { $_->{cpu} > 80 } @processes;

    # Count by user
    my %by_user;
    $by_user{$_->{user}}++ for @processes;

    return {
        processes  => \@processes,
        zombies    => \@zombies,
        high_cpu   => \@high_cpu,
        by_user    => \%by_user,
        total      => scalar @processes,
    };
}

sub format_report {
    my ($result) = @_;
    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                    PROCESS MANAGER                           ║
╚══════════════════════════════════════════════════════════════╝

Total processes shown: $result->{total}
EOF

    if (@{$result->{zombies}}) {
        $report .= "\n⚠  ZOMBIE PROCESSES: " . scalar(@{$result->{zombies}}) . "\n";
        for my $z (@{$result->{zombies}}) {
            $report .= "   PID $z->{pid}: $z->{command}\n";
        }
    }

    if (@{$result->{high_cpu}}) {
        $report .= "\n⚠  HIGH CPU (>80%):\n";
        for my $p (@{$result->{high_cpu}}) {
            $report .= "   PID $p->{pid} ($p->{cpu}%): $p->{command}\n";
        }
    }

    $report .= "\n── Process List ──────────────────────────────────────────────\n";
    $report .= sprintf("  %6s  %-10s %5s %5s %8s  %s\n",
        'PID', 'USER', 'CPU%', 'MEM%', 'RSS(KB)', 'COMMAND');
    $report .= "  " . "-" x 65 . "\n";

    for my $p (@{$result->{processes}}) {
        my $cmd = length($p->{command}) > 45
            ? substr($p->{command}, 0, 45) . '...'
            : $p->{command};
        $report .= sprintf("  %6d  %-10s %5.1f %5.1f %8d  %s\n",
            $p->{pid}, $p->{user}, $p->{cpu}, $p->{mem}, $p->{rss}, $cmd);
    }

    $report .= "\n── Processes by User ─────────────────────────────────────────\n";
    for my $user (sort { $result->{by_user}{$b} <=> $result->{by_user}{$a} }
                  keys %{$result->{by_user}}) {
        $report .= sprintf("  %-15s %d\n", $user, $result->{by_user}{$user});
    }

    return $report;
}

sub metadata {
    return {
        name        => 'Process Manager',
        filename    => 'process_manager.pl',
        description => 'List and manage running processes',
        category    => 'System Info',
        icon        => 'computer-symbolic',
        emoji       => '🖥',
    };
}

1;

__END__

=head1 NAME

BadgerOps::Scripts::ProcessManager - Process listing and analysis

=head1 SYNOPSIS

    use BadgerOps::Scripts::ProcessManager;
    my $r = BadgerOps::Scripts::ProcessManager::run(
        sort_by => 'cpu',
        top_n   => 20,
        filter  => 'perl',
    );
    print BadgerOps::Scripts::ProcessManager::format_report($r);

=head1 DESCRIPTION

Parses C<ps aux> output to list, sort, and filter running processes.
Flags zombies and high-CPU consumers and provides summary statistics.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<sort_by> (cpu|mem|pid|rss), C<top_n> (number of
processes to return), C<filter> (regex to match command lines).

Returns a hash-ref with process list, zombie list, and totals.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 RETURNS

C<run()> returns a hashref with:

=over 4

=item C<processes>

Arrayref of process hashrefs C<{ pid, name, user, cpu, mem, vsz, rss, stat, start, cmd }>.

=item C<zombies>

Arrayref of zombie process hashrefs (subset of C<processes> where state is C<Z>).

=item C<high_cpu>

Arrayref of processes with CPU usage above the threshold (default 5%).

=item C<by_user>

Hashref of username E<rarr> process count.

=item C<total>

Total number of processes returned.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
