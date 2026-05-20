#!/usr/bin/env perl
# ============================================================================
# file_permissions.pl — Audit file permissions for security issues
# Usage: file_permissions.pl [directory] [--max-depth N] [--help]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PerlDen::Scripts::FilePermissions;

my $help;
my $dir       = shift @ARGV // $ENV{HOME} // '.';
my $max_depth = 4;

GetOptions(
    'max-depth=i' => \$max_depth,
    'help|h'      => \$help,
) or die "Usage: $0 [dir] [--max-depth N]\n";

if ($help) {
    print "Usage: $0 [dir] [--max-depth N]\n";
    print "Audit SUID/SGID/world-writable files. Default dir: \$HOME\n";
    exit 0;
}

my $result = PerlDen::Scripts::FilePermissions::run(
    directory => $dir,
    max_depth => $max_depth,
);
print PerlDen::Scripts::FilePermissions::format_report($result);
