#!/usr/bin/env perl
# ============================================================================
# user_audit.pl — Audit user accounts and security
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use BadgerOps::Scripts::UserAudit;

my $help;
GetOptions('help|h' => \$help) or die "Usage: $0 [--help]\n";
if ($help) {
    print "Usage: $0\n";
    print "Audit user accounts and security.\n";
    exit 0;
}

my $result = BadgerOps::Scripts::UserAudit::run();
print BadgerOps::Scripts::UserAudit::format_report($result);
