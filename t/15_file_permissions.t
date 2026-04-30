#!/usr/bin/env perl
# ============================================================================
# t/15_file_permissions.t — Test BadgerOps::Scripts::FilePermissions
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);

use_ok('BadgerOps::Scripts::FilePermissions');

subtest 'run returns expected structure' => sub {
    # Scan a small temp dir to keep things fast
    my $tmpdir = tempdir(CLEANUP => 1);
    my $result = BadgerOps::Scripts::FilePermissions::run(
        target    => $tmpdir,
        max_files => 100,
    );

    ok(ref $result eq 'HASH', 'returns a hashref');
    is($result->{target}, $tmpdir, 'target matches');

    for my $key (qw(suid_files sgid_files world_writable world_readable_sens no_owner)) {
        ok(exists $result->{$key}, "has key: $key");
        ok(ref $result->{$key} eq 'ARRAY', "$key is an arrayref");
    }
};

subtest 'detects world-writable files' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $ww_file = "$tmpdir/world_writable.txt";
    open my $fh, '>', $ww_file or die "Cannot create test file: $!";
    close $fh;
    chmod 0666, $ww_file;  # world-writable

    my $result = BadgerOps::Scripts::FilePermissions::run(
        target    => $tmpdir,
        max_files => 100,
    );

    my @ww = @{$result->{world_writable}};
    ok(scalar @ww > 0, 'found world-writable files');
    my @match = grep { $_->{path} =~ /world_writable\.txt$/ } @ww;
    ok(scalar @match > 0, 'found our specific test file');
};

subtest 'empty dir produces empty results' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $result = BadgerOps::Scripts::FilePermissions::run(
        target    => $tmpdir,
        max_files => 100,
    );

    is(scalar @{$result->{suid_files}},     0, 'no suid files');
    is(scalar @{$result->{sgid_files}},     0, 'no sgid files');
    is(scalar @{$result->{world_writable}}, 0, 'no world-writable files');
    is(scalar @{$result->{no_owner}},       0, 'no orphaned files');
};

subtest 'format_report produces text' => sub {
    my $tmpdir = tempdir(CLEANUP => 1);
    my $result = BadgerOps::Scripts::FilePermissions::run(target => $tmpdir);
    my $report = BadgerOps::Scripts::FilePermissions::format_report($result);
    ok(length($report) > 50, 'report has content');
    like($report, qr/FILE PERMISSIONS AUDIT/i, 'report has header');
    like($report, qr/\Q$tmpdir\E/, 'report contains target path');
};

done_testing();
