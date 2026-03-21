package HBPerl::Scripts::LogAnalyzer;
# ============================================================================
# Parse and analyze system log files (syslog, auth.log, journalctl)
# ============================================================================
use strict;
use warnings;
use POSIX qw(strftime);

sub run {
    my (%args) = @_;
    my $log_file  = $args{log_file}  // _find_syslog();
    my $max_lines = $args{max_lines} // 5000;
    my $pattern   = $args{pattern}   // '';

    my @entries;
    my %severity_count;
    my %source_count;
    my %hourly;

    my $fh;
    if ($log_file eq 'journalctl') {
        my $n = int($max_lines || 5000);
        open $fh, '-|', 'journalctl', '--no-pager', '-n', $n
            or return { error => "Cannot run journalctl: $!" };
    } elsif (-f $log_file && -r $log_file) {
        open $fh, '<', $log_file
            or return { error => "Cannot open $log_file: $!" };
    } else {
        return { error => "Log file not found or not readable: $log_file" };
    }

    # Pre-compile user pattern to catch invalid regex early
    my $compiled_pattern;
    if ($pattern) {
        $compiled_pattern = eval { qr/$pattern/i };
        if (!$compiled_pattern) {
            close $fh;
            (my $err = $@) =~ s/ at .+//s;
            return { error => "Invalid regex pattern '$pattern': $err" };
        }
    }

    my $count = 0;
    while (my $line = <$fh>) {
        chomp $line;
        last if $count >= $max_lines;

        # Apply pattern filter
        if ($compiled_pattern) {
            next unless $line =~ $compiled_pattern;
        }

        # Parse syslog format: Mon DD HH:MM:SS hostname process[pid]: message
        if ($line =~ /^(\w+\s+\d+\s+\d+:\d+:\d+)\s+(\S+)\s+(\S+?)(?:\[(\d+)\])?:\s+(.*)/) {
            my ($timestamp, $host, $source, $pid, $message) = ($1, $2, $3, $4, $5);

            my $severity = _guess_severity($message);
            $severity_count{$severity}++;
            $source_count{$source}++;

            if ($timestamp =~ /(\d+):/) {
                $hourly{$1}++;
            }

            push @entries, {
                timestamp => $timestamp,
                host      => $host,
                source    => $source,
                pid       => $pid // '',
                message   => $message,
                severity  => $severity,
            };
            $count++;
        }
        # systemd journal format
        elsif ($line =~ /^(\w+\s+\d+\s+\d+:\d+:\d+)\s+(\S+)\s+(.+)/) {
            my ($timestamp, $host, $rest) = ($1, $2, $3);
            my $severity = _guess_severity($rest);
            $severity_count{$severity}++;

            if ($timestamp =~ /(\d+):/) {
                $hourly{$1}++;
            }

            push @entries, {
                timestamp => $timestamp,
                host      => $host,
                source    => 'journal',
                message   => $rest,
                severity  => $severity,
            };
            $count++;
        }
    }
    close $fh;

    # Top sources
    my @top_sources = sort { $source_count{$b} <=> $source_count{$a} }
                      keys %source_count;
    splice @top_sources, 15;

    return {
        log_file       => $log_file,
        total_entries  => $count,
        entries        => \@entries,
        severity_count => \%severity_count,
        source_count   => \%source_count,
        top_sources    => \@top_sources,
        hourly         => \%hourly,
    };
}

sub format_report {
    my ($result) = @_;

    if ($result->{error}) {
        return "ERROR: $result->{error}\n";
    }

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                    LOG ANALYZER                              ║
╚══════════════════════════════════════════════════════════════╝

Log file: $result->{log_file}
Total entries analyzed: $result->{total_entries}

── Severity Breakdown ────────────────────────────────────────
EOF

    for my $sev (qw(error warning notice info debug)) {
        my $count = $result->{severity_count}{$sev} // 0;
        my $marker = $sev eq 'error' ? '✗' : $sev eq 'warning' ? '⚠' : '●';
        $report .= sprintf("  %s %-10s %d\n", $marker, uc($sev), $count);
    }

    $report .= "\n── Top Sources ───────────────────────────────────────────────\n";
    for my $src (@{$result->{top_sources}}) {
        $report .= sprintf("  %-30s %d\n", $src, $result->{source_count}{$src});
    }

    $report .= "\n── Hourly Activity ───────────────────────────────────────────\n";
    my $max_h = 1;
    for (values %{$result->{hourly}}) { $max_h = $_ if $_ > $max_h }
    for my $h (sort keys %{$result->{hourly}}) {
        my $count = $result->{hourly}{$h};
        my $bar = '█' x int(40 * $count / $max_h);
        $report .= sprintf("  %02d:00  %4d  %s\n", $h, $count, $bar);
    }

    $report .= "\n── Recent Error/Warning Entries ───────────────────────────────\n";
    my $shown = 0;
    for my $e (reverse @{$result->{entries}}) {
        last if $shown >= 20;
        next unless $e->{severity} =~ /error|warning/;
        $report .= "  [$e->{severity}] $e->{timestamp} $e->{source}: $e->{message}\n";
        $shown++;
    }

    return $report;
}

sub _guess_severity {
    my ($msg) = @_;
    return 'error'   if $msg =~ /\b(error|fail(?:ed|ure)?|fatal|crit(?:ical)?|panic|segfault|denied|out of memory|killed process|oom)\b/i;
    return 'warning' if $msg =~ /\b(warn(?:ing)?|timeout|retry|refused|invalid|reject(?:ed)?|flooding)\b/i;
    return 'notice'  if $msg =~ /\b(notice|started|stopped|accepted|session)\b/i;
    return 'info';
}

sub _find_syslog {
    for my $f (qw(/var/log/syslog /var/log/messages)) {
        return $f if -f $f && -r $f;
    }
    return 'journalctl';
}

1;

__END__

=head1 NAME

HBPerl::Scripts::LogAnalyzer - System log parsing and analysis

=head1 SYNOPSIS

    use HBPerl::Scripts::LogAnalyzer;
    my $r = HBPerl::Scripts::LogAnalyzer::run(
        log_file  => '/var/log/syslog',
        max_lines => 5000,
        pattern   => 'error|fail',
    );
    print HBPerl::Scripts::LogAnalyzer::format_report($r);

=head1 DESCRIPTION

Parses syslog-format or journalctl log files, classifies entries by
severity (error, warning, info), counts messages by source and hour,
and highlights recent errors and warnings.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<log_file> (path or C<'journalctl'>), C<max_lines>
(tail limit), C<pattern> (regex filter).

Returns a hash-ref with line counts, severity breakdown, top sources,
and hourly distribution.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut
