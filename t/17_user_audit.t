#!/usr/bin/env perl
# ============================================================================
# t/17_user_audit.t — Test HBPerl::Scripts::UserAudit
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use_ok('HBPerl::Scripts::UserAudit');

SKIP: {
    skip 'No /etc/passwd (non-Linux)', 16 unless -f '/etc/passwd';

subtest 'run returns expected structure' => sub {
    my $result = HBPerl::Scripts::UserAudit::run();
    ok(ref $result eq 'HASH', 'returns a hashref');

    for my $key (qw(users login_users warnings sudoers password_status)) {
        ok(exists $result->{$key}, "has key: $key");
    }
};

subtest 'users list is populated' => sub {
    my $result = HBPerl::Scripts::UserAudit::run();
    ok(ref $result->{users} eq 'ARRAY', 'users is an array');
    ok(scalar @{$result->{users}} > 0, 'has at least one user');

    # Check user structure
    my $root = (grep { $_->{name} eq 'root' } @{$result->{users}})[0];
    ok($root, 'found root user');
    if ($root) {
        is($root->{uid}, 0, 'root uid is 0');
        ok($root->{is_root}, 'root flagged as is_root');
    }
};

subtest 'login_users is a subset of users' => sub {
    my $result = HBPerl::Scripts::UserAudit::run();
    ok(ref $result->{login_users} eq 'ARRAY', 'login_users is an array');
    my $total  = scalar @{$result->{users}};
    my $logins = scalar @{$result->{login_users}};
    cmp_ok($logins, '<=', $total, 'login_users <= total users');
    cmp_ok($logins, '>', 0, 'at least one login user');
};

subtest 'warnings is an array' => sub {
    my $result = HBPerl::Scripts::UserAudit::run();
    ok(ref $result->{warnings} eq 'ARRAY', 'warnings is an array');
};

subtest 'format_report produces text' => sub {
    my $result = HBPerl::Scripts::UserAudit::run();
    my $report = HBPerl::Scripts::UserAudit::format_report($result);
    ok(length($report) > 100, 'report has content');
    like($report, qr/USER.*AUDIT/i, 'report has header');
};

} # end SKIP

done_testing();
