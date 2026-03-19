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

our $VERSION = '1.00';

sub new {
    my ($class, %args) = @_;
    return bless {
        on_stdout => $args{on_stdout} // sub {},
        on_stderr => $args{on_stderr} // sub {},
        on_exit   => $args{on_exit}   // sub {},
        running   => 0,
        pid       => undef,
    }, $class;
}

sub run_script {
    my ($self, %args) = @_;
    my $command   = $args{command};
    my $as_root   = $args{as_root} // 0;

    return if $self->{running};

    if ($as_root && $> != 0) {
        $command = "pkexec $command";
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

        exec('/bin/bash', '-c', $command)
            or die "exec failed: $!\n";
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

    Glib::IO->add_watch(fileno($stdout_r), ['in', 'hup'], sub {
        my ($fd, $condition) = @_;
        if ($condition >= 'in') {
            my $buf;
            my $n = sysread($stdout_r, $buf, 8192);
            if ($n && $n > 0) {
                $on_stdout->($buf);
                return TRUE;
            }
        }
        close $stdout_r;
        $check_done->();
        return FALSE;
    });

    Glib::IO->add_watch(fileno($stderr_r), ['in', 'hup'], sub {
        my ($fd, $condition) = @_;
        if ($condition >= 'in') {
            my $buf;
            my $n = sysread($stderr_r, $buf, 8192);
            if ($n && $n > 0) {
                $on_stderr->($buf);
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
sub run_sync {
    my ($class, @command) = @_;
    # Accept either a list or a single string (for backward compat)
    @command = ('bash', '-c', $command[0]) if @command == 1;

    my $stderr_fh = gensym;
    my $pid = open3(my $stdin_fh, my $stdout_fh, $stderr_fh, @command);
    close $stdin_fh;

    my $stdout = do { local $/; <$stdout_fh> } // '';
    my $stderr = do { local $/; <$stderr_fh> } // '';
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

James

=head1 LICENSE

MIT

=cut
