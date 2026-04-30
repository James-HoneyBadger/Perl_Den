#!/usr/bin/env perl
# ============================================================================
# cron_manager.pl — List and analyse cron jobs and systemd timers
# Usage: cron_manager.pl [--user USERNAME]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use BadgerOps::Scripts::CronManager;

my $user;
my $help;

GetOptions(
    'user=s' => \$user,
    'help|h' => \$help,
) or die "Usage: $0 [--user USERNAME]\n";

if ($help) {
    print "Usage: $0 [--user USERNAME]\n";
    print "List and analyze cron jobs and systemd timers.\n";
    exit 0;
}

my $result = BadgerOps::Scripts::CronManager::run(
    user => $user,
);
print BadgerOps::Scripts::CronManager::format_report($result);
