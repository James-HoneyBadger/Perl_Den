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
use PerlDen::Scripts::PortScanner;

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

my $result = PerlDen::Scripts::PortScanner::run(
    host       => $host,
    port_range => $range,
    timeout    => $timeout,
    mode       => $scan ? 'scan' : 'listen',
);
print PerlDen::Scripts::PortScanner::format_report($result);
