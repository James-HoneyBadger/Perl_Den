package PerlDen::Scheduler;
# ============================================================================
# PerlDen::Scheduler - Schedule Perl Den scripts via crontab (v2.0)
# ============================================================================
use strict;
use warnings;
use Carp qw(croak carp);

our $VERSION = '2.01';

# Sentinel comment that marks an Perl Den cron entry
my $MARKER = '# hbperl-job';

# ── Public API ────────────────────────────────────────────────────────────────

=head1 NAME

PerlDen::Scheduler - Crontab-based job scheduler for Perl Den scripts

=head1 SYNOPSIS

    use PerlDen::Scheduler;

    PerlDen::Scheduler::add_job(
        script   => 'system_info',
        schedule => '0 * * * *',
    );

    my @jobs = PerlDen::Scheduler::list_jobs();

    PerlDen::Scheduler::remove_job('system_info');

=head1 FUNCTIONS

=head2 add_job(%args)

Add a crontab entry for a Perl Den script.

Required: C<script>, C<schedule> (standard 5-field cron expression).
Optional: C<args> (string of extra arguments to pass to the script).

Dies if the script name is already scheduled; use remove_job() first.

=cut

sub add_job {
    my %args = @_;
    croak 'add_job: script is required'   unless $args{script};
    croak 'add_job: schedule is required' unless $args{schedule};

    _validate_script_name($args{script});
    _validate_cron_expr($args{schedule});

    my @lines = _read_crontab();
    if (grep { /$MARKER\s+script=\Q$args{script}\E\b/ } @lines) {
        croak "Job for '$args{script}' is already scheduled. Remove it first.\n";
    }

    # Build the hbperl-run command path
    my $cmd = _hbperl_cli_path() . " run $args{script}";
    $cmd   .= " -- $args{args}" if $args{args};
    my $entry = "$args{schedule} $cmd $MARKER script=$args{script}";

    push @lines, $entry;
    _write_crontab(@lines);
    return 1;
}

=head2 list_jobs()

Return a list of hashrefs, each describing a scheduled Perl Den job:
C<{ script, schedule, args, raw_line }>.

=cut

sub list_jobs {
    my @jobs;
    for my $line (_read_crontab()) {
        my ($disabled, $inner) = (0, $line);

        # Detect disabled entries (prefixed with '# DISABLED: ...')
        if ($line =~ /^#\s*DISABLED:\s*(.+)$/) {
            $inner    = $1;
            $disabled = 1;
        }

        next unless $inner =~ /\Q$MARKER\E\s+script=(\S+)/;
        my $script = $1;
        my ($schedule, $cmd_rest) = _split_cron_line($inner);
        my $args = '';
        if ($cmd_rest && $cmd_rest =~ /--\s+(.*)$MARKER/) {
            $args = $1;
            $args =~ s/\s+$//;
        }
        push @jobs, {
            script   => $script,
            schedule => $schedule // '?',
            args     => $args,
            enabled  => !$disabled,
            raw_line => $line,
        };
    }
    return @jobs;
}

=head2 remove_job($script_name)

Remove the crontab entry for the given script.
Returns 1 if a job was found and removed, 0 otherwise.

=cut

sub remove_job {
    my ($script) = @_;
    croak 'remove_job: script name is required' unless $script;

    my @lines = _read_crontab();
    my $before = scalar @lines;
    @lines = grep { !/$MARKER\s+script=\Q$script\E\b/ } @lines;

    if (scalar @lines == $before) {
        return 0;   # nothing removed
    }
    _write_crontab(@lines);
    return 1;
}

=head2 disable_job($script_name)

Disable a scheduled job without removing it. The crontab entry is
commented out with a C<# DISABLED:> prefix so it can be re-enabled later.

Dies if no active job for the script is found.

=cut

sub disable_job {
    my ($script) = @_;
    croak 'disable_job: script name is required' unless $script;
    _validate_script_name($script);

    my @lines = _read_crontab();
    my $found  = 0;
    @lines = map {
        if (/$MARKER\s+script=\Q$script\E\b/ && !/^#\s*DISABLED:/) {
            $found = 1;
            "# DISABLED: $_";
        } else {
            $_;
        }
    } @lines;
    croak "No active scheduled job found for '$script'\n" unless $found;
    _write_crontab(@lines);
    return 1;
}

