package HBPerl::Scripts::BackupManager;
# ============================================================================
# Backup manager — tar/gzip backups with rotation and integrity checks
# ============================================================================
use strict;
use warnings;
use File::Find;
use File::Basename;
use File::Spec;
use File::Copy;
use Archive::Tar;
use Digest::SHA;
use POSIX qw(strftime);
use HBPerl::Util qw(format_bytes);

sub run {
    my (%args) = @_;
    my $action  = $args{action}   // 'list';      # list | create | verify | rotate
    my $source  = $args{source};                   # directory to back up
    my $dest    = $args{dest}     // '/tmp/hb_backups';
    my $keep    = $args{keep}     // 5;            # how many rotations to keep
    my $prefix  = $args{prefix}   // 'backup';
    my $exclude = $args{exclude}  // [];           # patterns to exclude

    my %result = (action => $action);

    if ($action eq 'list') {
        $result{backups} = _list_backups($dest, $prefix);
    }
    elsif ($action eq 'create') {
        die "Source directory required for create\n" unless $source && -d $source;
        mkdir $dest unless -d $dest;
        $result{backup} = _create_backup($source, $dest, $prefix, $exclude);
    }
    elsif ($action eq 'verify') {
        my $file = $args{file};
        die "Backup file required for verify\n" unless $file;
        $result{verify} = _verify_backup($file);
    }
    elsif ($action eq 'rotate') {
        $result{rotation} = _rotate_backups($dest, $prefix, $keep);
    }

    return \%result;
}

