#!/usr/bin/env perl
# t/23_git.t - Tests for BadgerOps::Git lightweight git integration
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin qw($RealBin);

use lib "$RealBin/../lib";
use BadgerOps::Git;

# Test 1: is_git_repo on the project directory itself (should be a git repo)
my $project_dir = "$RealBin/..";
SKIP: {
    skip 'Not inside a git repo', 3 unless -d "$project_dir/.git";

    ok(BadgerOps::Git::is_git_repo($project_dir), 'project dir is a git repo');

    my $branch = BadgerOps::Git::current_branch($project_dir);
    ok(defined $branch && length($branch) > 0, "current_branch returns: $branch");

    my $summary = BadgerOps::Git::status_summary($project_dir);
    ok(defined $summary, "status_summary returns: $summary");
    like($summary, qr/\|/, 'summary contains pipe separator');
}

# Test 2: is_git_repo on a temp dir (not a repo)
my $tmpdir = tempdir(CLEANUP => 1);
ok(!BadgerOps::Git::is_git_repo($tmpdir), 'temp dir is not a git repo');

my $branch = BadgerOps::Git::current_branch($tmpdir);
ok(!defined $branch, 'current_branch returns undef for non-repo');

my $summary = BadgerOps::Git::status_summary($tmpdir);
ok(!defined $summary, 'status_summary returns undef for non-repo');

# Test 3: status returns a hashref
SKIP: {
    skip 'Not inside a git repo', 1 unless -d "$project_dir/.git";

    my $status = BadgerOps::Git::status($project_dir);
    is(ref $status, 'HASH', 'status returns a hashref');
}

done_testing();