=head2 enable_job($script_name)

Re-enable a previously disabled scheduled job.

Dies if no disabled job for the script is found.

=cut

sub enable_job {
    my ($script) = @_;
    croak 'enable_job: script name is required' unless $script;
    _validate_script_name($script);

    my @lines = _read_crontab();
    my $found  = 0;
    @lines = map {
        if (/^#\s*DISABLED:\s*(.+)$/) {
            my $inner = $1;
            if ($inner =~ /\Q$MARKER\E\s+script=\Q$script\E\b/) {
                $found = 1;
                $inner;   # restore the original un-commented line
            } else {
                $_;
            }
        } else {
            $_;
        }
    } @lines;
    croak "No disabled scheduled job found for '$script'\n" unless $found;
    _write_crontab(@lines);
    return 1;
}

# ── Private helpers ───────────────────────────────────────────────────────────

sub _read_crontab {
    my $raw = qx{crontab -l 2>/dev/null} // '';
    return split /\n/, $raw;
}

sub _write_crontab {
    my @lines = @_;
    # Remove trailing blank lines but keep one final newline
    while (@lines && $lines[-1] =~ /^\s*$/) { pop @lines }
    my $content = join("\n", @lines) . "\n";

    require File::Temp;
    my ($fh, $tmpfile) = File::Temp::tempfile(UNLINK => 1, SUFFIX => '.crontab');
    print $fh $content;
    close $fh;

    my $ret = system('crontab', $tmpfile);
    die "crontab command failed (exit $ret)\n" if $ret != 0;
}

sub _split_cron_line {
    my ($line) = @_;
    # A standard cron line starts with 5 whitespace-delimited fields
    if ($line =~ /^(\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(.*)$/) {
        return ($1, $2);
    }
    return (undef, $line);
}

sub _validate_script_name {
    my ($name) = @_;
    croak "Invalid script name '$name'" unless $name =~ /\A[A-Za-z0-9_\-]+\z/;
}

sub _validate_cron_expr {
    my ($expr) = @_;
    my @fields = split /\s+/, $expr;
    croak "Cron expression must have exactly 5 fields: '$expr'"
        unless @fields == 5;

    my @ranges = ([0, 59], [0, 23], [1, 31], [1, 12], [0, 7]);
    my @names  = qw(minute hour day-of-month month day-of-week);

    for my $i (0 .. $#fields) {
        my $f = $fields[$i];
        my ($min, $max) = @{$ranges[$i]};
        for my $part (split /,/, $f) {
            if ($part eq '*') {
                next;
            } elsif ($part =~ m{^\*/(\d+)$}) {
                croak "Invalid step '0' in $names[$i] field" if $1 == 0;
            } elsif ($part =~ /^(\d+)-(\d+)$/) {
                my ($lo, $hi) = ($1 + 0, $2 + 0);
                croak "$names[$i] range $lo-$hi invalid (lo > hi)" if $lo > $hi;
                croak "$names[$i] value $lo out of range [$min-$max]" unless $lo >= $min && $lo <= $max;
                croak "$names[$i] value $hi out of range [$min-$max]" unless $hi >= $min && $hi <= $max;
            } elsif ($part =~ /^(\d+)$/) {
                my $v = $1 + 0;
                croak "$names[$i] value $v out of range [$min-$max]" unless $v >= $min && $v <= $max;
            } else {
                croak "Invalid cron field '$part' in $names[$i]";
            }
        }
    }
}

sub _hbperl_cli_path {
    # Prefer the real binary if findable; otherwise fall back to plain name
    require FindBin;
    FindBin->import;
    my $cli = "$FindBin::RealBin/perlden-cli";
    return -f $cli ? $cli : 'perlden-cli';
}

1;

__END__

=head1 AUTHOR

James-HoneyBadger

=head1 LICENSE

MIT

=cut
