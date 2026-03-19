#!/usr/bin/env perl
# ============================================================================
# t/12_config_diff.t — Test HBPerl::Scripts::ConfigDiff
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);

use_ok('HBPerl::Scripts::ConfigDiff');

my $base_dir = tempdir(CLEANUP => 1) . "/baselines";
my $src_dir  = tempdir(CLEANUP => 1);

# Create test "config" files
my @test_files;
for my $name (qw(hosts.conf app.conf)) {
    my $path = "$src_dir/$name";
    open my $fh, '>', $path or die $!;
    print $fh "# Config $name\nkey=value\nport=8080\n";
    close $fh;
    push @test_files, $path;
}

subtest 'create baseline' => sub {
    my $result = HBPerl::Scripts::ConfigDiff::run(
        action   => 'baseline',
        base_dir => $base_dir,
        files    => \@test_files,
    );
    ok(ref $result eq 'HASH', 'returns hashref');
    my $b = $result->{baseline};
    is($b->{saved}, 2, 'saved 2 files');
    is($b->{skipped}, 0, 'skipped none');
    ok(-d "$base_dir/latest" || -l "$base_dir/latest", 'latest symlink created');
};

subtest 'status shows unchanged' => sub {
    my $r = HBPerl::Scripts::ConfigDiff::run(
        action   => 'status',
        base_dir => $base_dir,
        files    => \@test_files,
    );
    my @st = @{$r->{status}};
    is(scalar @st, 2, 'status for 2 files');
    is($st[0]{status}, 'unchanged', 'first file unchanged');
};

subtest 'diff detects changes' => sub {
    # Modify one file
    open my $fh, '>>', $test_files[0] or die $!;
    print $fh "new_key=new_value\n";
    close $fh;

    my $r = HBPerl::Scripts::ConfigDiff::run(
        action   => 'diff',
        base_dir => $base_dir,
        files    => \@test_files,
    );
    my @diffs = @{$r->{diffs}};
    my @changed = grep { $_->{status} eq 'changed' } @diffs;
    cmp_ok(scalar @changed, '>=', 1, 'detected a change');
    ok(length($changed[0]{diff}) > 0, 'diff content present');
};

subtest 'format_report works' => sub {
    my $r = HBPerl::Scripts::ConfigDiff::run(
        action   => 'status',
        base_dir => $base_dir,
        files    => \@test_files,
    );
    my $report = HBPerl::Scripts::ConfigDiff::format_report($r);
    ok(length($report) > 50, 'report has content');
    like($report, qr/CONFIGURATION/i, 'has header');
};

done_testing();
