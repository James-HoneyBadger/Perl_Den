#!/usr/bin/env perl
# ============================================================================
# ssl_checker.pl — Check SSL/TLS certificate expiry and details
# Usage: ssl_checker.pl host1 host2 ... [--port N] [--timeout N]
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use BadgerOps::Scripts::SSLChecker;

my $port    = 443;
my $timeout = 10;
my $help;

GetOptions(
    'port=i'    => \$port,
    'timeout=i' => \$timeout,
    'help|h'    => \$help,
) or die "Usage: $0 host1 [host2 ...] [--port N] [--timeout N]\n";

if ($help) {
    print "Usage: $0 host1 [host2 ...] [--port N] [--timeout N]\n";
    print "Check SSL/TLS certificate expiry and details.\n";
    exit 0;
}

my @hosts = @ARGV;
@hosts = ('localhost') unless @hosts;

my $result = BadgerOps::Scripts::SSLChecker::run(
    hosts   => \@hosts,
    port    => $port,
    timeout => $timeout,
);
print BadgerOps::Scripts::SSLChecker::format_report($result);
