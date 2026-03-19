#!/usr/bin/env perl
# ============================================================================
# t/18_ssl_checker.t — Test HBPerl::Scripts::SSLChecker
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('HBPerl::Scripts::SSLChecker');

subtest 'run returns expected structure' => sub {
    # Use a very short timeout and localhost to avoid network dependency
    my $result = HBPerl::Scripts::SSLChecker::run(
        hosts   => ['localhost'],
        port    => 443,
        timeout => 2,
    );

    ok(ref $result eq 'HASH', 'returns a hashref');
    ok(exists $result->{checks}, 'has checks key');
    ok(ref $result->{checks} eq 'ARRAY', 'checks is an array');
    is(scalar @{$result->{checks}}, 1, 'one check result');

    my $check = $result->{checks}[0];
    ok(ref $check eq 'HASH', 'check entry is a hashref');
    is($check->{host}, 'localhost', 'host matches');
    is($check->{port}, 443, 'port matches');
    # localhost:443 likely won't have SSL, so we expect an error
    # but the structure should be valid
    ok(exists $check->{host}, 'check has host');
    ok(exists $check->{port}, 'check has port');
};

subtest 'local_certs key exists' => sub {
    my $result = HBPerl::Scripts::SSLChecker::run(
        hosts   => [],
        timeout => 1,
    );
    ok(exists $result->{local_certs}, 'has local_certs key');
};

subtest 'format_report produces text' => sub {
    my $result = HBPerl::Scripts::SSLChecker::run(
        hosts   => ['localhost'],
        port    => 443,
        timeout => 2,
    );
    my $report = HBPerl::Scripts::SSLChecker::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/SSL.*TLS.*CERTIFICATE/i, 'report has header');
};

subtest 'format_report handles connection errors' => sub {
    my $result = {
        checks => [{
            host  => 'bad.host.example',
            port  => 443,
            error => 'Connection refused',
        }],
        local_certs => [],
    };
    my $report = HBPerl::Scripts::SSLChecker::format_report($result);
    like($report, qr/ERROR.*Connection refused/, 'error displayed in report');
};

done_testing();
