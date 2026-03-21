package HBPerl::Runner;
# ============================================================================
# HBPerl::Runner - Script execution engine with STDOUT/STDERR capture
# ============================================================================
use strict;
use warnings;
use utf8;
use POSIX qw(:sys_wait_h);
use IO::Handle;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use File::Temp;
use IPC::Open3;
use Symbol 'gensym';
use Glib ('TRUE', 'FALSE');
use HBPerl::Config;

our $VERSION = '1.00';

sub new {
    my ($class, %args) = @_;
    return bless {
        on_stdout => $args{on_stdout} // sub {},
        on_stderr => $args{on_stderr} // sub {},
        on_exit   => $args{on_exit}   // sub {},
        running   => 0,
        pid       => undef,
        output_lines => 0,
        max_output_lines => $args{max_output_lines} // 50_000,
    }, $class;
}

sub run_script {
    my ($self, %args) = @_;
    my $command   = $args{command};
    my $as_root   = $args{as_root} // 0;

    return if $self->{running};

    # Build the exec argument list.  Accepting an arrayref avoids the
    # shell entirely; a plain string still works for backward compat
    # but is passed through bash -c (callers should prefer arrayref).
    my @exec_cmd;
    if (ref $command eq 'ARRAY') {
        @exec_cmd = @$command;
    } else {
        @exec_cmd = ('/bin/bash', '-c', $command);
    }

    if ($as_root && $> != 0) {
        my $priv_tool = HBPerl::Config::privilege_tool();
        unshift @exec_cmd, $priv_tool;
    }

    # Create pipes for STDOUT and STDERR
    pipe(my $stdout_r, my $stdout_w) or die "pipe: $!";
    pipe(my $stderr_r, my $stderr_w) or die "pipe: $!";

    my $pid = fork();
    die "fork: $!" unless defined $pid;

    if ($pid == 0) {
        # ── Child process ──
        close $stdout_r;
        close $stderr_r;
        open STDOUT, '>&', $stdout_w or die "dup stdout: $!";
        open STDERR, '>&', $stderr_w or die "dup stderr: $!";
        close $stdout_w;
        close $stderr_w;
        STDOUT->autoflush(1);
        STDERR->autoflush(1);

        { no warnings 'exec'; exec(@exec_cmd); }
        # If exec fails, report to stderr so parent can capture it
        print STDERR "hbperl: exec failed for '$exec_cmd[0]': $!\n";
        POSIX::_exit(127);
    }

    # ── Parent process ──
    close $stdout_w;
    close $stderr_w;
    $self->{pid}     = $pid;
    $self->{running} = 1;

    # Make handles non-blocking
    _set_nonblock($stdout_r);
    _set_nonblock($stderr_r);

    # Watch for readable data using Glib IO watch
    my $on_stdout = $self->{on_stdout};
    my $on_stderr = $self->{on_stderr};
    my $on_exit   = $self->{on_exit};
    my $runner    = $self;
    my $done_count = 0;

    my $check_done = sub {
        $done_count++;
        if ($done_count >= 2) {
            waitpid($pid, 0);
            my $exit_code = $? >> 8;
            $runner->{running} = 0;
            $runner->{pid}     = undef;
            $on_exit->($exit_code);
        }
    };

    my $max_lines = $self->{max_output_lines};

    Glib::IO->add_watch(fileno($stdout_r), ['in', 'hup'], sub {
        my ($fd, $condition) = @_;
        if ($condition =~ /in/) {
            my $buf;
            my $n = sysread($stdout_r, $buf, 8192);
            if (defined $n && $n > 0) {
                if ($runner->{output_lines} < $max_lines) {
                    $runner->{output_lines} += ($buf =~ tr/\n//);
                    $on_stdout->($buf);
                }
                return TRUE;
            }
        }
        close $stdout_r;
        $check_done->();
        return FALSE;
    });

    Glib::IO->add_watch(fileno($stderr_r), ['in', 'hup'], sub {
        my ($fd, $condition) = @_;
        if ($condition =~ /in/) {
            my $buf;
            my $n = sysread($stderr_r, $buf, 8192);
            if (defined $n && $n > 0) {
                if ($runner->{output_lines} < $max_lines) {
                    $runner->{output_lines} += ($buf =~ tr/\n//);
                    $on_stderr->($buf);
                }
                return TRUE;
            }
        }
        close $stderr_r;
        $check_done->();
        return FALSE;
    });

    return $pid;
}

sub kill_running {
    my ($self) = @_;
    if ($self->{running} && $self->{pid}) {
        kill 'TERM', $self->{pid};
        Glib::Timeout->add(2000, sub {
            if ($self->{running} && $self->{pid}) {
                kill 'KILL', $self->{pid};
            }
            return FALSE;
        });
    }
}

sub is_running { return $_[0]->{running} }

sub _set_nonblock {
    my ($fh) = @_;
    my $flags = fcntl($fh, F_GETFL, 0) or return;
    fcntl($fh, F_SETFL, $flags | O_NONBLOCK);
}

# Run a command synchronously and return (stdout, stderr, exit_code)
# Optional last argument: hashref with { timeout => $seconds }
sub run_sync {
    my ($class, @command) = @_;
    my $opts = ref $command[-1] eq 'HASH' ? pop @command : {};
    my $timeout = $opts->{timeout} // 0;  # 0 = no timeout

    # Accept either a list or a single string (for backward compat)
    @command = ('bash', '-c', $command[0]) if @command == 1;

    my $stderr_fh = gensym;
    my $pid = open3(my $stdin_fh, my $stdout_fh, $stderr_fh, @command);
    close $stdin_fh;

    # Read both streams concurrently via IO::Select to avoid deadlock
    # when both pipe buffers fill simultaneously.
    require IO::Select;
    my $sel = IO::Select->new($stdout_fh, $stderr_fh);
    my ($stdout, $stderr) = ('', '');
    my $remaining = 2;
    my $deadline = $timeout > 0 ? time() + $timeout : 0;
    my $timed_out = 0;

    while ($remaining > 0) {
        my $wait = $deadline > 0 ? ($deadline - time()) : undef;
        if (defined $wait && $wait <= 0) {
            $timed_out = 1;
            last;
        }
        my @ready = $sel->can_read($wait);
        if (!@ready) {
            # can_read returned empty — either all fds are done or we timed out
            if ($deadline > 0 && time() >= $deadline) {
                $timed_out = 1;
            }
            last;
        }
        for my $fh (@ready) {
            my $buf;
            my $n = sysread($fh, $buf, 8192);
            if (!defined $n || $n == 0) {
                $sel->remove($fh);
                $remaining--;
                next;
            }
            if ($fh == $stdout_fh) {
                $stdout .= $buf;
            } else {
                $stderr .= $buf;
            }
        }
    }

    if ($timed_out) {
        kill 'TERM', $pid;
        # Give it a moment, then force-kill
        my $reaped = waitpid($pid, WNOHANG);
        if ($reaped == 0) {
            kill 'KILL', $pid;
            waitpid($pid, 0);
        }
        close $stdout_fh;
        close $stderr_fh;
        return ($stdout, "Command timed out after ${timeout}s\n" . $stderr, 124);
    }

    close $stdout_fh;
    close $stderr_fh;

    waitpid($pid, 0);
    my $exit_code = $? >> 8;

    return ($stdout, $stderr, $exit_code);
}

1;

__END__

=encoding utf8

=head1 NAME

HBPerl::Runner - Non-blocking script execution with output capture

=head1 SYNOPSIS

    use HBPerl::Runner;

    # Async (GUI — output via callbacks, driven by Glib event loop)
    my $runner = HBPerl::Runner->new(
        on_stdout => sub { print $_[0] },
        on_stderr => sub { warn  $_[0] },
        on_exit   => sub { say "exit code: $_[0]" },
    );
    $runner->run_script(command => 'perl myscript.pl');

    # Sync (CLI / tests)
    my ($stdout, $stderr, $exit) = HBPerl::Runner->run_sync('ls -la');

=head1 DESCRIPTION

Runs shell commands in a child process.  The async path uses fork/pipe
with Glib IO watches so the GTK event loop stays responsive.  The sync
path uses L<IPC::Open3> and blocks until the command completes.

=head1 METHODS

=over 4

=item B<new(%args)>

Create a runner.  Accepts callbacks: C<on_stdout>, C<on_stderr>, C<on_exit>.

=item B<run_script(command =E<gt> $cmd, as_root =E<gt> 0|1)>

Fork a child to execute C<$cmd>.  If C<as_root> is true and the current
user is not root, the command is prefixed with C<pkexec>.  Returns the
child PID.

=item B<kill_running()>

Send SIGTERM to the child; escalate to SIGKILL after 2 seconds.

=item B<is_running()>

Return true if a child process is still active.

=item B<run_sync(@command)>  (class method)

Run a command synchronously.  Returns C<($stdout, $stderr, $exit_code)>.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
