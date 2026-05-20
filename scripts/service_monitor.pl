#!/usr/bin/env perl
# ============================================================================
# service_monitor.pl — Monitor systemd services
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PerlDen::Scripts::ServiceMonitor;

my $help;
GetOptions('help|h' => \$help) or die "Usage: $0 [--help]\n";
if ($help) {
    print "Usage: $0\n";
    print "Monitor systemd services.\n";
    exit 0;
}

my $result = PerlDen::Scripts::ServiceMonitor::run();
print PerlDen::Scripts::ServiceMonitor::format_report($result);
