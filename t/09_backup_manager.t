#!/usr/bin/env perl
# ============================================================================
# t/09_backup_manager.t — Test PerlDen::Scripts::BackupManager
# ============================================================================
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);

use_ok('PerlDen::Scripts::BackupManager');

my $src_dir  = tempdir(CLEANUP => 1);
my $dest_dir = tempdir(CLEANUP => 1);

# Create test files
for my $i (1..3) {
    open my $fh, '>', "$src_dir/file_$i.txt" or die $!;
    print $fh "Content of file $i\n" x 100;
    close $fh;
}
mkdir "$src_dir/sub";
open my $fh, '>', "$src_dir/sub/nested.txt" or die $!;
print $fh "nested content\n";
close $fh;

subtest 'create backup' => sub {
    my $result = PerlDen::Scripts::BackupManager::run(
        action => 'create',
        source => $src_dir,
        dest   => $dest_dir,
        prefix => 'test',
    );
    ok(ref $result eq 'HASH', 'returns hashref');
    my $b = $result->{backup};
    ok($b, 'backup info exists');
    ok(-f $b->{file}, 'archive file created');
    is($b->{file_count}, 4, 'correct file count');
    ok(length($b->{sha256}) == 64, 'SHA256 hash present');
    ok(-f "$b->{file}.sha256", 'checksum file created');
};

subtest 'list backups' => sub {
    my $result = PerlDen::Scripts::BackupManager::run(
        action => 'list',
        dest   => $dest_dir,
        prefix => 'test',
    );
    my @bk = @{$result->{backups}};
    cmp_ok(scalar @bk, '>=', 1, 'at least one backup listed');
    ok($bk[0]{name} =~ /^test_/, 'backup name has prefix');
};

subtest 'verify backup' => sub {
    my $list = PerlDen::Scripts::BackupManager::run(
        action => 'list', dest => $dest_dir, prefix => 'test');
    my $file = $list->{backups}[0]{path};

    my $result = PerlDen::Scripts::BackupManager::run(
        action => 'verify',
        file   => $file,
    );
    my $v = $result->{verify};
    ok($v->{valid}, 'backup is valid');
    is($v->{file_count}, 4, 'archive has 4 files');
};

subtest 'rotate backups' => sub {
    # Create a second backup with a distinct timestamp
    sleep 1;
    PerlDen::Scripts::BackupManager::run(
        action => 'create', source => $src_dir,
        dest => $dest_dir, prefix => 'test');

    my $result = PerlDen::Scripts::BackupManager::run(
        action => 'rotate',
        dest   => $dest_dir,
        prefix => 'test',
        keep   => 1,
    );
    my $r = $result->{rotation};
    is($r->{kept}, 1, 'kept 1 backup');
    cmp_ok($r->{removed}, '>=', 1, 'removed at least 1');
};

subtest 'format_report works' => sub {
    my $r = PerlDen::Scripts::BackupManager::run(
        action => 'list', dest => $dest_dir, prefix => 'test');
    my $report = PerlDen::Scripts::BackupManager::format_report($r);
    ok(length($report) > 50, 'report has content');
    like($report, qr/BACKUP/i, 'report has backup header');
};

done_testing();
