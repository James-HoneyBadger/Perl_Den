package HBPerl::BatchRunner;
# ============================================================================
# HBPerl::BatchRunner - Run multiple toolkit scripts sequentially
# ============================================================================
use strict;
use warnings;
use Carp qw(croak);
use HBPerl::ScriptRegistry qw(script_index find_script);

our $VERSION = '1.00';

sub new {
    my ($class, %args) = @_;
    return bless {
        on_progress => $args{on_progress} // sub {},
        on_error    => $args{on_error}    // sub {},
    }, $class;
}

sub run_batch {
    my ($self, @script_names) = @_;
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
        my $loaded = eval { require $module_path; 1 };
        unless ($loaded) {
            my $err = { name => $display, error => "Failed to load $module: $@" };
            push @results, $err;
            $self->{on_error}->($display, $err->{error});
            next;
        }

        # Run the script module's run() function (call as function, not method)
        my $run_fn = $module->can('run');
        my $result = eval { $run_fn ? $run_fn->() : undef };
        if ($@ || !$result) {
            my $msg = $@ || 'run() returned nothing';
            push @results, { name => $display, error => "Execution failed: $msg" };
            $self->{on_error}->($display, $msg);
            next;
        }

        # Format the report if available
        my $report = '';
        my $fmt_fn = $module->can('format_report');
        if ($fmt_fn) {
            $report = eval { $fmt_fn->($result) } // '';
        }

        push @results, {
            name     => $display,
            category => $category,
            data     => $result,
            report   => $report,
        };
    }

    return \@results;
}

sub format_batch_report {
    my ($self, $results) = @_;
    $results //= [];

    my $divider = '=' x 72;
    my $report  = "\n$divider\n";
    $report .= "  HB PERL BATCH REPORT — " . scalar(@$results) . " script(s)\n";
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

1;

__END__

=head1 NAME

HBPerl::BatchRunner - Run multiple toolkit scripts sequentially

=head1 SYNOPSIS

    use HBPerl::BatchRunner;

    my $runner = HBPerl::BatchRunner->new(
        on_progress => sub { my ($name, $i, $total) = @_; print "[$i/$total] $name\n" },
    );

    my $results = $runner->run_batch('system_info', 'disk_usage', 'config_diff');
    print $runner->format_batch_report($results);

=head1 DESCRIPTION

Runs multiple HBPerl toolkit scripts by name, collecting results and
producing an aggregated report. Scripts are resolved via
L<HBPerl::ScriptRegistry/find_script>.

=cut
