#!/usr/bin/env perl
# ============================================================================
# network_diag.pl — Network diagnostics
# Usage: network_diag.pl [--dns-host HOST] [--ping-host HOST]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use PerlDen::Scripts::NetworkDiag;

my $dns_host  = 'google.com';
my $ping_host = '8.8.8.8';
my $help;

GetOptions(
    'dns-host=s'  => \$dns_host,
    'ping-host=s' => \$ping_host,
    'help|h'      => \$help,
) or die "Usage: $0 [--dns-host HOST] [--ping-host HOST]\n";

if ($help) {
    print "Usage: $0 [--dns-host HOST] [--ping-host HOST]\n";
    print "Run network diagnostics: DNS lookups, ping, interface info.\n";
    exit 0;
}

my $result = PerlDen::Scripts::NetworkDiag::run(
    dns_host  => $dns_host,
    ping_host => $ping_host,
);
print PerlDen::Scripts::NetworkDiag::format_report($result);
