package HBPerl::Scheduler;
# ============================================================================
# HBPerl::Scheduler - Schedule HB Perl scripts via crontab (v2.0)
# ============================================================================
use strict;
use warnings;
use Carp qw(croak carp);

our $VERSION = '2.00';

# Sentinel comment that marks an HB Perl cron entry
my $MARKER = '# hbperl-job';

# ── Public API ────────────────────────────────────────────────────────────────

=head1 NAME

HBPerl::Scheduler - Crontab-based job scheduler for HB Perl scripts

=head1 SYNOPSIS

    use HBPerl::Scheduler;

    HBPerl::Scheduler::add_job(
        script   => 'system_info',
        schedule => '0 * * * *',
    );

    my @jobs = HBPerl::Scheduler::list_jobs();

    HBPerl::Scheduler::remove_job('system_info');

=head1 FUNCTIONS

=head2 add_job(%args)

Add a crontab entry for a HB Perl script.

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

Return a list of hashrefs, each describing a scheduled HB Perl job:
C<{ script, schedule, args, raw_line }>.

=cut

sub list_jobs {
    my @jobs;
    for my $line (_read_crontab()) {
        next unless $line =~ /\Q$MARKER\E\s+script=(\S+)/;
        my $script = $1;
        # Extract the 5-field cron schedule from the beginning of the line
        my ($schedule, $cmd_rest) = _split_cron_line($line);
        my $args = '';
        if ($cmd_rest && $cmd_rest =~ /--\s+(.*)$MARKER/) {
            $args = $1;
            $args =~ s/\s+$//;
        }
        push @jobs, {
            script   => $script,
            schedule => $schedule // '?',
            args     => $args,
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
    # Basic: must have 5 whitespace-separated fields
    my @fields = split /\s+/, $expr;
    croak "Cron expression must have exactly 5 fields: '$expr'"
        unless @fields == 5;
}

sub _hbperl_cli_path {
    # Prefer the real binary if findable; otherwise fall back to plain name
    require FindBin;
    FindBin->import;
    my $cli = "$FindBin::RealBin/hb_perl_cli";
    return -f $cli ? $cli : 'hb_perl_cli';
}

1;

__END__

=head1 AUTHOR

James-HoneyBadger

=head1 LICENSE

MIT

=cut
