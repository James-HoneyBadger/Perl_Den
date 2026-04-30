#!/usr/bin/env perl
# ============================================================================
# port_scanner.pl — List listening ports and optionally scan a host
# Usage: port_scanner.pl [--host HOST] [--range 1-1024] [--scan] [--timeout N]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use BadgerOps::Scripts::PortScanner;

my $host    = '127.0.0.1';
my $range   = '1-1024';
my $scan    = 0;
my $timeout = 1;
my $help;

GetOptions(
    'host=s'    => \$host,
    'range=s'   => \$range,
    'scan'      => \$scan,
    'timeout=i' => \$timeout,
    'help|h'    => \$help,
) or die "Usage: $0 [--host HOST] [--range 1-1024] [--scan] [--timeout N]\n";

if ($help) {
    print "Usage: $0 [--host HOST] [--range 1-1024] [--scan] [--timeout N]\n";
    print "List listening ports or scan a remote host.\n";
    exit 0;
}

my $result = BadgerOps::Scripts::PortScanner::run(
    host       => $host,
    port_range => $range,
    timeout    => $timeout,
    mode       => $scan ? 'scan' : 'listen',
);
print BadgerOps::Scripts::PortScanner::format_report($result);
