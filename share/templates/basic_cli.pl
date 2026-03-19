#!/usr/bin/env perl
# ============================================================================
# Template: Basic CLI Script
# Description: A minimal Perl CLI script with argument parsing and help
# ============================================================================
use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;

# ── Configuration ──────────────────────────────────────────
my $verbose = 0;
my $help    = 0;

GetOptions(
    'verbose|v' => \$verbose,
    'help|h'    => \$help,
) or pod2usage(2);
pod2usage(1) if $help;

# ── Main Logic ─────────────────────────────────────────────
print "Hello from your new Perl script!\n";
print "Verbose mode is ON\n" if $verbose;

# TODO: Add your logic here

exit 0;

__END__

=head1 NAME

my_script.pl - A brief description of what this script does

=head1 SYNOPSIS

    my_script.pl [options]

    Options:
        -v, --verbose    Enable verbose output
        -h, --help       Show this help message

=head1 DESCRIPTION

Describe what this script does in detail.

=head1 AUTHOR

Your Name

=cut