sub format_report {
    my ($result) = @_;

    my $report = <<"EOF";
╔══════════════════════════════════════════════════════════════╗
║                   BACKUP MANAGER                              ║
╚══════════════════════════════════════════════════════════════╝

EOF

    my $action = $result->{action} // 'unknown';

    if ($action eq 'list') {
        $report .= "── Available Backups ─────────────────────────────────────────\n";
        my @bk = @{$result->{backups} // []};
        if (@bk) {
            $report .= sprintf("  %-40s %-10s %s\n", 'Filename', 'Size', 'Created');
            $report .= "  " . ("-" x 68) . "\n";
            for my $b (@bk) {
                $report .= sprintf("  %-40s %-10s %s\n",
                    $b->{name}, _fmt_bytes($b->{size}), $b->{mtime});
            }
        } else {
            $report .= "  No backups found.\n";
        }
    }
    elsif ($action eq 'create') {
        my $b = $result->{backup};
        $report .= "── Backup Created ────────────────────────────────────────────\n";
        $report .= "  Source:     $b->{source}\n";
        $report .= "  Archive:    $b->{file}\n";
        $report .= "  Size:       " . _fmt_bytes($b->{size}) . "\n";
        $report .= "  Files:      $b->{file_count}\n";
        $report .= "  SHA256:     $b->{sha256}\n";
        $report .= "  Duration:   $b->{duration}s\n";
    }
    elsif ($action eq 'verify') {
        my $v = $result->{verify};
        my $status = $v->{valid} ? '✔ VALID' : '✘ INVALID';
        $report .= "── Backup Verification ───────────────────────────────────────\n";
        $report .= "  File:       $v->{file}\n";
        $report .= "  Status:     $status\n";
        $report .= "  Files:      $v->{file_count}\n" if $v->{valid};
        $report .= "  SHA256:     $v->{sha256}\n" if $v->{sha256};
        $report .= "  Error:      $v->{error}\n" if $v->{error};
    }
    elsif ($action eq 'rotate') {
        my $r = $result->{rotation};
        $report .= "── Backup Rotation ───────────────────────────────────────────\n";
        $report .= "  Kept:       $r->{kept}\n";
        $report .= "  Removed:    $r->{removed}\n";
        if (@{$r->{removed_files} // []}) {
            $report .= "  Removed files:\n";
            for my $f (@{$r->{removed_files}}) {
                $report .= "    - $f\n";
            }
        }
    }

    return $report;
}

sub _create_backup {
    my ($source, $dest, $prefix, $exclude) = @_;
    my $start = time();
    my $ts = strftime('%Y%m%d_%H%M%S', localtime());
    my $basename = "${prefix}_${ts}.tar.gz";
    my $outfile  = File::Spec->catfile($dest, $basename);

    # Collect files
    my @files;
    my %excl = map { $_ => 1 } @$exclude;

    find({
        no_chdir => 1,
        wanted   => sub {
            my $rel = File::Spec->abs2rel($_, $source);
            return if $rel eq '.';
            for my $pattern (keys %excl) {
                return if $rel =~ /$pattern/;
            }
            push @files, { abs => $_, rel => $rel } if -f $_;
        }
    }, $source);

    # Create tar.gz
    my $tar = Archive::Tar->new;
    for my $f (@files) {
        $tar->add_files($f->{abs});
        # Rename to relative path inside archive
        my @items = $tar->get_files($f->{abs});
        if (@items) {
            $items[-1]->rename($f->{rel});
        }
    }
    $tar->write($outfile, Archive::Tar::COMPRESS_GZIP());

    # Calculate checksum
    my $sha = Digest::SHA->new(256);
    $sha->addfile($outfile, 'b');
    my $digest = $sha->hexdigest;

    # Write checksum file
    my $ckfile = "$outfile.sha256";
    if (open my $fh, '>', $ckfile) {
        print $fh "$digest  $basename\n";
        close $fh;
    }

    my $size = -s $outfile // 0;
    my $duration = time() - $start;

    return {
        file       => $outfile,
        source     => $source,
        size       => $size,
        file_count => scalar @files,
        sha256     => $digest,
        duration   => $duration,
    };
}

sub _verify_backup {
    my ($file) = @_;
    my %v = (file => $file, valid => 0);

    unless (-f $file) {
        $v{error} = "File not found: $file";
        return \%v;
    }

    # Check SHA256 if checksum file exists
    my $ckfile = "$file.sha256";
    if (-f $ckfile) {
        my $sha = Digest::SHA->new(256);
        eval { $sha->addfile($file, 'b') };
        if ($@) {
            $v{error} = "Cannot read file: $@";
            return \%v;
        }
        my $digest = $sha->hexdigest;
        $v{sha256} = $digest;

        if (open my $fh, '<', $ckfile) {
            my $line = <$fh>;
            close $fh;
            if ($line && $line =~ /^([a-f0-9]+)/) {
                my $expected = $1;
                unless ($digest eq $expected) {
                    $v{error} = "Checksum mismatch! Expected $expected";
                    return \%v;
                }
            }
        }
    }

    # Try to list archive contents
    eval {
        my $tar = Archive::Tar->new($file, Archive::Tar::COMPRESS_GZIP());
        my @contents = $tar->list_files;
        $v{file_count} = scalar @contents;
        $v{valid} = 1;
    };
    if ($@) {
        $v{error} = "Archive corrupted: $@";
        return \%v;
    }

    return \%v;
}

sub _list_backups {
    my ($dest, $prefix) = @_;
    my @backups;
    return \@backups unless -d $dest;

    opendir my $dh, $dest or return \@backups;
    while (my $entry = readdir $dh) {
        next unless $entry =~ /^\Q$prefix\E.*\.tar\.gz$/;
        my $path = File::Spec->catfile($dest, $entry);
        my @st = stat($path);
        push @backups, {
            name  => $entry,
            path  => $path,
            size  => $st[7] // 0,
            mtime => $st[9] ? strftime('%Y-%m-%d %H:%M:%S', localtime($st[9])) : 'unknown',
        };
    }
    closedir $dh;

    @backups = sort { $b->{mtime} cmp $a->{mtime} } @backups;
    return \@backups;
}

sub _rotate_backups {
    my ($dest, $prefix, $keep) = @_;
    my $all = _list_backups($dest, $prefix);
    my @sorted = @$all;   # already sorted newest-first
    my @removed_files;
    my $removed = 0;

    if (@sorted > $keep) {
        my @to_remove = splice @sorted, $keep;
        for my $b (@to_remove) {
            if (unlink $b->{path}) {
                push @removed_files, $b->{name};
                $removed++;
                # Also remove checksum file
                my $ck = "$b->{path}.sha256";
                unlink $ck if -f $ck;
            }
        }
    }

    return {
        kept          => scalar(@sorted),
        removed       => $removed,
        removed_files => \@removed_files,
    };
}

# _fmt_bytes is provided by HBPerl::Util::format_bytes
sub _fmt_bytes { goto &format_bytes }

1;

__END__

=head1 NAME

HBPerl::Scripts::BackupManager - Backup creation, verification and rotation

=head1 SYNOPSIS

    use HBPerl::Scripts::BackupManager;

    # Create a backup
    my $r = HBPerl::Scripts::BackupManager::run(
        action  => 'create',
        source  => '/etc',
        dest    => '/var/backups',
        prefix  => 'etc',
        exclude => '*.tmp',
    );
    print HBPerl::Scripts::BackupManager::format_report($r);

=head1 DESCRIPTION

Creates tar/gzip archives of directories with SHA256 integrity
verification, listing of existing backups, and rotation of old
archives.

=head1 EXPORTED FUNCTIONS

=over 4

=item B<run(%args)>

Parameters: C<action> (list|create|verify|rotate), C<source>, C<dest>,
C<keep> (number of backups to retain), C<prefix>, C<exclude> (glob
pattern), C<file> (for verify).

Returns a hash-ref with C<success>, C<action>, and action-specific
result keys.

=item B<format_report($result)>

Format the hash-ref from C<run()> as a human-readable report string.

=back

=head1 AUTHOR

James Temple <james@amiga-fan.net>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2026 Honey Badger Universe

MIT License

=cut
