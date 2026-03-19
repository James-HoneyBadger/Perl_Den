#!/usr/bin/env perl
# ============================================================================
# Template: System Administration Script
# Description: A robust sysadmin script with logging, sudo checks, and reports
# ============================================================================
use strict;
use warnings;
use POSIX qw(strftime);
use File::Basename;
use Getopt::Long;

# ── Configuration ──────────────────────────────────────────
my $log_file = '/tmp/' . basename($0, '.pl') . '.log';
my $verbose  = 0;
my $dry_run  = 0;

GetOptions(
    'verbose|v'  => \$verbose,
    'dry-run|n'  => \$dry_run,
    'log=s'      => \$log_file,
) or die "Usage: $0 [--verbose] [--dry-run] [--log FILE]\n";

# ── Logging ────────────────────────────────────────────────
sub log_msg {
    my ($level, $msg) = @_;
    my $ts = strftime('%Y-%m-%d %H:%M:%S', localtime());
    my $line = "[$ts] [$level] $msg\n";
    print $line if $verbose || $level eq 'ERROR';
    if (open my $fh, '>>', $log_file) {
        print $fh $line;
        close $fh;
    }
}

# ── Root Check ─────────────────────────────────────────────
sub require_root {
    if ($< != 0) {
        log_msg('ERROR', 'This script requires root privileges');
        die "Please run with sudo or as root.\n";
    }
}

# ── Safe Command Execution ─────────────────────────────────
sub run_cmd {
    my ($cmd) = @_;
    log_msg('INFO', "Running: $cmd");
    if ($dry_run) {
        log_msg('INFO', '[DRY RUN] Would execute: ' . $cmd);
        return ('', 0);
    }
    my $output = `$cmd 2>&1`;
    my $rc = $? >> 8;
    log_msg($rc ? 'ERROR' : 'INFO', "Exit code: $rc");
    return ($output, $rc);
}

# ── Main ───────────────────────────────────────────────────
log_msg('INFO', 'Script started');

# TODO: Add your sysadmin logic here
# Example:
# require_root();
# my ($out, $rc) = run_cmd('systemctl status sshd');
# print $out;

log_msg('INFO', 'Script completed');
print "Done. Log written to $log_file\n";
