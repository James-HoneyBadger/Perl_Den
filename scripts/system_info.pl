#!/usr/bin/env perl
# ============================================================================
# system_info.pl — Display comprehensive system information
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use BadgerOps::Scripts::SystemInfo;

my $help;
GetOptions('help|h' => \$help) or die "Usage: $0 [--help]\n";
if ($help) {
    print "Usage: $0\n";
    print "Display comprehensive system information.\n";
    exit 0;
}

my $result = BadgerOps::Scripts::SystemInfo::run();
print BadgerOps::Scripts::SystemInfo::format_report($result);
