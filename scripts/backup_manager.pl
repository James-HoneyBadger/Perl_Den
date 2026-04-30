#!/usr/bin/env perl
# ============================================================================
# backup_manager.pl — Create, verify, list, and rotate backups
# Usage: backup_manager.pl --action create --source /path --dest /backup
#        backup_manager.pl --action list   --dest /backup
#        backup_manager.pl --action verify --file /backup/archive.tar.gz
#        backup_manager.pl --action rotate --dest /backup --keep 5
# ============================================================================
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use BadgerOps::Scripts::BackupManager;

my $action = 'list';
my $source;
my $dest   = '/tmp/hb_backups';
my $keep   = 5;
my $prefix = 'backup';
my $file;
my $help;

GetOptions(
    'action=s' => \$action,
    'source=s' => \$source,
    'dest=s'   => \$dest,
    'keep=i'   => \$keep,
    'prefix=s' => \$prefix,
    'file=s'   => \$file,
    'help|h'   => \$help,
) or die "Usage: $0 --action <list|create|verify|rotate> [options]\n";

if ($help) {
    print "Usage: $0 --action <list|create|verify|rotate> [options]\n";
    print "  --source DIR    Source directory to back up\n";
    print "  --dest DIR      Destination for backups (default: /tmp/hb_backups)\n";
    print "  --keep N        Number of backups to retain (default: 5)\n";
    print "  --prefix STR    Backup filename prefix (default: backup)\n";
    print "  --file FILE     Specific archive to verify\n";
    print "Create, verify, list, and rotate backups.\n";
    exit 0;
}

my $result = BadgerOps::Scripts::BackupManager::run(
    action => $action,
    source => $source,
    dest   => $dest,
    keep   => $keep,
    prefix => $prefix,
    file   => $file,
);
print BadgerOps::Scripts::BackupManager::format_report($result);
