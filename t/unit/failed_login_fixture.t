#!/usr/bin/env perl
# ============================================================================
# t/unit/failed_login_fixture.t — Fixture-based FailedLoginDetector tests
# Uses t/fixtures/auth.log to test parsing against realistic log data
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use_ok('BadgerOps::Scripts::FailedLoginDetector');

my $fixture = "$FindBin::Bin/../fixtures/auth.log";
plan skip_all => 'auth.log fixture not found' unless -f $fixture;

# Read fixture lines
open my $fh, '<', $fixture or die "Cannot read $fixture: $!";
my @lines = <$fh>;
close $fh;

subtest 'parse fixture auth.log' => sub {
    my @entries = BadgerOps::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    cmp_ok(scalar @entries, '>=', 8, 'parsed at least 8 entries from fixture');

    my @fails     = grep { $_->{type} eq 'fail' }    @entries;
    my @successes = grep { $_->{type} eq 'success' }  @entries;
    cmp_ok(scalar @fails,     '>=', 6, 'at least 6 failed entries');
    cmp_ok(scalar @successes, '>=', 2, 'at least 2 success entries');
};

subtest 'fixture IPs are correct' => sub {
    my @entries = BadgerOps::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    my %ips;
    for my $e (grep { $_->{type} eq 'fail' } @entries) {
        $ips{$e->{ip}}++ if $e->{ip};
    }
    ok(exists $ips{'192.168.1.100'}, 'found brute-force IP 192.168.1.100');
    cmp_ok($ips{'192.168.1.100'}, '>=', 4, 'IP 192.168.1.100 has >= 4 failures');
    ok(exists $ips{'10.0.0.5'} || exists $ips{'10.0.0.10'}, 'found other attacker IPs');
};

subtest 'fixture users are correct' => sub {
    my @entries = BadgerOps::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    my %users;
    for my $e (grep { $_->{type} eq 'fail' } @entries) {
        $users{$e->{user}}++ if $e->{user};
    }
    ok(exists $users{'root'}, 'root targeted');
    cmp_ok($users{'root'}, '>=', 4, 'root has >= 4 failures');
};

subtest 'accepted logins parsed from fixture' => sub {
    my @entries = BadgerOps::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    my @ok = grep { $_->{type} eq 'success' } @entries;
    my @james = grep { $_->{user} eq 'james' } @ok;
    ok(scalar @james >= 1, 'james has at least 1 accepted login');

    my @deploy = grep { $_->{user} eq 'deploy' } @ok;
    ok(scalar @deploy >= 1, 'deploy has at least 1 accepted login');
};

subtest 'sudo failure parsed from fixture' => sub {
    my @entries = BadgerOps::Scripts::FailedLoginDetector::_parse_auth_lines(\@lines);
    my @sudo = grep { $_->{service} && $_->{service} eq 'sudo' } @entries;
    cmp_ok(scalar @sudo, '>=', 1, 'at least 1 sudo failure');
};

done_testing();
