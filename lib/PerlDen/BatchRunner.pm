package PerlDen::BatchRunner;
# ============================================================================
# PerlDen::BatchRunner - Run multiple toolkit scripts sequentially
# ============================================================================
use strict;
use warnings;
use feature 'state';
use Carp qw(croak);
use Scalar::Util qw(looks_like_number);
use Try::Tiny;
use PerlDen::ScriptRegistry qw(script_index find_script);

our $VERSION = '2.01';

# Mapping from notification config value to when we fire
my %NOTIFY_MODES = ( always => 1, errors => 1, off => 1 );

sub new {
    my ($class, %args) = @_;
    return bless {
        on_progress => $args{on_progress} // sub {},
        on_error    => $args{on_error}    // sub {},
    }, $class;
}

sub run_batch {
    my ($self, @script_names) = @_;
    my $opts           = ref $script_names[-1] eq 'HASH' ? pop @script_names : {};
    my $timeout_secs   = $opts->{timeout_seconds} // 0;
    croak 'No scripts specified' unless @script_names;

    my @results;
    my $total = scalar @script_names;

    for my $i (0 .. $#script_names) {
        my $name = $script_names[$i];
        $self->{on_progress}->($name, $i + 1, $total);

        my @match = find_script($name);
        unless (@match) {
            my $err = { name => $name, error => "Unknown script: $name" };
            push @results, $err;
            $self->{on_error}->($name, $err->{error});
            next;
        }

        my ($display, $file, $module, $desc, $category) = @match;

        # Validate module name to prevent code injection via string eval
        unless ($module =~ /\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/) {
            my $err = { name => $display, error => "Invalid module name: $module" };
            push @results, $err;
            $self->{on_error}->($display, $err->{error});
            next;
        }

        # Load the module dynamically using path-based require (avoids string eval)
        (my $module_path = "$module.pm") =~ s{::}{/}g;
        my $loaded = 0;
        try {
            require $module_path;
            $loaded = 1;
        } catch {
            my $err = { name => $display, error => "Failed to load $module: $_" };
            push @results, $err;
            $self->{on_error}->($display, $err->{error});
        };
        next unless $loaded;

        # Run the script module's run() function (call as function, not method)
        my $run_fn = $module->can('run');
        my ($result, $run_err);
        local $SIG{ALRM} = $timeout_secs > 0
            ? sub { die "Script timed out after ${timeout_secs}s\n" }
            : ($SIG{ALRM} // sub {});
        alarm($timeout_secs) if $timeout_secs > 0;
        try {
            $result = $run_fn ? $run_fn->() : undef;
            die 'run() returned nothing' unless $result;
        } catch {
            $run_err = $_;
        };
        alarm(0) if $timeout_secs > 0;
        if ($run_err) {
            push @results, { name => $display, error => "Execution failed: $run_err" };
            $self->{on_error}->($display, $run_err);
            next;
        }

        # Format the report if available
        my $report = '';
        my $fmt_fn = $module->can('format_report');
        if ($fmt_fn) {
            try   { $report = $fmt_fn->($result) // '' }
            catch { $report = "[format_report error: $_]" };
        } else {
            $report = "[No format_report defined for $display]";
        }

        push @results, {
            name     => $display,
            category => $category,
            data     => $result,
            report   => $report,
        };
    }

    _maybe_notify(\@results);
    return \@results;
}

# Run scripts in parallel using fork(). Results are aggregated in start order.
# Pass { parallel => 1 } (or { parallel => N } for max N workers) in opts.
# Uses a worker-pool model: at most $max_workers children live at once.
sub run_batch_parallel {
    my ($self, @script_names) = @_;
    my $opts        = ref $script_names[-1] eq 'HASH' ? pop @script_names : {};
    my $max_workers = (looks_like_number($opts->{parallel}) && $opts->{parallel} > 1)
                        ? $opts->{parallel}
                        : 4;
    croak 'No scripts specified' unless @script_names;
    require Storable;
    require POSIX;

    my $total   = scalar @script_names;
    my %results;  # index => hashref
    my @queue   = (0 .. $#script_names);   # indices to process
    my %running;  # pid => { index, rfh }

    while (@queue || %running) {
        # Spawn up to max_workers
        while (@queue && keys(%running) < $max_workers) {
            my $idx  = shift @queue;
            my $name = $script_names[$idx];

            # Create a pipe for the child to send its result back
            pipe(my $rfh, my $wfh) or do { warn "pipe: $!\n"; next };

            my $pid = fork();
            if (!defined $pid) { warn "fork: $!\n"; next }

            if ($pid == 0) {
                # Child: run single script via sequential batch, send result over pipe
                close $rfh;
                my $r = eval {
                    $self->run_batch($name, { timeout_seconds => $opts->{timeout_seconds} // 0 })
                };
                my $res = $@ ? [{ name => $name, error => "Child died: $@" }] : $r;
                # Serialise result through the pipe
                my $frozen = Storable::nfreeze($res);
                print $wfh pack('N', length($frozen)), $frozen;
                close $wfh;
                exit 0;
            }

            # Parent: record running child
            close $wfh;
            $running{$pid} = { index => $idx, rfh => $rfh };
        }

        # Wait for at least one child to finish
        my $done_pid = waitpid(-1, POSIX::WNOHANG());
        if ($done_pid > 0 && exists $running{$done_pid}) {
            my $info = delete $running{$done_pid};
            my $rfh  = $info->{rfh};
            my ($len_buf, $frozen);
            if (read($rfh, $len_buf, 4) == 4) {
                my $len = unpack('N', $len_buf);
                read($rfh, $frozen, $len);
                my $res = eval { Storable::thaw($frozen) };
                $results{$info->{index}} = $res // [{ name => $script_names[$info->{index}], error => 'Deserialise failed' }];
            } else {
                $results{$info->{index}} = [{ name => $script_names[$info->{index}], error => 'No data from child' }];
            }
            close $rfh;
        } elsif (!%running) {
            last;  # no children left
        }
    }

    # Flatten results in original order
    my @all = map { @{ $results{$_} // [{ name => $script_names[$_], error => 'No result' }] } } 0 .. $#script_names;
    _maybe_notify(\@all);
    return \@all;
}

# Send a desktop notification after a batch run (non-blocking, best-effort)
sub _maybe_notify {
    my ($results) = @_;
    # Avoid loading Config unless already in %INC (prevent circular dependency
    # if BatchRunner is loaded very early; also skips notify if Config unavailable)
    return unless exists $INC{'PerlDen/Config.pm'};
    require PerlDen::Config;
    my $mode = PerlDen::Config::get('notifications') // 'errors';
    return if $mode eq 'off';

    my $fail = grep { $_->{error} } @$results;
    my $ok   = @$results - $fail;

    # 'errors' mode: only notify when there are failures
    return if $mode eq 'errors' && !$fail;

    my $summary = "Perl Den batch complete";
    my $body    = "$ok succeeded" . ($fail ? ", $fail FAILED" : '');
    my $urgency = $fail ? 'critical' : 'normal';
    my $icon    = $fail ? 'dialog-error' : 'dialog-information';

    _send_notification($urgency, $icon, $summary, $body);
}

# Try notification backends in order: notify-send → dbus-send → stderr
sub _send_notification {
    my ($urgency, $icon, $summary, $body) = @_;
    if (_has_cmd('notify-send')) {
        system('notify-send', '--urgency', $urgency, '--icon', $icon, $summary, $body);
        return;
    }
    if (_has_cmd('dbus-send')) {
        # List-form system() — args passed directly, no shell injection risk
        system('dbus-send', '--session',
            '--dest=org.freedesktop.Notifications',
            '/org/freedesktop/Notifications',
            'org.freedesktop.Notifications.Notify',
            'string:Perl Den', 'uint32:0', "string:$icon",
            "string:$summary", "string:$body",
            'array:string:', 'dict:string:variant:', 'int32:5000');
        return;
    }
    # Final fallback: log to STDERR
    warn "Perl Den: $summary \x{2014} $body\n";
}

sub _has_cmd {
    my ($cmd) = @_;
    state %cache;
    return $cache{$cmd} if exists $cache{$cmd};
    $cache{$cmd} = !system("which \Q$cmd\E >/dev/null 2>&1");
    return $cache{$cmd};
}

sub format_batch_report {
    my ($self, $results) = @_;
    $results //= [];

    my $divider = '=' x 72;
    my $report  = "\n$divider\n";
    $report .= "  PERLDEN BATCH REPORT — " . scalar(@$results) . " script(s)\n";
    $report .= "$divider\n\n";

    my ($ok, $fail) = (0, 0);

    for my $r (@$results) {
        if ($r->{error}) {
            $fail++;
            $report .= "✗ $r->{name}: ERROR — $r->{error}\n\n";
        } else {
            $ok++;
            $report .= $r->{report} . "\n" if $r->{report};
        }
    }

    $report .= "$divider\n";
    $report .= "  Summary: $ok succeeded, $fail failed\n";
    $report .= "$divider\n";

    return $report;
}

# Export batch results as 'text' (default), 'html', or 'json'
sub export_report {
    my ($self, $results, %opts) = @_;
    my $format = lc($opts{format} // 'text');
    $results //= [];

    if ($format eq 'json') {
        return _export_json($results);
    } elsif ($format eq 'html') {
        return _export_html($results, $self);
    } else {
        return $self->format_batch_report($results);
    }
}

sub _export_json {
    my ($results) = @_;
    require JSON::MaybeXS;
    my $json = JSON::MaybeXS->new(utf8 => 1, pretty => 1, canonical => 1);
    my @out;
    for my $r (@$results) {
        push @out, {
            name     => $r->{name}     // '',
            category => $r->{category} // '',
            error    => $r->{error}    // undef,
            report   => $r->{report}   // '',
        };
    }
    return $json->encode({ generated => _timestamp(), results => \@out });
}

sub _export_html {
    my ($results, $self) = @_;
    my ($ok, $fail) = (0, 0);
    my $rows = '';
    for my $r (@$results) {
        if ($r->{error}) {
            $fail++;
            my $e = _html_esc($r->{error});
            $rows .= "<section class=\"result error\">\n"
                   . "  <h2>\x{2717} " . _html_esc($r->{name}) . "</h2>\n"
                   . "  <pre class=\"error-msg\">$e</pre>\n"
                   . "</section>\n";
        } else {
            $ok++;
            my $txt = _html_esc($r->{report} // '');
            $rows .= "<section class=\"result ok\">\n"
                   . "  <h2>\x{2713} " . _html_esc($r->{name}) . "</h2>\n"
                   . "  <pre>$txt</pre>\n"
                   . "</section>\n";
        }
    }
    my $ts    = _timestamp();
    my $total = scalar @$results;
    return <<"HTML";
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Perl Den Batch Report</title>
<style>
  body { font-family: monospace; background:#1e1e1e; color:#d4d4d4; margin:2em; }
  h1   { color:#3794ff; border-bottom:1px solid #444; padding-bottom:.4em; }
  h2   { color:#9cdcfe; font-size:1em; margin:.8em 0 .2em; }
  pre  { background:#252526; padding:1em; overflow-x:auto; border-radius:4px; }
  .ok h2  { color:#4ec9b0; }
  .error h2, .error-msg { color:#f44747; }
  .summary { color:#d7ba7d; margin-top:2em; }
</style>
</head>
<body>
<h1>Perl Den Batch Report</h1>
<p>Generated: $ts &mdash; $total script(s) &mdash; $ok succeeded, $fail failed</p>
$rows
<p class="summary">Summary: $ok succeeded, $fail failed</p>
</body>
</html>
HTML
}

sub _html_esc {
    my ($s) = @_;
    $s //= '';
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

sub _timestamp {
    use POSIX qw(strftime);
    return strftime('%Y-%m-%d %H:%M:%S', localtime);
}

1;

__END__

=head1 NAME

PerlDen::BatchRunner - Run multiple toolkit scripts sequentially

=head1 SYNOPSIS

    use PerlDen::BatchRunner;

    my $runner = PerlDen::BatchRunner->new(
        on_progress => sub { my ($name, $i, $total) = @_; print "[$i/$total] $name\n" },
    );

    my $results = $runner->run_batch('system_info', 'disk_usage', 'config_diff');
    print $runner->format_batch_report($results);

=head1 DESCRIPTION

Runs multiple Perl Den toolkit scripts by name, collecting results and
producing an aggregated report. Scripts are resolved via
L<PerlDen::ScriptRegistry/find_script>.

=head1 METHODS

=over 4

=item B<new(%args)>

Create a batch runner.  Accepts:

=over 8

=item C<on_progress =E<gt> sub { ($name, $i, $total) }>

Callback fired before each script runs.

=item C<on_error =E<gt> sub { ($name, $error_string) }>

Callback fired when a script fails to load or raises an exception.

=back

=item B<run_batch(@names)>

Run each named script in sequence.  Each name is resolved via
C<find_script()> so fuzzy/partial names are accepted.
Calls C<_maybe_notify()> after all scripts complete.
Returns an arrayref of result hashrefs.

=item B<format_batch_report($results)>

Format the arrayref from C<run_batch()> as a UTF-8 text report with a
summary line showing succeeded/failed counts.

=item B<export_report($results, format =E<gt> 'text|html|json')>

Export the batch results in the requested format.  C<'html'> returns a
self-contained HTML document; C<'json'> returns pretty-printed JSON
(via L<JSON::MaybeXS>); C<'text'> is the same as C<format_batch_report>.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
