#!/usr/bin/env perl
# ============================================================================
# t/10_duplicate_finder.t — Test BadgerOps::Scripts::DuplicateFinder
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);

use_ok('BadgerOps::Scripts::DuplicateFinder');

subtest 'finds duplicates' => sub {
    my $dir = tempdir(CLEANUP => 1);

    # Create duplicate files
    for my $name (qw(a.txt b.txt)) {
        open my $fh, '>', "$dir/$name" or die $!;
        print $fh "identical content here\n";
        close $fh;
    }
    # And a unique file
    open my $fh, '>', "$dir/c.txt" or die $!;
    print $fh "different content\n";
    close $fh;

    my $result = BadgerOps::Scripts::DuplicateFinder::run(
        directory => $dir,
        min_size  => 1,
    );
    ok(ref $result eq 'HASH', 'returns hashref');
    is($result->{total_files}, 3, 'scanned 3 files');
    cmp_ok(scalar @{$result->{groups}}, '>=', 1, 'found duplicate group');
    is($result->{groups}[0]{count}, 2, 'group has 2 files');
    cmp_ok($result->{wasted_bytes}, '>', 0, 'wasted bytes > 0');
};

subtest 'no duplicates in unique files' => sub {
    my $dir = tempdir(CLEANUP => 1);
    for my $i (1..3) {
        open my $fh, '>', "$dir/file_$i.txt" or die $!;
        print $fh "unique content $i\n";
        close $fh;
    }

    my $r = BadgerOps::Scripts::DuplicateFinder::run(directory => $dir, min_size => 1);
    is(scalar @{$r->{groups}}, 0, 'no duplicate groups');
    is($r->{wasted_bytes}, 0, 'no wasted bytes');
};

subtest 'format_report works' => sub {
    my $dir = tempdir(CLEANUP => 1);
    open my $fh, '>', "$dir/x.txt" or die $!;
    print $fh "data";
    close $fh;

    my $r = BadgerOps::Scripts::DuplicateFinder::run(directory => $dir, min_size => 1);
    my $report = BadgerOps::Scripts::DuplicateFinder::format_report($r);
    ok(length($report) > 30, 'report has content');
    like($report, qr/DUPLICATE/i, 'report header present');
};

done_testing();
