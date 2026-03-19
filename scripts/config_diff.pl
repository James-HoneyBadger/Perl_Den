#!/usr/bin/env perl
# ============================================================================
# config_diff.pl — Track changes in system configuration files
# Usage: config_diff.pl --action baseline   Create a new baseline
#        config_diff.pl --action diff        Diff current vs baseline
#        config_diff.pl --action status      Show file status overview
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use HBPerl::Scripts::ConfigDiff;

my $action   = 'status';
my $base_dir;
my $help;

GetOptions(
    'action=s'   => \$action,
    'base-dir=s' => \$base_dir,
    'help|h'     => \$help,
) or die "Usage: $0 --action <baseline|diff|status> [--base-dir DIR]\n";

if ($help) {
    print "Usage: $0 --action <baseline|diff|status> [--base-dir DIR]\n";
    print "Track changes in system configuration files.\n";
    exit 0;
}

my %args = (action => $action);
$args{base_dir} = $base_dir if $base_dir;

my $result = HBPerl::Scripts::ConfigDiff::run(%args);
print HBPerl::Scripts::ConfigDiff::format_report($result);
