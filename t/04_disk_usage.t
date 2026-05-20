#!/usr/bin/env perl
# ============================================================================
# t/04_disk_usage.t — Test PerlDen::Scripts::DiskUsage
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);

use_ok('PerlDen::Scripts::DiskUsage');

subtest 'scan a temp directory' => sub {
    my $dir = tempdir(CLEANUP => 1);

    # Create test files
    for my $i (1..5) {
        my $f = "$dir/file_$i.txt";
        open my $fh, '>', $f or die $!;
        print $fh 'x' x (1024 * $i);   # 1KB, 2KB, ...
        close $fh;
    }
    mkdir "$dir/subdir";
    open my $fh, '>', "$dir/subdir/deep.txt" or die $!;
    print $fh 'y' x 4096;
    close $fh;

    my $result = PerlDen::Scripts::DiskUsage::run(
        target    => $dir,
        max_depth => 2,
        min_size  => 0,
        top_n     => 10,
    );

    ok(ref $result eq 'HASH', 'returns hashref');
    ok(exists $result->{total_size}, 'has total_size');
    cmp_ok($result->{total_size}, '>', 0, 'total_size > 0');
    ok(ref $result->{large_files} eq 'ARRAY', 'has large_files array');
    cmp_ok(scalar @{$result->{large_files}}, '>=', 6, 'found at least 6 files');
};

subtest 'format_report produces output' => sub {
    my $dir = tempdir(CLEANUP => 1);
    open my $fh, '>', "$dir/test.txt" or die $!;
    print $fh 'data';
    close $fh;

    my $r = PerlDen::Scripts::DiskUsage::run(
        target => $dir, min_size => 0);
    my $report = PerlDen::Scripts::DiskUsage::format_report($r);
    ok(length($report) > 50, 'report has content');
};

subtest 'nonexistent directory returns zero' => sub {
    my $r = PerlDen::Scripts::DiskUsage::run(target => '/nonexistent_xyz');
    is($r->{total_size}, 0, 'total_size is 0 for nonexistent dir');
};

done_testing();
