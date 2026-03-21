package HBPerl::Util;
# ============================================================================
# HBPerl::Util - Shared utility functions
# ============================================================================
use strict;
use warnings;
use utf8;
use FindBin qw($RealBin);
use POSIX qw(strftime);
use Carp qw(carp);
use Exporter 'import';

our $VERSION = '1.00';
our @EXPORT_OK = qw(
    format_bytes  format_number  timestamp  trim
    run_command   run_command_list  run_command_sudo
    shell_quote   slurp_file
    find_share_dir  is_root
);

sub find_share_dir {
    # Find share/ relative to the script or lib
    my @candidates = (
        "$FindBin::RealBin/../share",
        "$FindBin::RealBin/share",
        "/usr/share/hb_perl",
        "$ENV{HOME}/.local/share/hb_perl",
    );
    for my $d (@candidates) {
        return $d if -d $d;
    }
    return "$FindBin::RealBin/../share";  # fallback
}

sub format_bytes {
    my ($bytes) = @_;
    return '0 B' unless defined $bytes && $bytes >= 0;
    my @units = ('B', 'KB', 'MB', 'GB', 'TB', 'PB');
    my $i = 0;
    my $val = $bytes + 0;
    while ($val >= 1024 && $i < $#units) {
        $val /= 1024;
        $i++;
    }
    return $i == 0 ? sprintf("%d %s", $val, $units[$i])
                    : sprintf("%.1f %s", $val, $units[$i]);
}

sub format_number {
    my ($n) = @_;
    $n = int($n // 0);
    my $s = "$n";
    1 while $s =~ s/^(-?\d+)(\d{3})/$1,$2/;
    return $s;
}

sub timestamp {
    return strftime('%Y-%m-%d %H:%M:%S', localtime);
}

sub trim {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

sub run_command {
    my ($cmd) = @_;
    my $output = '';
    my $pid = open(my $fh, '-|', 'bash', '-c', "$cmd 2>&1");
    if ($pid) {
        local $/;
        $output = <$fh> // '';
        close $fh;
    } else {
        return ('', -1);
    }
    my $rc = $? >> 8;
    return ($output, $rc);
}

# Run a command in list form — no shell interpretation.
# Safer than run_command() for untrusted arguments.
sub run_command_list {
    my (@cmd) = @_;
    my $output = '';
    my $pid = open(my $fh, '-|', @cmd);
    if ($pid) {
        local $/;
        $output = <$fh> // '';
        close $fh;
    } else {
        return ('', -1);
    }
    my $rc = $? >> 8;
    return ($output, $rc);
}

sub run_command_sudo {
    my ($cmd) = @_;
    require HBPerl::Config;
    my $priv_tool = HBPerl::Config::privilege_tool();
    return run_command(shell_quote($priv_tool) . " $cmd");
}

# Shell-escape a single argument for safe interpolation into shell strings.
# Uses single-quoting with proper escaping of embedded single quotes.
sub shell_quote {
    my ($arg) = @_;
    return "''" unless defined $arg && length $arg;
    $arg =~ s/'/'\\''/g;
    return "'$arg'";
}

sub slurp_file {
    my ($file) = @_;
    return '' unless defined $file && -f $file && -r $file;
    open my $fh, '<:encoding(UTF-8)', $file or do {
        carp "slurp_file: cannot open $file: $!" if $ENV{HBPERL_DEBUG};
        return '';
    };
    local $/;
    my $content = eval { <$fh> };
    close $fh;
    return $content // '';
}

sub is_root {
    return $> == 0;
}

1;

__END__

=head1 NAME

HBPerl::Util - Shared utility functions for the HB Perl toolkit

=head1 SYNOPSIS

    use HBPerl::Util qw(format_bytes run_command slurp_file is_root);

    say format_bytes(1536);                # "1.5 KB"
    my ($output, $rc) = run_command('df -h');
    my $text = slurp_file('/etc/hostname');

=head1 DESCRIPTION

A collection of pure-function utilities imported by the Script modules,
GUI components, and entry points.  All functions are importable via
L<Exporter>.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<format_bytes($n)>

Format a byte count as a human-readable string (B, KB, MB, GB, TB, PB).

=item B<format_number($n)>

Format an integer with comma-separated thousands (e.g. C<1,234,567>).

=item B<timestamp()>

Return the current local time as C<YYYY-MM-DD HH:MM:SS>.

=item B<trim($string)>

Strip leading and trailing whitespace.

=item B<run_command($cmd)>

Run a shell command via C<bash -c> and capture combined stdout/stderr.
Returns C<($output, $exit_code)>.  Only use with trusted command strings.

=item B<run_command_list(@cmd)>

Run a command in list form with no shell interpretation.  Safer than
C<run_command()> when arguments come from untrusted input.
Returns C<($output, $exit_code)>.

=item B<run_command_sudo($cmd)>

Like C<run_command> but prefixed with the configured privilege escalation
tool (pkexec, sudo, or doas).

=item B<shell_quote($arg)>

Shell-escape a single argument for safe interpolation into shell command
strings.  Uses single-quoting with proper escaping of embedded quotes.

=item B<slurp_file($path)>

Read an entire file as a UTF-8 string.  Returns C<''> if the file does
not exist or is unreadable.

=item B<find_share_dir()>

Locate the F<share/> directory by probing several candidate paths
relative to the running script.

=item B<is_root()>

Return true if the effective UID is 0.

=back

=head1 AUTHOR

James

=head1 LICENSE

MIT

=cut